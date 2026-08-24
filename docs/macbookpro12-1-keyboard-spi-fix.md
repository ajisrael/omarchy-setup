# MacBookPro12,1 Internal Keyboard/Trackpad - SPI + PIO Fix

## Purpose

Companion to `docs/arch-setup-mac.md` (install guide that bakes this in,
with the full investigation) and
`docs/macbookpro12-1-keyboard-kernel-patch.md` (the local kernel patch).
This document explains why the internal keyboard/trackpad die under Linux on
this 2015 13" MacBook Pro, documents the two-part fix, and gives a cheap
runtime test to prove it works before making it permanent.

## The problem, in one paragraph

This model's keyboard/trackpad controller is **dual-mode** - the same
physical pins carry either a USB or an SPI signal, switched by ACPI GPIO
methods (`UIEN`/`UIST` for USB, `SIEN`/`SIST` for SPI). Two independent bugs
conspire to leave the keyboard unclaimed:

1. **The driver backs off because ACPI reports a lie.** Apple's EFI firmware
   leaves the electrical switch on SPI from power-on (proven by reading the
   xHCI `portsc` register pre-boot from the GRUB shell: `usb1-port5` never
   shows a device, `CCS=0`, even while the keyboard works). But Linux's ACPI
   tables still report `UIST=1` ("USB active"), so the mainlined `applespi`
   driver logs `USB interface already enabled` and returns `-ENODEV`
   (`applespi.c:1616-1622`) without ever calling `SIEN(1)`. Nothing claims
   the keyboard.
2. **Even forced into SPI mode, transfers time out.** When `SIEN(1)` is
   called manually, `applespi` binds and registers an input device - but
   every SPI transfer fails with `SPI transfer timed out` / `-110`. The SPI
   controller (`00:15.4`, `spi-pxa2xx-pci`, PCI ID `0x9ce6`) is wired to the
   DesignWare DMA engine (`00:15.0`, `dw_dmac_pci`), and Apple's EFI
   firmware holds that DMA block in permanent reset (`LPSS_PRIV_RESETS =
   0x0` at BAR0+0x204), so DMA-backed transfers never complete. The fix is to
   force the SPI controller into **PIO** (no-DMA) mode - which is exactly how
   Apple's own firmware drives the keyboard, and why it works in GRUB and
   macOS Recovery.

So the fix has two independent parts, both required:
- Call `SIEN(1)` (via `acpi_call`) before `applespi` probes.
- Force PIO by making the `dw_dmac_pci` DMA driver unavailable.

## Upstream status (as of 2026-07)

Shih-Yuan Lee's series - "spi: pxa2xx: disable DMA for Apple MacBook8,1",
plus LPSS runtime-PM and S3-resume fixes - is at v16 (2026-07-20/21), in
review on `linux-spi`, and **not in mainline**. The author confirmed via
direct MMIO inspection that EFI permanently holds the LPSS DMA block in
reset, making the forced-PIO DMI quirk the accepted fix. The series' DMI
table matches **MacBook8,1 only**, so MacBookPro12,1 still needs a local
equivalent (this document) or a follow-up DMI entry.

- Series cover letter: <https://lore.kernel.org/linux-spi/20260720162117.32304-1-fourdollars@debian.org/>
- Patch "disable DMA for Apple MacBook8,1" (v16 5/7):
  <https://lore.kernel.org/linux-spi/20260720162117.32304-6-fourdollars@debian.org/>
- EFI-held-in-reset confirmation (2026-07-26 reply):
  <https://lists.openwall.net/linux-kernel/2026/07/26/503>
- Kernel Bugzilla: <https://bugzilla.kernel.org/show_bug.cgi?id=108331>
- Fedora thread, identical A1502 symptom:
  <https://discussion.fedoraproject.org/t/macbook-pro-12-a1502-internal-keyboard-trackpad-not-working-only-using-external-usb-keyboard-and-mouse/196957>
- MacBookAir 2015 (MacBookAir7,2) - same controller, same mode-switch
  mechanism, and the modprobe `install`-reroute pattern this fix reuses:
  <https://github.com/robertogogoni/claude-cross-machine-sync/commit/bd93b7754ba2d573f50d1ae4a02574c61124a4a6>

Once the series merges (ideally with MacBookPro12,1 added to its DMI table),
the local steps below can be removed.

## Quick runtime test (no rebuild, no initramfs change)

Proves the fix before you bake it in. Requirements: a booted system where
the SPI stack is NOT currently loaded (the existing broken install with the
old applespi blacklist, or a fresh stock boot), an external USB keyboard,
and `acpi_call` installed (`pacman -S acpi_call-dkms`). Run as root.

```bash
rm -f /etc/modprobe.d/blacklist-applespi.conf          # old wrong advice in the base guide
modprobe -r applespi spi_pxa2xx_pci spi_pxa2xx_platform 2>/dev/null

modprobe acpi_call
echo "\\_SB.PCI0.SPI1.SPIT.SIEN 1" > /proc/acpi/call
echo "\\_SB.PCI0.SPI1.SPIT.SIST" > /proc/acpi/call && cat /proc/acpi/call    # expect 0x1
echo "\\_SB.PCI0.SPI1.SPIT.UIST" > /proc/acpi/call && cat /proc/acpi/call    # expect 0x0

printf 'blacklist dw_dmac_pci\nblacklist dw_dmac_core\n' > /etc/modprobe.d/blacklist-lpss-dma.conf
modprobe -r dw_dmac_pci dw_dmac_core 2>/dev/null       # ignore failure: only matters if they were loaded

modprobe spi_pxa2xx_platform spi_pxa2xx_pci applespi
```

Then verify:

```bash
dmesg | grep -Ei 'applespi|pxa2xx' | tail -30
lsmod | grep dw_dmac          # expect empty
```

Expected: `applespi` binds to `spi-APP000D:00`, registers `Apple SPI
Keyboard` and `Apple SPI Touchpad` input devices, and `spi-pxa2xx` logs
`no DMA channels available, using PIO`. There must be NO `SPI transfer
timed out` / `Error reading from device: -110`. Type on the internal
keyboard - keystrokes and trackpad should work.

If `modprobe -r dw_dmac_*` fails (driver in use), reboot once with the
blacklist file in place before retrying the `modprobe spi... applespi` step.

This test is the missing proof step for this exact model: the SIEN(1)
binding and the `-110` timeout are both already documented on this machine
(issue doc, step 19); PIO mode on MacBookPro12,1 has not yet been observed
end-to-end. It is strongly inferred from the chipset-identical MacBook8,1
diagnosis, but the test above is what confirms it.

## Making it permanent (fresh install)

Follow `docs/arch-setup-mac.md`. In summary, four config pieces plus
an initramfs rebuild:

1. `pacman -S acpi_call-dkms`
2. `/etc/modprobe.d/blacklist-lpss-dma.conf` -> `blacklist dw_dmac_pci`,
   `blacklist dw_dmac_core` (forces PIO)
3. `/etc/modprobe.d/apple-keyboard-spi.conf` -> modprobe `install` reroute
   that runs `SIEN(1)` via `acpi_call` before every `applespi` load
4. `/etc/udev/rules.d/60-spi-pio.rules` -> pin SPI controller
   (`0x9ce6`) runtime PM to `on` (see caveats)
5. `/etc/mkinitcpio.conf`: `MODULES=(acpi_call spi_pxa2xx_platform
   spi_pxa2xx_pci applespi)`, HOOKS unchanged, then `mkinitcpio -P` and
   `grub-mkconfig -o /boot/grub/grub.cfg`

The `install` reroute is the load-order guarantee: whenever `applespi` is
modprobed - including inside the initramfs via the `modconf` hook + kmod
modprobe - the `SIEN(1)` call runs first, so `applespi` sees SPI active and
proceeds instead of backing off.

Escaping trap: the reroute file MUST contain `\\_SB` (two backslashes).
kmod's `modprobe.d` parser strips one backslash level before the shell sees
the command, so a single `\_SB` arrives as the relative path `_SB...`,
`acpi_get_handle` rejects it (`acpi_call: Cannot get handle: Error:
AE_BAD_PARAMETER`), and `applespi` keeps bailing with `USB interface
already enabled`. An interactive shell has no such problem - only
`modprobe.d` files. Whenever you edit the reroute file, re-run
`mkinitcpio -P`: the initramfs carries its own baked-in copy, and a stale
copy is a silent reintroduction of the dead-keyboard bug.

## If the keyboard works after login but not at the LUKS prompt

With the reroute escaping fixed, the reroute covers the LUKS prompt:
`modconf` bundles `/etc/modprobe.d` into the image, and when `applespi` is
modprobed in the initramfs, kmod fires the `install` reroute (`SIEN(1)`
first, then the real `applespi` load). Confirmed 2026-08: keyboard working
at the LUKS prompt and after login.

The initcpio hook used before the escaping fix had two halves with very
different fates under the `systemd` initramfs:

- **The install file's `build()`/`add_module` is load-bearing.** It runs at
  image-build time and is what pulled `acpi_call` (a DKMS module that
  `autodetect` cannot see) and the SPI stack into the image. Removing the
  hook while leaving `MODULES=()` silently drops those modules from the
  initramfs and re-breaks the keyboard: the reroute's `modprobe --ignore-
  install acpi_call` finds nothing, SIEN never runs, `applespi` bails with
  `USB interface already enabled`. Either keep the hook's install file, or
  carry the modules explicitly: `MODULES=(acpi_call spi_pxa2xx_platform
  spi_pxa2xx_pci applespi)`.
- **The hook script's `run_hook` does NOT execute.** The `systemd`
  initramfs contains no `/usr/bin/bash` (mkinitcpio warns `Possibly missing
  '/usr/bin/bash' for script: /etc/initcpio/hooks/apple-spi` at build), so
  a `#!/usr/bin/bash` `run_hook` never runs. Observed on this machine with
  the hook files present and `apple-spi` correctly placed in HOOKS. It only
  works on non-`systemd` (busybox `base`) initramfs configurations, where
  hooks are sourced by `/bin/sh` instead of executed.

`/etc/initcpio/hooks/apple-spi`:

```bash
#!/usr/bin/bash

run_hook() {
    modprobe -q acpi_call
    echo "\\_SB.PCI0.SPI1.SPIT.SIEN 1" > /proc/acpi/call
    modprobe spi_pxa2xx_platform spi_pxa2xx_pci applespi
}
```

`/etc/initcpio/install/apple-spi`:

```bash
#!/usr/bin/bash

build() {
    add_module acpi_call spi_pxa2xx_platform spi_pxa2xx_pci applespi
    add_runscript
}

help() {
    echo "Switch Apple keyboard to SPI mode (SIEN 1) and load the SPI stack before LUKS"
}
```

```bash
chmod +x /etc/initcpio/hooks/apple-spi /etc/initcpio/install/apple-spi
```

In `/etc/mkinitcpio.conf`, when using the hook: set `MODULES=()` (drop the
SPI modules - the hook loads them in the right order) and insert `apple-spi`
into HOOKS before `sd-encrypt`:

```bash
HOOKS=(base systemd autodetect microcode modconf kms keyboard apple-spi sd-vconsole block sd-encrypt filesystems fsck)
```

Then `mkinitcpio -P`. Keep the `dw_dmac` blacklist either way.

## Caveats and open questions

- **The end-to-end PIO result on MacBookPro12,1 was confirmed in 2026-08:**
  the runtime test passed (`modeswitch done` + working keyboard) and the
  boot log shows `pxa2xx_spi_pci 0000:00:15.4: MacBookPro12,1 detected:
  disabling DMA to force PIO mode` from inside the initramfs.
- **`modprobe.d` escaping.** The reroute file must contain `\\_SB` (two
  backslashes) - kmod strips one before the shell sees the command. A
  single `\_SB` becomes the relative `_SB...`, fails with `Cannot get
  handle: Error: AE_BAD_PARAMETER`, and `applespi` never gets the mode
  switch. The identical string is fine from an interactive shell, which is
  why the manual test passes while the boot still fails.
- **Runtime PM caveat on stock kernels.** The upstream series also fixes a
  bug where, in PIO mode, aggressive runtime clock gating causes PCIe
  Completion Timeouts on subsequent MMIO accesses. On a stock kernel the
  udev `power/control=on` rule (step 4) sidesteps it by never letting the
  SPI controller autosuspend. Long-term, a kernel with the upstream series
  removes the need for that rule.
- **Sleep/wake.** Deep sleep (S3) also kills the keyboard/trackpad until
  reboot - a separate bug (LPSS private registers reset, never restored).
  Either sleep with s2idle or apply the local
  `build/0002-spi-pxa2xx-lpss-s3-resume.patch`. See
  [macbookpro12-1-keyboard-s3-resume.md](macbookpro12-1-keyboard-s3-resume.md).
- **If `dw_dmac_pci` is built into the kernel** (`grep -c dw_dmac_pci
  /usr/lib/modules/*/modules.builtin` prints 1), the blacklist cannot
  remove it. Fall back to the
  [local kernel patch](macbookpro12-1-keyboard-kernel-patch.md) that adds
  MacBookPro12,1 to the upstream DMI quirk table. (Inside a chroot, use the
  glob form - not `$(uname -r)`, which reports the host kernel.)
- **Model-specific.** Do not apply this fix to MacBookPro11,x (keyboard is
  plain internal USB) or to MacBook8,1/9,1+ and Touch Bar models (their
  firmware reports the mode correctly; upstream's DMI quirk will cover the
  PIO half once merged).
