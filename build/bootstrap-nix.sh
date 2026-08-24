#!/usr/bin/env bash
# Bootstrap nix + the first home-manager generation on a fresh Omarchy box.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
#
# The Arch Nix setup differs from the stale ArchWiki instructions in several
# ways - each gotcha is called out inline below. Only the nix daemon + first
# switch happen here; system-level (root /etc) files come from
# build/omarchy-setup.sh instead.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> Step 1: Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  echo "    Installing nix from the Arch repos..."
  sudo pacman -S --needed nix
fi

echo "==> Step 2: daemon runtime dirs + socket activation"
# tmpfiles creates /nix/var/nix/{daemon-socket,builds} (also runs at boot).
# This must happen BEFORE the socket starts: the socket unit carries
# ConditionPathIsReadWrite=/nix/var/nix/daemon-socket.
sudo systemd-tmpfiles --create
# Modern socket-activated setup. Do NOT also enable nix-daemon.service -
# systemd refuses to listen on a socket whose service is already active
# ("Socket service nix-daemon.service already active, refusing").
sudo systemctl enable --now nix-daemon.socket

echo "==> Step 3: /nix/store"
# The package's tmpfiles config deliberately does not create /nix/store.
# Multi-user store: root:root, mode 1775 (sticky so build users can't
# interfere with each other's outputs). Without it, `nix run` fails with
# "opening file /nix/store: No such file or directory".
if [ ! -d /nix/store ]; then
  sudo install -d -o root -g root -m 1775 /nix/store
fi

echo "==> Step 4: experimental features"
# Nix 2.35 gates `nix run` / flakes behind experimental-features; the Arch
# package ships /etc/nix/nix.conf containing only `build-users-group = nixbld`.
if [ ! -f /etc/nix/nix.conf ] || ! grep -q '^experimental-features' /etc/nix/nix.conf; then
  echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf >/dev/null
fi

# /etc/profile.d/nix-daemon.sh only runs in login shells; source it so this
# script works from a fresh shell.
# shellcheck disable=SC1091
. /etc/profile.d/nix-daemon.sh 2>/dev/null || true

echo "==> Step 5: first home-manager switch"
# home-manager does not exist yet on a fresh box; run it straight from the
# flake this once (pinned to flake.lock's home-manager input, so the CLI and
# the modules are version-matched). After this the generation self-hosts
# `home-manager` on PATH (via ~/.local/state/nix/profile/bin) and rebuild.sh
# works normally.
# Never `nix profile add` home-manager: the generation installs
# home-manager-path with the same bin/home-manager at the same priority and
# the switch fails with a file clash.
nix run "$DIR#home-manager" -- switch --flake "$DIR#archeus"

echo "==> Done. Use ./rebuild.sh for future changes."
