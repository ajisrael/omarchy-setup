# Omarchy 4.0.4 Upgrade Plan - Bespoke Kernel + Patch Stack Port

Status: **planned, not yet executed**. Written 2026-09-17 against
Omarchy 4.0.0-1 (installed) and v4.0.4 (latest stable, packages already live
on `pkgs.omarchy.org/stable`). No implementation has started.

Chosen direction: **Option A - embrace the Omarchy kernel and port the
MacBookPro12,1 SPI patch stack onto it.** Other options considered and
rejected: keep booting the patched stock `linux` (Option B - fights future
migrations over BOOT_ORDER and drifts further from the kernel Omarchy tests
against), and stay on 4.0.0 (Option C - no upside).

Companion docs: [macbookpro12-1-keyboard-kernel-patch.md](macbookpro12-1-keyboard-kernel-patch.md)
(current patch loop), [macbookpro12-1-keyboard-spi-fix.md](macbookpro12-1-keyboard-spi-fix.md),
[macbookpro12-1-keyboard-s3-resume.md](macbookpro12-1-keyboard-s3-resume.md).

## Situation at time of writing

| | |
|---|---|
| Omarchy installed | 4.0.0-1 |
| Latest stable | v4.0.4 (`omarchy 4.0.4-1` on the stable repo) |
| Kernel installed | `linux 7.1.10.arch1-1.1` - locally patched, `IgnorePkg = linux linux-headers linux-docs` in `/etc/pacman.conf` |
| Kernel incoming | `linux-omarchy 7.2.5-3` (also in repo: `linux-omarchy-bore`, `linux-omarchy-muqss`; default is plain) |
| Bootloader | Limine; `/etc/default/limine` has the LUKS `cryptdevice` cmdline; `KERNEL_CMDLINE[default]` currently plain |

### What `omarchy update` will do (verified against v4.0.4 source)

1. `pacman -Syu` upgrades `omarchy` to 4.0.4 and runs `omarchy-migrate`;
   ~85 migrations are pending.
2. Migration `1789325478` installs `linux-omarchy` + `linux-omarchy-headers`,
   then rewrites `/etc/default/limine`:
   - deletes any existing `BOOT_ORDER` and appends
     `BOOT_ORDER="linux-omarchy, linux-omarchy-*, *, *fallback, Snapshots"`
   - appends to `KERNEL_CMDLINE[default]`: `quiet splash loglevel=0 ...
     initramfs_async=0` (the defaults file at
     `/etc/limine-entry-tool.d/omarchy-defaults.conf` adds `CUSTOM_UKI_NAME="omarchy"`)
   - runs `limine-mkinitcpio linux-omarchy`
   - it exits early **only** for T2 Macs (`linux-t2` installed or running
     kernel is `-t2`) - MacBookPro12,1 is pre-T2, so it does **not** skip us
3. Migration `1789444024` installs `linux-omarchy-headers` (idempotent).

Net effect if done naively: next boot lands on linux-omarchy 7.2.5
**unpatched** - internal keyboard/trackpad dead. Mitigations already present:
the migration leaves the old kernel installed, the Limine menu keeps old
entries, a Snapper snapshot is taken before the update, and the LUKS cmdline
is preserved.

### Why port the patches instead of fearing them

- The patches are small and target stable code:
  - `0001-spi-pxa2xx-macbookpro12-1-pio.patch`: DMI match
    (`MacBookPro12,1`) in `drivers/spi/spi-pxa2xx-pci.c` forces
    `enable_dma = 0` (Apple's firmware holds the DMA block in reset on this
    model; the exact antagonist is the `dw_dmac_pci` DMA device).
  - `0002-spi-pxa2xx-lpss-s3-resume.patch`: LPSS private-reset fix in
    `drivers/spi/spi-pxa2xx.c` so the controller survives S3 resume.
- Both drivers are unchanged in 7.2.x as far as the driver architecture goes;
  expect context drift at most (`patch` fuzz or small rebases).
- Fallback exists at every step: old patched stock kernel stays bootable
  from the Limine menu.

### Unknown worth testing cheaply before porting

v4.0.4's release notes claim the new kernel fixes "unresponsive touchpads"
on affected machines. It is *possible* 7.2.5 fixes the MBP12,1 SPI/DMA issue
upstream (upstream "disable DMA for Apple MacBook" series was in review on
linux-spi as of 2026-07 - see the kernel-patch doc). If it did, we could
eventually drop the local patch loop entirely. Testing costs one boot.

## Execution plan

Do this in one sitting; the machine should be on AC power and all work
saved. Expect a 30-60+ min kernel build on the i5 (2 cores).

### Phase 0: Pre-flight (before any update)

1. Confirm state matches "situation at time of writing":
   `omarchy version`, `pacman -Q linux linux-headers`, `grep IgnorePkg
   /etc/pacman.conf`, `cat /etc/default/limine`.
2. Record the current backup story: `omarchy snapshot` (the update also
   takes one, but an explicit pre-update snapshot costs nothing).
3. Have an external USB keyboard plugged in for the whole session (cheap
   insurance; the stock kernel entry also survives, but don't gamble).
4. Verify the current patched kernel is what's running:
   `uname -r` == `pacman -Q linux | cut -d' ' -f2` version (7.1.10).

### Phase 1: The update itself

1. Run `omarchy update` (or via the omarchy-settings app: Update > Omarchy).
   Let it upgrade to 4.0.4 and run all migrations. Expect it to demand a
   reboot at the end - **do not reboot yet.**
2. Verify the migration did its thing:
   - `pacman -Q linux linux-omarchy linux-omarchy-headers`
     (both kernels present)
   - `grep BOOT_ORDER /etc/default/limine` (now points at linux-omarchy)
3. Do NOT reboot until Phase 2 is done (or unpatched 7.2.5 is deliberately
   being tested per Phase 2a).

### Phase 2a (optional test): Does 7.2.5 fix the SPI issue upstream?

1. Reboot into linux-omarchy **unpatched**.
2. Watch the internal keyboard at the LUKS prompt/login: `arm
   /dev/input/by-path/*spi*` or just press keys on the internal keyboard.
3. Outcome A - works: upstream fixed it. Skip the port; just note it in
   the kernel-patch doc and consider eventually removing the patch loop.
4. Outcome B - dead keyboard (expected, if history repeats): reboot, pick
   the stock `linux` entry in the Limine menu, proceed to Phase 2b.

### Phase 2b: Port the patches to linux-omarchy

1. Fetch the PKGBUILD source:
   ```
   git clone --depth 1 https://github.com/omacom-io/omarchy-pkgs
   cp -r omarchy-pkgs/pkgbuilds/linux-omarchy ~/build/linux-omarchy
   ```
   (Keep `~/build/linux` intact until the new stack is proven.)
2. Copy both current patches (`~/build/linux/0001-*.patch`,
   `0002-*.patch`) into the new dir and add them to `source=()` +
   `prepare()`, mirroring what `rebuild-patch.sh` does today. Do NOT
   replicate `sed`-style PKGBUILD surgery by hand every time - write
   `~/build/linux-omarchy/rebuild-omarchy-patch.sh` as a port of
   `~/build/linux/rebuild-patch.sh` (same skeleton: reset worktree, copy
   patches, insert into PKGBUILD, bump `pkgrel` to `X.1`, `updpkgsums`,
   `makepkg`, `pacman -U`). Differences to expect vs the Arch PKGBUILD:
   - Different PGP keys for the omarchy kernel's extra patch components -
     reuse the key-import loop unchanged.
   - No `.arch1` suffix in pkgver; `pkgrel=3` (or 6 on master) → bump to
     `3.1` style.
   - Omarchy's patch-set file list in `source=()` is longer; insert our
     two lines at the same point in the array.
3. Build + install: `MAKEFLAGS=-j$(nproc) makepkg -s && sudo pacman -U linux-omarchy-*.pkg.tar.zst`
   Glob covers `linux-omarchy`, `linux-omarchy-headers` (nothing else is
   generated by this PKGBUILD - `!debug`, no docs package).
4. Rebuild the boot entry: `sudo limine-mkinitcpio linux-omarchy`.
5. Sanity-check `sudo limine-entry-tool --tree` shows linux-omarchy with
   the new pkgrel.

### Phase 3: Boot and verify

1. Reboot. If 2a was skipped: first boot goes straight to the now-patched
   linux-omarchy (BOOT_ORDER already points at it).
2. Verify: internal keyboard types at LUKS and login; trackpad responds;
   then suspend-to-RAM (S3) once and resurfacing restores both (validates
   the 0002 patch port).
3. Confirm these still hold for the system layer:
   - `sudo systemctl status ac-stay-awake waynergy`
   - keyboard backlight stepping (`actkbd`) and brightness keys
   - Omarchy themes/migrations healthy: `hyprctl configerrors` clean.

### Phase 4: Make it permanent

1. Add `/etc/pacman.conf` IgnorePkg: append `linux-omarchy
   linux-omarchy-headers` (keep the stock trio too until the old kernel is
   finally retired - see note below weighing it).
   Note: omarchy's updater ships a pacman.conf-protection hook
   (`/etc/pacman.d/hooks/` keep-ignorepkg) - verify it still covers the
   new entries (`grep -r ignorepkg /etc/pacman.d/hooks/`).
2. Update the docs so future-me is not confused:
   - [macbookpro12-1-keyboard-kernel-patch.md](macbookpro12-1-keyboard-kernel-patch.md):
     retarget the whole story from Arch `linux` to `linux-omarchy` (new
     upstream for patches: the omarchy tree; new bump cadence source).
   - AGENTS.md "Patched kernel loop" section: swap `~/build/linux/rebuild-patch.sh`
     for `~/build/linux-omarchy/rebuild-omarchy-patch.sh` and note the
     version-bump cadence is now Omarchy's (monthly-ish, watch
     `omarchy update` output for kernel bumps via `pacman -Qu linux-omarchy`).
3. Once confident (a couple weeks of daily use): delete the stock linux
   stack (`pacman -Rns linux linux-headers linux-docs`) and drop the legacy
   IgnorePkg entries, AND fix BOOT_ORDER: after removing stock linux, the
   `*, *fallback` slots in BOOT_ORDER only match linux-omarchy variants -
   verify `limine-entry-tool --tree` still lists exactly what is expected.
   If not confident, keep the stock stack IgnorePkg'd indefinitely - its
   only cost is ~200MB of disk.

## Rollback story (kept simple on purpose)

- BOOT_ORDER is one line in `/etc/default/limine`; the Limine menu itself
  retains a linux-omarchy and a stock-linux entry for as long as both are
  installed.
- Unpatched 7.2.5 boots (keyboard dead over it): at the Limine menu pick
  the stock kernel; keyboard works there.
- Patched linux-omarchy boots but S3-resume regresses after upstream
  changes: re-apply `0002` rebased against the newer tree (same as today's
  drift-rebase dance), or fall back to the stock kernel entry that day.
- Catestrophic: `limine-snapper-sync` snapshot from before the update is
  bootable from the Limine menu (Snapshots entry).
