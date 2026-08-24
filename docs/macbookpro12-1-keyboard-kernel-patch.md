# MacBookPro12,1 Keyboard Fix - Local Kernel Patch (DMI Forced-PIO)

Companion to `docs/arch-setup-mac.md`, `docs/macbookpro12-1-keyboard-spi-fix.md`,
and `docs/macbookpro12-1-keyboard-s3-resume.md`. You only need this when the
userland blacklist cannot work.

## When you need this

The normal fix blacklists `dw_dmac_pci` in `/etc/modprobe.d/` so
`spi-pxa2xx` has no DMA engine and falls back to PIO. That only works if the
DMA driver is a loadable module:

```
grep -c dw_dmac_pci /usr/lib/modules/*/modules.builtin
```

If this prints `0`, the DMA driver is a module - go use the blacklist (the
install-guide approach) and stop here. If it prints `1` (as it did here on
`7.0.14-arch1-1`), `dw_dmac_pci` is compiled into the kernel, the blacklist
cannot remove it, and the DMA device stays present - so DMA-backed SPI
transfers will keep timing out with `-110`. The clean fix is a kernel patch
that tells the SPI controller to skip DMA entirely.

## What the patch does

In `drivers/spi/spi-pxa2xx-pci.c` (the LPSS PCI glue driver for the SPI
controller at `00:15.4`, PCI ID `0x9ce6`), `lpss_spi_setup()` unconditionally
sets `c->enable_dma = 1` (line 169). `spi-pxa2xx` then requests a DMA channel
from `dw_dmac_pci`; the transfer never completes because Apple's EFI firmware
holds that DMA block in permanent reset.

The patch adds a DMI match for `MacBookPro12,1` and routes `enable_dma`
through a helper that returns `false` on this machine. With
`platform_info->enable_dma == 0`, `spi-pxa2xx.c:1339-1344` skips DMA setup
entirely and every transfer is PIO - exactly how Apple's own firmware drives
the keyboard. This is the same mechanism as Shih-Yuan Lee's upstream series
("spi: pxa2xx: disable DMA for Apple MacBook8,1", v16, still in review on
linux-spi as of 2026-07), minus its module parameter (removed after review)
and with the DMI entry pointed at this model.

## The patch

The patch is kept in this repo as
`build/0001-spi-pxa2xx-macbookpro12-1-pio.patch` (copy it to the machine
running the build). Its full content:

```diff
diff --git a/drivers/spi/spi-pxa2xx-pci.c b/drivers/spi/spi-pxa2xx-pci.c
index cae77ac18520..8d917c9a52ec 100644
--- a/drivers/spi/spi-pxa2xx-pci.c
+++ b/drivers/spi/spi-pxa2xx-pci.c
@@ -10,6 +10,7 @@
 #include <linux/err.h>
 #include <linux/module.h>
 #include <linux/pci.h>
+#include <linux/dmi.h>
 #include <linux/pm.h>
 #include <linux/pm_runtime.h>
 #include <linux/sprintf.h>
@@ -21,6 +22,27 @@
 
 #include "spi-pxa2xx.h"
 
+static const struct dmi_system_id pxa2xx_spi_pci_dmi_table[] = {
+	{
+		.ident = "Apple MacBookPro12,1",
+		.matches = {
+			DMI_MATCH(DMI_SYS_VENDOR, "Apple Inc."),
+			DMI_MATCH(DMI_PRODUCT_NAME, "MacBookPro12,1"),
+		},
+	},
+	{ }
+};
+
+static bool pxa2xx_spi_pci_can_dma(struct pci_dev *dev)
+{
+	if (dmi_check_system(pxa2xx_spi_pci_dmi_table)) {
+		pci_info(dev, "MacBookPro12,1 detected: disabling DMA to force PIO mode\n");
+		return false;
+	}
+
+	return true;
+}
+
 #define PCI_DEVICE_ID_INTEL_QUARK_X1000		0x0935
 #define PCI_DEVICE_ID_INTEL_BYT			0x0f0e
 #define PCI_DEVICE_ID_INTEL_MRFLD		0x1194
@@ -166,7 +188,7 @@ static int lpss_spi_setup(struct pci_dev *dev, struct pxa2xx_spi_controller *c)
 
 	c->dma_filter = lpss_dma_filter;
 	c->dma_burst_size = 1;
-	c->enable_dma = 1;
+	c->enable_dma = pxa2xx_spi_pci_can_dma(dev);
 	return 0;
 }
```

Notes:

- This is the **minimal** version - only the LPSS `lpss_spi_setup()` path
  (used by `0x9ce6`) is changed; `mrfld_spi_setup()` is untouched, so
  Merrifield devices keep their DMA behaviour. `spi-pxa2xx-pci` builds as a
  module (`CONFIG_SPI_PXA2XX_PCI`), so only that module is affected - nothing
  else in the kernel changes.
- If `patch` complains about offsets, the hunk line numbers just drifted
  (kernel upgrades). `git apply --3way` or `patch -p1 -F3` handles small
  shifts; the context lines above are stable.
- The DMI strings are `product_name=MacBookPro12,1` / `sys_vendor=Apple Inc.`
  (see `/sys/class/dmi/id/`). To confirm your unit reports these:
  `cat /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor`.

## Build prerequisites (on the machine, as a non-root user)

Building the full `linux` package takes roughly 1-2 hours on this machine
and needs ~15 GB free disk and several GB of RAM. `base-devel` and `git` are
required; `pacman-contrib` provides `updpkgsums`:

```
sudo pacman -S --needed base-devel git pacman-contrib
```

## Build steps

1. Get the Arch kernel packaging tree (PKGBUILD + `config.x86_64`) - `asp`
   is deprecated and no longer in the repos, so clone the packaging repo
   directly:

```
git clone https://gitlab.archlinux.org/archlinux/packaging/packages/linux.git
cd linux
```

   (Official alternative, `pkgctl` from the `devtools` package - needs a
   gitlab.archlinux.org login via `pkgctl auth login` first:
   `sudo pacman -S --needed devtools && pkgctl repo clone linux`.)

2. Copy the patch in and wire it into the PKGBUILD:

```
cp ../0001-spi-pxa2xx-macbookpro12-1-pio.patch .
```

   Edit `PKGBUILD`:
   - Add `"0001-spi-pxa2xx-macbookpro12-1-pio.patch"` to the `source=()`
     array.
   - Bump `pkgrel=1` to `pkgrel=2` so the rebuilt kernel is distinguishable
     (`7.0.14-arch1-2`) from stock.
   - The PKGBUILD's `prepare()` already applies any `*.patch` entry in
     `source=()` after the source checkout, so no `prepare()` edit is needed.
     If a future PKGBUILD drops that loop, add `patch -Np1 <
     ../0001-spi-pxa2xx-macbookpro12-1-pio.patch` at the top of `prepare()`.

3. Update the checksums (this adds the patch's b2sum and keeps the git source
   as `SKIP`):

```
updpkgsums
```

4. Import the signing keys listed in `validpgpkeys=` - this is the step
   people skip, and skipping it is exactly what produces the makepkg error
   `==> ERROR: One or more PGP signatures could not be verified!` when it
   reaches the download/verify stage. The list changes between releases -
   use whatever the checked-out PKGBUILD lists; as of `7.1.5` these are
   the three current keys:

```
gpg --keyserver keyserver.ubuntu.com --recv-keys \
  ABAF11C65A2970B130ABE3C479BE3E4300411886 \
  647F28654894E3BD457199BE38DBBDC86092693E \
  83BC8889351B5DEBBB68416EB8AC08600F108CDF
```

   If `makepkg` still fails with `PGP signatures could not be verified`
   after importing: the keyserver may have returned nothing (re-run the
   `gpg` command, or switch servers to `hkps://keys.openpgp.org`), or a
   stale copy of a key is in your keyring (`gpg --refresh-keys`, or
   `gpg --delete-keys <key>` before re-importing). Cross-check what
   makepkg actually needs against the `validpgpkeys=` array in the
   PKGBUILD.

5. Build (sets parallel jobs to the number of CPU cores):

```
MAKEFLAGS="-j$(nproc)" makepkg -s
```

   `-s` installs makedepends (`bc`, `pahole`, `cpio`, ...) automatically.
   The result is `linux-7.0.14.arch1-2-x86_64.pkg.tar.zst`,
   `linux-headers-...`, and `linux-docs-...` (version strings are examples -
   use whatever the checked-out PKGBUILD reports).

## Install

Install the kernel **and its headers** - `linux-headers` must match the
running kernel or `acpi_call-dkms` (still part of this fix, see below) fails
to rebuild:

```
sudo pacman -U linux-*.pkg.tar.zst linux-headers-*.pkg.tar.zst
```

The pacman hooks rebuild the initramfs (picking up the existing
`MODULES=(...)` and `/etc/modprobe.d` from the earlier steps) and re-trigger
dkms. Reboot.

## Verify

```
uname -r                # 7.0.14-arch1-2
sudo dmesg | grep -i "disabling DMA"
```

The dmesg line should read `pxa2xx_spi_pci 0000:00:15.4: MacBookPro12,1
detected: disabling DMA to force PIO mode`. The internal keyboard and
trackpad should work at GRUB, at the LUKS prompt, and in the booted system.

## What this replaces, and what you still keep

- **Replaces:** the `dw_dmac_pci`/`dw_dmac_core` blacklist
  (`/etc/modprobe.d/blacklist-lpss-dma.conf`) - it is now redundant and can
  be removed (it did nothing anyway once `dw_dmac_pci` was built-in).
- **Still required:** the `SIEN(1)` modprobe `install` reroute
  (`/etc/modprobe.d/apple-keyboard-spi.conf` + `acpi_call-dkms`) - the DMI
  quirk only fixes DMA; it does not stop `applespi` bailing on the bogus
  `UIST=1`.
- **Still required:** the udev runtime-PM pin
  (`/etc/udev/rules.d/60-spi-pio.rules`). The minimal patch here does not
  include the upstream series' "lock out runtime autosuspend in PIO mode"
  fix, so the autosuspend/PCIe-Completion-Timeout bug still needs the
  `power/control=on` stopgap on a stock kernel.

### Optional: port the full upstream series instead

Shih-Yuan Lee's upstream series (v16) covers three things beyond this DMI
quirk: the LPSS S3-resume register restore (covered locally by
`build/0002-spi-pxa2xx-lpss-s3-resume.patch`, see
[docs/macbookpro12-1-keyboard-s3-resume.md](macbookpro12-1-keyboard-s3-resume.md)),
a runtime-autosuspend lockout in PIO mode (would let you drop the udev
rule), and clock/PM refactors. Porting the full series and adding the
`MacBookPro12,1` entry to its DMI table removes the last stopgap (the udev
rule) at a larger maintenance burden; the two local patches plus the udev
rule are the equivalent otherwise.

## Keeping up with kernel updates

A stock `pacman -Syu` would overwrite the patched kernel. Add to
`/etc/pacman.conf`:

```
IgnorePkg = linux linux-headers linux-docs
```

Then, each time a new `linux` version lands, redo steps 1-5 above (refresh
the packaging tree, confirm the patch still applies, bump `pkgrel`,
rebuild), and `pacman -U` the new packages. `build/rebuild-patch.sh` in this repo
automates exactly that loop (clone/fetch, hard-reset, re-apply the patches,
bump `pkgrel`, `updpkgsums`, `makepkg`, install). `build/setup-patch.sh` copies
`rebuild-patch.sh` and both patches into a dedicated directory on this system
(default `~/build/linux/`) - run it once, then `~/build/linux/rebuild-patch.sh`
after each kernel bump.

## References

- Upstream series (v16, 2026-07, in review): patch "disable DMA for Apple
  MacBook8,1" - <https://lore.kernel.org/linux-spi/20260720162117.32304-6-fourdollars@debian.org/>
  (mirror: <https://lore-kernel.gnuweeb.org/linux-spi/20260720162117.32304-6-fourdollars@debian.org/>)
- EFI-held-in-reset confirmation (2026-07-26 reply, `force_pio` param removed):
  <https://lists.openwall.net/linux-kernel/2026/07/26/503>
- Kernel Bugzilla: <https://bugzilla.kernel.org/show_bug.cgi?id=108331>
- Arch build-system documentation: <https://wiki.archlinux.org/title/Kernel>
- Local kernel source reference (cloned the github mirror to `~/examples/linux` for direct reference and analysis):
  `drivers/spi/spi-pxa2xx-pci.c` (DMI quirk location, `lpss_spi_setup`),
  `drivers/spi/spi-pxa2xx.c:1339-1344` (PIO fallback path), `drivers/input/keyboard/applespi.c:1616-1622` (UIST bailout).
