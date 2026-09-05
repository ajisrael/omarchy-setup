#!/usr/bin/env bash
# Apply the user-level config: home-manager switch against this flake.
# Run this for every change after the first bootstrap (build/bootstrap-nix.sh).
#
# Also ensures ~/.todos exists (the git-tracked todos dir opened by
# <prefix>t via tmux-my-todos). Idempotent: only initializes it on first-run.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ~/.todos: seed dir + git repo on first run only; now owned by the todos repo.
TODO_DIR="$HOME/.todos"
if [ ! -d "$TODO_DIR/.git" ]; then
  mkdir -p "$TODO_DIR"
  if [ ! -f "$TODO_DIR/todos.md" ]; then
    printf '# TODOs:\n' > "$TODO_DIR/todos.md"
  fi
  git -C "$TODO_DIR" init -q
  git -C "$TODO_DIR" add todos.md
  git -C "$TODO_DIR" commit -q -m "init todos" || true
fi

# Resolve home-manager even when the caller's PATH lacks the nix profile bin
# (non-login shells don't run /etc/profile.d/nix-daemon.sh).
HM="$(command -v home-manager || echo "$HOME/.nix-profile/bin/home-manager")"
"$HM" switch --flake "$DIR#archeus"

echo "Rebuild successful!"
