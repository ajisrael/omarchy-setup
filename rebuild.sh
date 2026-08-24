#!/usr/bin/env bash
# Apply the user-level config: home-manager switch against this flake.
# Run this for every change after the first bootstrap (build/bootstrap-nix.sh).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Resolve home-manager even when the caller's PATH lacks the nix profile bin
# (non-login shells don't run /etc/profile.d/nix-daemon.sh).
HM="$(command -v home-manager || echo "$HOME/.nix-profile/bin/home-manager")"
"$HM" switch --flake "$DIR#archeus"

echo "Rebuild successful!"
