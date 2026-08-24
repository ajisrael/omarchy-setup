# opencode MCP secrets (ansible-vault)

`opencode.json` references MCP server auth tokens via `{env:VAR}` interpolation
(e.g. `SONARQUBE_MCP_TOKEN`, `JENKINS_MCP_AUTH`, `DOJO_PRO_*_TOKEN`). The
values live in `.env` on this machine, but the plaintext `.env` is **never
committed** — the repo only tracks an ansible-vault encrypted copy.

## Files involved

| File                | Tracked? | Purpose                                                     |
| ------------------- | -------- | ----------------------------------------------------------- |
| `.env.vault`        | yes      | ansible-vault AES256 encrypted copy of the secrets          |
| `.vault.env`        | **no**   | the vault password; copied onto a machine once, unlocks all |
| `.env`              | **no**   | decrypted output; what opencode actually needs in your env  |
| `build/decrypt-secrets.sh` | yes | helper that does the decrypt for you                    |

## Prerequisite

Install ansible on this machine so `ansible-vault` exists (also gives you
plain `ansible` for provisioning):

```sh
./rebuild.sh --packages
```

Ansible and ansible-vault are tracked in `system-packages.nix`.

## Everyday workflow

Decrypt the vault into `.env` and launch opencode with the secrets loaded:

```sh
build/decrypt-secrets.sh
set -a && source .env && set +a && opencode
```

opencode does **not** auto-load `.env`, so the `source` step is required. The
script refuses to run if `.vault.env` is missing and explains where it comes
from.

## Editing / adding a secret

1. Decrypt the current vault to `.env` (above).
2. Edit `.env` with your editor.
3. Re-encrypt it back into `.env.vault`:

```sh
ansible-vault encrypt --vault-password-file .vault.env --output .env.vault .env
rm .env   # keep the plaintext out of the tree
```

Or skip the plaintext file entirely and edit the vault in place (decrypts,
opens `$EDITOR`, re-encrypts on save):

```sh
ansible-vault edit --vault-password-file .vault.env .env.vault
```

## Viewing the current vault

```sh
ansible-vault view --vault-password-file .vault.env .env.vault
```

## Adding a new machine

1. Get the vault onto it. Only the single password file `.vault.env` needs to
   be copied (never the plaintext `.env`).
2. Clone the repo, create `.vault.env` with that password.
3. Run `build/decrypt-secrets.sh`.

## Which variables opencode.json consumes

From `config/opencode/opencode.json`:

- `SONARQUBE_MCP_TOKEN` — Bearer token for the sonarqube MCP
- `JENKINS_MCP_AUTH` — full `Authorization` header for the jenkins MCP
- `DOJO_PRO_PROD_TOKEN` / `DOJO_PRO_PREPROD_TOKEN` / `DOJO_PRO_LOCAL_TOKEN` —
  Bearer tokens for the dojo-pro environments
