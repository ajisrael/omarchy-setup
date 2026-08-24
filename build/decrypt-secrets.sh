#!/usr/bin/env bash
# Decrypt the MCP server secrets for this machine.
#
# .env.vault (committed, ansible-vault AES256 encrypted) is decrypted into
# .env (gitignored) using the vault password in .vault.env (gitignored). The
# vault password file must exist on this machine - copy it over once, it is
# the single secret that unlocks everything.
#
# opencode does not auto-load .env, so after decrypting, source it in your
# shell before launching opencode:
#
#   build/decrypt-secrets.sh
#   set -a && source .env && set +a && opencode
#
# Usage:
#   decrypt-secrets.sh          # decrypt .env.vault -> .env
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VAULT_FILE="$DIR/.vault.env"
SOURCE="$DIR/.env.vault"
DEST="$DIR/.env"

if [ ! -f "$VAULT_FILE" ]; then
    echo "error: $VAULT_FILE not found." >&2
    echo "It holds the ansible-vault password and is never committed - copy it from" >&2
    echo "another machine or recreate it, then rerun this script." >&2
    exit 1
fi

if [ ! -f "$SOURCE" ]; then
    echo "error: $SOURCE not found (is the repo on the latest commit?)" >&2
    exit 1
fi

ansible-vault decrypt --vault-password-file "$VAULT_FILE" --output "$DEST" "$SOURCE"
echo "==> Secrets decrypted to $DEST"
echo "    Source it before running opencode:  set -a && source $DEST && set +a"
