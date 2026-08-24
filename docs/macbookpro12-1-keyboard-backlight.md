# MacBookPro12,1 Keyboard Backlight Keys (F5/F6)

**Status:** solved with a system-level `actkbd` service (see "Fix"), committed
to the repo as `config/actkbd/`. Applied and verified on archeus.

## Summary

The F5/F6 keyboard-backlight keys did not work in the base tty1 (they only
work inside Hyprland after a binding is added). The fix is a **system-level**
`actkbd` service that steps `smc::kbd_backlight` from the raw evdev events.
Because it reads evdev globally, it works at tty1, at the login prompt, and
inside Hyprland alike - no per-desktop binding needed.

## Why the brightness keys only work inside Hyprland

On this MacBook all top-row function keys are routed through the SPI keyboard
controller (`applespi`): F1/F2 -> `KEY_BRIGHTNESSDOWN`/`KEY_BRIGHTNESSUP`
(applespi.c:479-480), F5/F6 -> `KEY_KBDILLUMDOWN`/`KEY_KBDILLUMUP`
(applespi.c:483-484). Every one of them is a plain evdev event with no
in-kernel consumer - so at a bare tty1 nothing reacts to any of them. Inside
Hyprland the screen keys work only because `config/hypr/hyprland.lua` binds
`XF86MonBrightnessUp/Down` to `brightnessctl` (lines 220-221); nothing binds
the keyboard keys. (The kernel's ACPI-video notify handler that makes screen
keys work at the console on other laptops does not fire on this hardware.)

## Findings

- **`applespi`** maps F5/F6 to keycodes 229/230 and registers the `spi::kbd_backlight`
  LED class device (applespi.c:1687, name `Apple SPI Keyboard`, phys
  `applespi/input0`).
- **`applesmc`** registers `smc::kbd_backlight` (SMC key `LKSB`); on the 2015
  13" MBP (12,1) this is the working control path (CachyOS forum report for
  exactly this model on a vanilla Arch kernel).
- **No `brightness_get`:** applesmc implements only `brightness_set`
  (applesmc.c:1069-1072), so the sysfs `brightness` file reflects the last
  value written through the LED core, not the hardware state. Relative
  brightnessctl steps therefore misbehave after boot; `kbd-backlight-step`
  tracks state via the LED core cache instead.
- Kernel config: `CONFIG_KEYBOARD_APPLESPI=m`, `CONFIG_SENSORS_APPLESMC=m`,
  `CONFIG_LEDS_CLASS=y`. Present in Arch's default config, so the locally
  rebuilt kernel has them too. Nothing to enable.

## Fix (in this repo)

Files under `config/actkbd/`, deployed to `/etc` by `build/system-config.sh`:

- `actkbd.conf` - binds 229 (`F5`, down) and 230 (`F6`, up) to
  `kbd-backlight-step`.
- `kbd-backlight-step` - steps `smc::kbd_backlight` via sysfs: 10% on a key
  press, 2% on repeat (so holding F5/F6 ramps quickly).
- `actkbd.service` - systemd unit pointing at udev's own by-path symlink
  `/dev/input/by-path/pci-0000:00:15.4-cs-00-event-kbd` (created by
  `/usr/lib/udev/rules.d/60-persistent-input.rules`, so it does not depend on
  boot-order-dependent `/dev/input/eventN`). Enabled at `multi-user.target`.
  `ExecStartPre` waits for the node before the daemon starts - see the fopen
  race below.

No custom udev rule: an earlier version created its own
`/dev/input/actkbd-kbd` symlink and started the service from the rule
(`SYSTEMD_WANTS`), but `udevadm trigger` does not reliably re-create a symlink
that was removed on an already-running box, which wedged the daemon. Using
udev's own by-path link removes that failure mode entirely.

The fopen race: actkbd opens its device with `fopen("a+")` (linux.c:100),
which CREATES a regular file if the path does not exist yet. Reading it then
hits EOF with errno=0, i.e. `Error: failed to read event from ...: Success`.
So the daemon must never run against a missing node - `ExecStartPre` enforces
that, and the same warning applies to any manual `actkbd` test run.

The Hyprland `XF86KbdBrightness*` binds previously drafted here are dropped:
with actkbd reading the device globally, Hyprland binds would double-step.

## Backlight at the LUKS prompt (boot floor)

The F5/F6 daemon only helps once the booted system is up; the LUKS passphrase
prompt runs inside the initramfs, before any service. Worse: `applesmc`
registers its LED with `brightness_set` only (applesmc.c:1069-1072), so when
the module loads the LED core initializes the backlight OFF - observed as lit
at GRUB, off at LUKS, then on again after boot.

The fix is `config/modprobe.d/kbd-backlight.conf`, an `install` reroute for
`applesmc` (the same mechanism as the SPI reroute, docs/macbookpro12-1-
keyboard-spi-fix.md:119). It loads the real module, then writes ~50% of
`max_brightness` to the LED. Because `modconf` bundles `/etc/modprobe.d` into
the initramfs, the directive fires right after applesmc loads - before the LUKS
prompt - and at every modprobe in the booted system.

A udev rule was tried first (`/etc/udev/rules.d/10-kbd-backlight-boot.rules`):
it reliably fired in the booted system but not inside the initramfs, leaving
the backlight off at LUKS. The modprobe.d reroute replaces it.

One edit stays in `/etc` by hand (the boot layer is documented, not
repo-managed):

1. `/etc/mkinitcpio.conf`: make sure `applesmc` is in the initramfs so the SMC
   LED exists before the prompt. If the SPI stack is carried in
   `MODULES=(...)`, append it there - `MODULES=(acpi_call spi_pxa2xx_platform
   spi_pxa2xx_pci applespi applesmc)`. If the `apple-spi` install hook is used
   instead (`MODULES=()`), add `applesmc` to that hook's `add_module`.
2. The image itself is rebuilt automatically: `build/system-config.sh` compares
   each `config/modprobe.d/*.conf` against its `/etc/modprobe.d/` copy and runs
   `sudo mkinitcpio -P` only when something changed (backing up the previous
   images to `/var/backup/initramfs-pre-modprobe` first).

## Screen brightness keys (F1/F2)

applespi maps F1/F2 to `KEY_BRIGHTNESSDOWN`/`KEY_BRIGHTNESSUP` (224/225),
plain evdev events with no in-kernel handler - so at a bare tty1 nothing
reacted, exactly like the keyboard backlight. actkbd now owns them too
(`config/actkbd/actkbd.conf`) via `brightnessctl set +/-5%`, with `key,rep`
so holding the key repeats. Unlike the SMC backlight, the screen backlight
exposes a working `brightness_get`, so relative steps are safe.

The Hyprland `XF86MonBrightnessUp/Down` binds were removed
(`config/hypr/hyprland.lua`): actkbd reads the device globally, so keeping
them would double-step.

The screen starts at 50% in the booted system: `config/modprobe.d/backlight-
screen.conf` reroutes `i915` (which provides `intel_backlight`) and writes
half of `max_brightness` once the device appears. Unlike the keyboard LED this
is a one-shot set (the backlight exposes `brightness_get`), not a floor
re-assertion. The LUKS prompt keeps the firmware brightness - `i915` is not in
the initramfs, and loading the GPU there would change how the console renders
for little gain; the reroute would cover LUKS automatically if `i915` were
ever added to `MODULES=`.

## Setup on archeus

```sh
# 1. AUR helper (one-time) - paru recommended, see docs/arch-setup-mac.md
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git ~/build/paru && cd ~/build/paru && makepkg -si

# 2. System packages (actkbd, brightnessctl) from the tracked lists
./build/system-packages.sh

# 3. Deploy config + unit + modprobe.d boot floor (rebuilds the initramfs
#    itself when the boot floor changed)
./build/system-config.sh

# 4. (Only needed on first setup) after adding applesmc to MODULES= - see
#    "Backlight at the LUKS prompt"
sudo mkinitcpio -P
```

`system-config.sh` refuses to start if the by-path symlink is missing (it
lists `/dev/input/by-path/` for debugging), and it cleans up the stale
custom-udev-rule version of this setup if one was deployed before.

Verify:

```sh
systemctl status actkbd.service
sudo actkbd -n -s -d /dev/input/by-path/pci-0000:00:15.4-cs-00-event-kbd   # press F5/F6, expect keycodes 229/230
cat /sys/class/leds/smc::kbd_backlight/brightness   # changes on F5/F6
```

Caveat: the LED core cache starts at 0 at boot (applesmc has no
`brightness_get`), so the modprobe.d boot floor re-asserts 50%
(`config/modprobe.d/kbd-backlight.conf`); the first F5/F6 press then steps
from there rather than from the hardware state.

## References

- `drivers/input/keyboard/applespi.c` (mainline): F5/F6 translation, input
  device name/phys, `spi::kbd_backlight` registration.
- `drivers/hwmon/applesmc.c` (mainline): `smc::kbd_backlight`, `LKSB` key,
  `brightness_set`-only LED classdev.
- `drivers/acpi/acpi_video.c` (mainline): native screen-brightness notify
  handling - does NOT fire on this hardware, which is why no top-row key works
  at a bare console.
- `include/uapi/linux/input-event-codes.h`: `KEY_KBDILLUMDOWN=229`,
  `KEY_KBDILLUMUP=230`.
- actkbd upstream README: <https://github.com/thkala/actkbd> (config format,
  `-n -s` keycode mode). AUR package: <https://aur.archlinux.org/packages/actkbd>.
- CachyOS forum, "Keyboard Backlight not working on macbook pro 12,1":
  <https://discuss.cachyos.org/t/keyboard-backlight-not-working-on-macbook-pro-12-1-with-cachyos-kernel/9181>
