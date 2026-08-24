# MacBookPro12,1 Keyboard/Trackpad - S3 Resume Fix

Companion to `docs/arch-setup-mac.md` (install guide), the SPI/PIO fix
(`docs/macbookpro12-1-keyboard-spi-fix.md`), and the local kernel patch
(`docs/macbookpro12-1-keyboard-kernel-patch.md`). Covers the bug where the
internal keyboard/trackpad die after suspend-and-wake, and the two ways to
fix it: an s2idle quick fix, or a kernel patch that restores the LPSS
private register state across deep sleep (S3).

## Symptom

After the machine sleeps (deep/S3 suspend) and wakes up, the internal
keyboard/trackpad no longer respond. `dmesg` shows `applespi` logging a
repeating `SPI transfer timed out` / `Error reading from device: -110`.
`rmmod`/`modprobe applespi` and PCI `remove`/`rescan` do NOT help - only a
reboot clears it.

## Root cause

- The SPI controller is `00:15.4` (`8086:9ce6`, Wildcat Point-LP LPSS SPI,
  driver type `LPSS_LPT_SSP`). Its LPSS private registers live at
  `mmio_base + 0x800`.
- Across S3 the LPSS power domain is fully removed, resetting every private
  register - including `LPSS_PRIV_RESETS` (offset `0x04`), which comes back
  as `0x0`, holding the functional block in reset. Any register access to a
  held-in-reset block never completes, which is the `-110` loop.
- The driver binds through `spi-pxa2xx-pci`, not through `intel-lpss`/ACPI,
  so nothing re-initialises the private registers on resume:
  `pxa2xx_spi_resume()` only re-enables the clock before restarting the
  transfer queue.
- Same failure documented upstream against this exact controller:
  <https://github.com/cb22/macbook12-spi-driver/issues/49>.

## Fix options

### Quick fix: sleep with s2idle instead of deep sleep

s2idle does not remove the LPSS power domain, so the private registers
survive the sleep and the keyboard keeps working after wake. Cost: s2idle
keeps a bit more hardware alive, so battery draw while "asleep" is slightly
higher than deep sleep.

```bash
sudo tee /etc/tmpfiles.d/sleep-mode.conf > /dev/null <<'EOF'
w /sys/power/mem_sleep - - - - s2idle
EOF
```

Reboot (or `echo s2idle | sudo tee /sys/power/mem_sleep` to apply now), then
confirm s2idle is the active mode:

```bash
cat /sys/power/mem_sleep     # expect [s2idle] deep
```

Confirmed working on this machine (2026-08): keyboard/trackpad survive
sleep/wake with s2idle. To go back to deep sleep later, remove the file and
reboot (or `echo deep | sudo tee /sys/power/mem_sleep` to flip it live) and
check `[s2idle] deep` has flipped to `s2idle [deep]`.

### Permanent fix: kernel patch (restores LPSS state on resume)

`build/0002-spi-pxa2xx-lpss-s3-resume.patch` makes `spi-pxa2xx` restore the
LPSS private register state across S3 itself:

- **Suspend:** saves the first 6 LPSS private registers (offsets `0x00` to
  `0x14`) into `drv_data->lpss_priv_ctx[6]`, after `pm_runtime_resume_and_get()`
  guarantees the power domain is up. Registers beyond `0x14` (except CS
  control at `0x18`, re-initialised by `lpss_ssp_setup()`) are
  reserved/unimplemented on LPT; writing to them triggers a PCIe Completion
  Timeout, so only these 6 are touched.
- **Resume:** de-asserts `LPSS_PRIV_RESETS` (`FUNC | IDMA`) first - any
  access while the block is held in reset is the failure - then restores the
  other 5 saved registers, then re-runs `lpss_ssp_setup()` so the software
  chip-select starts deasserted (`SW_MODE | CS_HIGH`) regardless of its state
  at suspend time.
- Restricted to LPT/BYT/BSW platforms (`pxa2xx_spi_need_lpss_restore()`);
  newer LPSS generations are handled by `intel-lpss`. The runtime-PM wrapping
  is safe both with and without the udev `power/control=on` rule.

This is a minimal, self-contained adaptation of Shih-Yuan Lee's upstream
series patch "restore LPSS private register state on S3 resume" (v16, in
review on `linux-spi`, not in mainline). The upstream patch depends on a
7-patch refactor of the driver that is also not in mainline, so this local
patch re-implements the same fix against the current mainline
suspend/resume code.

## Applying the kernel patch

Both local patches live in `build/`:
`0001-spi-pxa2xx-macbookpro12-1-pio.patch` (forced PIO, already in the
running kernel) and `0002-spi-pxa2xx-lpss-s3-resume.patch`. `build/setup-patch.sh`
copies `rebuild-patch.sh` and the patches to a dedicated directory on this system
(default `~/build/linux/`); `rebuild-patch.sh` there clones the Arch kernel
packaging tree, applies both, bumps `pkgrel`, builds, and installs. See
[docs/macbookpro12-1-keyboard-kernel-patch.md](macbookpro12-1-keyboard-kernel-patch.md)
for the manual steps.

```bash
./build/setup-patch.sh
~/build/linux/rebuild-patch.sh
```

## Verify

1. After the patched kernel boots, remove the s2idle override so deep sleep
   is the active mode again:
   `sudo rm /etc/tmpfiles.d/sleep-mode.conf`, reboot, confirm
   `cat /sys/power/mem_sleep` shows `s2idle [deep]`.
2. Suspend the machine (deep sleep), wake it, and use the internal
   keyboard/trackpad.
3. `journalctl -k | grep -i 'SPI transfer timed out'` should be empty across
   the wake, and the keyboard should respond immediately.

## What you still keep

- **The udev `power/control=on` rule** (`/etc/udev/rules.d/60-spi-pio.rules`).
  It works around a separate runtime-autosuspend bug (aggressive autosuspend
  causing PCIe Completion Timeouts on MMIO in PIO mode) that this local patch
  does not cover - that one is fixed by a different patch in the upstream
  series ("lock out runtime autosuspend for Intel LPSS SPI in PIO mode").
- **The `SIEN(1)` modprobe reroute and the initramfs `MODULES=`.**
  Unrelated to sleep; still required for the keyboard at boot.

## References

- Upstream series (v16, 2026-07, in review): cover letter
  <https://lore.kernel.org/linux-spi/20260720162117.32304-1-fourdollars@debian.org/>;
  the S3-resume patch (6/7)
  <https://lore.kernel.org/linux-spi/20260720162117.32304-7-fourdollars@debian.org/>
- Same controller resume failure (message queued but never transmitted):
  <https://github.com/cb22/macbook12-spi-driver/issues/49>
- Register layout reference: `drivers/mfd/intel-lpss.c`
  (`LPSS_PRIV_RESETS` `0x04`, `FUNC` `0x3`, `IDMA` `BIT(2)`); driver code in
  `drivers/spi/spi-pxa2xx.c` / `spi-pxa2xx.h`.
