#!/bin/bash
# Rebuild the MacBookPro12,1-patched Arch kernel and install it.
#
# Run as your normal user (sudo is used for pacman -U). Safe to re-run;
# use it every time the `linux` package version bumps (~monthly).
#
# See docs/macbookpro12-1-keyboard-kernel-patch.md for the full story.

set -euo pipefail
cd "$(dirname "$0")"

PATCHES=(
  0001-spi-pxa2xx-macbookpro12-1-pio.patch
  0002-spi-pxa2xx-lpss-s3-resume.patch
)
REPO=https://gitlab.archlinux.org/archlinux/packaging/packages/linux.git

if [[ ! -d linux/.git ]]; then
  git clone "$REPO"
fi
git -C linux fetch origin
git -C linux reset --hard origin/main          # discard last run's edits
for patch in "${PATCHES[@]}"; do
  cp "$patch" linux/
done

cd linux
for patch in "${PATCHES[@]}"; do
  grep -q "$patch" PKGBUILD || sed -i "/^source=(/a\\  \"$patch\"" PKGBUILD
done
sed -i -E 's/^pkgrel=([0-9]+)$/pkgrel=\1.1/' PKGBUILD   # 2 -> 2.1, marks it local
updpkgsums

# Import the signing keys the PKGBUILD declares in validpgpkeys= - without
# these makepkg dies with "One or more PGP signatures could not be
# verified!". Existing keys are left alone (refreshing them is optional).
for key in $(sed -n '/^validpgpkeys=(/,/^)/p' PKGBUILD | grep -oE '[0-9A-F]{40}'); do
  if gpg --list-keys "$key" >/dev/null 2>&1; then
    continue
  fi
  echo "Importing PGP key $key (declared in validpgpkeys) ..."
  for server in keyserver.ubuntu.com hkps://keys.openpgp.org; do
    gpg --keyserver "$server" --recv-keys "$key" && break
  done
done

# Stale packages from the previous kernel version are left in this directory
# by makepkg; drop them so the install glob below matches only what makepkg
# just produced (otherwise pacman -U sees both versions and fails on a
# duplicate target).
rm -f linux-*.pkg.tar.zst

# If `patch -Np1` fails inside prepare() (hunk offsets drifted after a
# kernel bump), rebase the local patches against the new tree and re-run.
# -j$(nproc) parallelizes the build (Arch's default makepkg.conf leaves
# MAKEFLAGS unset, which would otherwise build with a single job).
# One glob covers linux, linux-headers and linux-docs; the old second
# linux-headers glob overlapped it and made pacman fail on a duplicate
# target, silently skipping the install.
MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}" makepkg -s
sudo pacman -U linux-*.pkg.tar.zst
