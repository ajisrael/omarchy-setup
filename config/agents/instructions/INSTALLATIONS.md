# Installing software on this machine

This applies to global/system-level installs only - a package manager
operating on this machine's state outside of a single project (a CLI tool,
a GUI app, a language runtime available on PATH everywhere). It does not
apply to project-local installs (`npm install` inside a repo, a `uv venv`,
`pip install` in an activated venv) - those follow whatever the project
itself uses.

This machine is Arch Linux running Omarchy, with user-scope config managed
by a home-manager flake (`omarchy-setup`). Before installing anything
globally, use this priority order:

1. **Arch official repos via `omarchy pkg add <name>`** - first choice.
   System layer, reproducible and declarative, rolls back cleanly with
   pacman. `omarchy pkg add` is just `pacman -S`; check the package exists
   in the repos first.
2. **AUR directly via `yay <name>`** - second choice, for packages with no
   Arch repo package. `omarchy pkg add` cannot reach the AUR, so use `yay`
   directly (e.g. blesh-git). Still system layer.
3. **Nix (`home.packages` in `home.nix`)** - last resort, only when the
   package isn't in the Arch repos or AUR at all, or when it needs
   user-scope pinning (e.g. treehouse, uv - both lack Arch packages). Runs
   through `./rebuild.sh`. For npm-published CLIs the same tier is
   reached via the pinned npm-global installs in
   `config/skills/install-axi.sh` (e.g. lavish-axi), which live in
   `~/.npm-global/bin`.

Record *why* a package landed at a lower tier right next to the
`home.packages` entry, `home.activation` block, `omarchy pkg add`, or
`yay` command - e.g. "no Arch package" or "needs user-scope pinning".
Future edits (including automated ones) need that reasoning to avoid
re-litigating the same tier decision or silently regressing a package to a
worse tier.

## Applying the two surfaces

- System layer: `./build/omarchy-setup.sh` (self-sudoes, idempotent).
- User layer: `./rebuild.sh` (home-manager switch against `flake.nix#archeus`).

Never run either on the user's behalf. Validate instead and tell the user
the change is ready to apply - see omarchy-setup's AGENTS.md for that rule
and why.