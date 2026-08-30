#!/usr/bin/env bash
# Deploy the MacBookPro12,1 internal keyboard/trackpad fix on omarchy, plus
# the rest of the repo's system-level config that carries over from archeus.
#
# Run as your normal user (each root step self-sudoes). Safe to re-run:
# every deploy is cmp-gated and the initramfs/UKI is only rebuilt when
# something actually changed or the kernel was just replaced.
#
# Prerequisites (one-time, NOT done here):
#   yay -S acpi_call-dkms actkbd        # AUR packages (yay must run as user)
#   ~/build/linux/rebuild-patch.sh      # builds+installs the patched kernel;
#                                       # if already built but not installed,
#                                       # this script installs the packages
#
# What this deploys:
#   - config/modprobe.d/*.conf          -> /etc/modprobe.d/   (SIEN(1) reroute,
#       dw_dmac blacklist belt-and-braces, kbd/screen backlight floors)
#   - /etc/mkinitcpio.conf.d/apple-spi-keyboard.conf  MODULES drop-in
#       (sorts before omarchy_hooks.conf; modconf bundles modprobe.d so the
#       reroute fires inside the busybox initramfs)
#   - config/udev/rules.d/60-spi-pio.rules -> /etc/udev/rules.d/
#       (runtime-PM pin on SPI controller 0x9ce6; without it PIO hits PCIe
#       Completion Timeouts)
#   - config/libinput/local-overrides.quirks ->
#       /etc/libinput/local-overrides.quirks (tags the SPI keyboard as
#       internal so libinput's disable-while-typing actually fires)
#   - config/actkbd/*                   -> F5/F6 keyboard-backlight stepping
#   - config/systemd/system-sleep/brcmfmac-reload ->
#       /usr/lib/systemd/system-sleep/ (reloads brcmfmac on resume to recover
#       a hung BCM43602 Wi-Fi chip after suspend)
#   - patched kernel packages           -> pacman -U from ~/build/linux/linux/
#   - IgnorePkg hold in /etc/pacman.conf + the pre-refresh-pacman hook that
#       re-adds it after `omarchy refresh pacman` rewrites pacman.conf
#
# See docs/omarchy-migration-plan.md (Phase 2) for the full story.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MODPROBE_SRC="$DIR/config/modprobe.d"
UDEV_SRC="$DIR/config/udev/rules.d"
ACTKBD_SRC="$DIR/config/actkbd"
LIBINPUT_SRC="$DIR/config/libinput"
KERNEL_BUILD_DIR="$HOME/build/linux/linux"
KBD_DEV="/dev/input/by-path/pci-0000:00:15.4-cs-00-event-kbd"

CHANGED=0

echo "==> modprobe.d"
for conf in apple-keyboard-spi.conf blacklist-lpss-dma.conf kbd-backlight.conf backlight-screen.conf; do
    src="$MODPROBE_SRC/$conf"
    [ -e "$src" ] || { echo "missing $src" >&2; exit 1; }
    dest="/etc/modprobe.d/$conf"
    cmp -s "$src" "$dest" || CHANGED=1
    sudo install -Dm644 "$src" "$dest"
done

echo "==> mkinitcpio drop-in"
DROPIN=/etc/mkinitcpio.conf.d/apple-spi-keyboard.conf
DROPIN_CONTENT='# MacBookPro12,1 internal keyboard/trackpad: acpi_call first (the modprobe.d
# install reroute fires SIEN(1) through it when applespi is modprobed), then
# the SPI host stack, then applespi. applesmc rides along so the modprobe.d
# kbd-backlight floor can fire inside the initramfs too.
MODULES=(acpi_call spi_pxa2xx_platform spi_pxa2xx_pci applespi applesmc)'
tmp_dropin=$(mktemp)
printf '%s\n' "$DROPIN_CONTENT" > "$tmp_dropin"
cmp -s "$tmp_dropin" "$DROPIN" || CHANGED=1
sudo install -Dm644 "$tmp_dropin" "$DROPIN"
rm -f "$tmp_dropin"

echo "==> udev rule"
rule_src="$UDEV_SRC/60-spi-pio.rules"
[ -e "$rule_src" ] || { echo "missing $rule_src" >&2; exit 1; }
cmp -s "$rule_src" /etc/udev/rules.d/60-spi-pio.rules || CHANGED=1
sudo install -Dm644 "$rule_src" /etc/udev/rules.d/60-spi-pio.rules
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=pci

echo "==> logind lid-toggle drop-in"
LOGIND_SRC="$DIR/config/logind/30-lid-toggle.conf"
[ -e "$LOGIND_SRC" ] || { echo "missing $LOGIND_SRC" >&2; exit 1; }
if cmp -s "$LOGIND_SRC" /etc/systemd/logind.conf.d/30-lid-toggle.conf; then
    echo "    already present"
else
    sudo install -Dm644 "$LOGIND_SRC" /etc/systemd/logind.conf.d/30-lid-toggle.conf
    # Restart is safe on modern systemd: user sessions are not killed
    # (KillUserProcesses defaults to no).
    sudo systemctl restart systemd-logind
fi

echo "==> system-sleep brcmfmac-reload hook"
SLEEP_SRC="$DIR/config/systemd/system-sleep/brcmfmac-reload"
[ -e "$SLEEP_SRC" ] || { echo "missing $SLEEP_SRC" >&2; exit 1; }
# No CHANGED bump: a system-sleep hook needs no initramfs/UKI rebuild.
sudo install -Dm755 "$SLEEP_SRC" /usr/lib/systemd/system-sleep/brcmfmac-reload

echo "==> libinput quirks"
quirk_src="$LIBINPUT_SRC/local-overrides.quirks"
[ -e "$quirk_src" ] || { echo "missing $quirk_src" >&2; exit 1; }
# No CHANGED bump: quirks need no initramfs rebuild, just a fresh session.
sudo install -Dm644 "$quirk_src" /etc/libinput/local-overrides.quirks

echo "==> actkbd"
sudo install -Dm644 "$ACTKBD_SRC/actkbd.conf" /etc/actkbd.conf
sudo install -Dm644 "$ACTKBD_SRC/actkbd.service" /etc/systemd/system/actkbd.service
sudo install -Dm755 "$ACTKBD_SRC/kbd-backlight-step" /usr/local/bin/kbd-backlight-step
sudo systemctl daemon-reload
# The device only exists once applespi is bound (patched kernel boot); until
# then starting the unit fails harmlessly. Enabled state is what matters.
if [ -e "$KBD_DEV" ]; then
    sudo systemctl enable --now actkbd.service || true
else
    sudo systemctl enable actkbd.service
fi

echo "==> patched kernel"
if compgen -G "$KERNEL_BUILD_DIR/linux-*.pkg.tar.zst" >/dev/null; then
    pkgfile=$(ls "$KERNEL_BUILD_DIR"/linux-*.pkg.tar.zst | head -1)
    pkgver_rel=$(basename "$pkgfile" | sed -E 's/^linux-([^-]+-[^-]+-[^-]+)-x86_64\.pkg\.tar\.zst$/\1/')
    installed=$(pacman -Q linux 2>/dev/null | awk '{print $2}')
    if [ "$pkgver_rel" = "$installed" ]; then
        echo "    patched kernel $installed already installed"
    else
        echo "    installing $pkgver_rel (installed: ${installed:-none})"
        sudo pacman -U --noconfirm "$KERNEL_BUILD_DIR"/linux-*.pkg.tar.zst
        CHANGED=1   # pacman hooks already rebuilt initramfs; flag not strictly needed
    fi
else
    echo "    no built kernel packages in $KERNEL_BUILD_DIR - skipping (run ~/build/linux/rebuild-patch.sh)"
fi

echo "==> IgnorePkg hold"
if ! grep -q '^IgnorePkg' /etc/pacman.conf; then
    sudo sed -i '/^HoldPkg/a IgnorePkg = linux linux-headers linux-docs' /etc/pacman.conf
    echo "    added IgnorePkg = linux linux-headers linux-docs"
else
    echo "    already present"
fi

echo "==> pre-refresh-pacman hook (survives 'omarchy refresh pacman')"
HOOK="$HOME/.config/omarchy/hooks/pre-refresh-pacman.d/keep-ignorepkg"
mkdir -p "$(dirname "$HOOK")"
cat > "$HOOK" <<'EOF'
#!/bin/bash
# Re-add the patched-kernel hold after omarchy-refresh-pacman rewrites
# /etc/pacman.conf from the channel template.
if ! grep -q '^IgnorePkg' /etc/pacman.conf; then
  sudo sed -i '/^HoldPkg/a IgnorePkg = linux linux-headers linux-docs' /etc/pacman.conf
fi
EOF
chmod +x "$HOOK"

echo "==> initramfs/UKI"
if [ "$CHANGED" = 1 ]; then
    BACKUP_DIR="/var/backup/initramfs-pre-spi"
    sudo mkdir -p "$BACKUP_DIR"
    stamp="$(date +%Y%m%d-%H%M%S)"
    for img in /boot/vmlinuz-*; do
        [ -e "$img" ] || continue
        sudo cp -a "$img" "$BACKUP_DIR/$(basename "$img").$stamp" 2>/dev/null || true
    done
    sudo mkinitcpio -P
else
    echo "    nothing changed; skipping rebuild"
fi

echo
echo "Done. If the kernel was just installed/changed, reboot and verify:"
echo "  uname -r   # should end in .1 (local pkgrel)"
echo "  journalctl -k -b | grep -Ei 'disabling DMA|applespi'"
