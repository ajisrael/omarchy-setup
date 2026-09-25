#!/usr/bin/env bash
# Revert the repo's suspend/resume WiFi driver reload hook back to stock, and
# install the pure-logging zz-suspend-debug hook in its place.
#
# Removes:
#   /usr/lib/systemd/system-sleep/brcmfmac-reload   (systemd suspend/resume hook)
#   /usr/local/sbin/wifi-recover                    (its backend)
# Each removed file is backed up under /var/backup/suspend-stock/<timestamp>/
# before deletion, so nothing is lost.
#
# Installs:
#   /usr/lib/systemd/system-sleep/zz-suspend-debug  (repo
#     config/systemd/system-sleep/zz-suspend-debug) - pure logging: enables
#     pm_print_times and snapshots dmesg/journal around each cycle into
#     /var/log/suspend-debug/. See maint/suspend-report to collate one cycle.
#
# Deliberately does NOT touch: the patched kernel, the modprobe.d SPI configs,
# the initramfs MODULES drop-in, the 60-spi-pio.rules udev rule, the logind
# lid-toggle drop-in, or the libinput quirks - those are the keyboard/trackpad
# driver stack and are required for the input devices to work, and the S3
# resume kernel patch is the documented fix for the keyboard-after-deep-sleep
# bug (docs/macbookpro12-1-keyboard-s3-resume.md).
#
# Run as your normal user (the root steps self-sudo). Idempotent: re-running
# is a no-op for anything already removed/installed.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BACKUP_ROOT="/var/backup/suspend-stock"
REMOVE=(
    "/usr/lib/systemd/system-sleep/brcmfmac-reload"
    "/usr/local/sbin/wifi-recover"
)
DEBUG_HOOK_SRC="$DIR/config/systemd/system-sleep/zz-suspend-debug"
DEBUG_HOOK_DEST="/usr/lib/systemd/system-sleep/zz-suspend-debug"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"

echo "==> Backup + remove suspend hooks"
for f in "${REMOVE[@]}"; do
    if [ -e "$f" ]; then
        sudo mkdir -p "$BACKUP_DIR"
        sudo cp -a "$f" "$BACKUP_DIR/$(basename "$f")"
        sudo rm -f "$f"
        echo "    removed $f (backed up to $BACKUP_DIR/)"
    else
        echo "    $f already absent - skipping"
    fi
done

echo "==> Install zz-suspend-debug logging hook"
[ -e "$DEBUG_HOOK_SRC" ] || { echo "missing $DEBUG_HOOK_SRC" >&2; exit 1; }
if cmp -s "$DEBUG_HOOK_SRC" "$DEBUG_HOOK_DEST"; then
    echo "    already installed"
else
    sudo install -Dm755 "$DEBUG_HOOK_SRC" "$DEBUG_HOOK_DEST"
    echo "    installed $DEBUG_HOOK_DEST"
fi

echo
echo "Done. Suspension is back to stock (no WiFi reload hook); a logging hook is active."
echo "Verify a cycle with: maint/wifi-cycle-test 30, then maint/suspend-report."
echo "Restore the old hooks anytime from: $BACKUP_DIR/"