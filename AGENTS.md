# Agent instructions for omarchy-setup

Omarchy box (hostname still `archeus`): MacBookPro12,1 running Omarchy
(Hyprland + Quickshell). This repo tracks everything layered on top of the
stock Omarchy base: the MacBookPro12,1 keyboard/trackpad fix stack, actkbd
backlight stepping, the composed tmux workflow, and (Phase 4.3) a slimmed
home-manager flake for user-scope config.

`~/arch-setup` is the previous setup's repo, kept as a historical archive -
read it for context (its docs/ hold the full keyboard saga and the migration
plan), never evolve it. New work happens here.

## Commit messages

Follow docs/COMMITS.md (canonical copy of the dotfiles convention):
`<prefix><risk> - <message>` with the dash at position 5. Prefixes: f/r/b/t/d/c/a
(feature, refactor, bugfix, test, docs, chore/config, automated); risk is
lowercase = min, uppercase = medium, `!` = high, `!!` = critical. One prefix,
one risk per commit; most commits minimum risk.

## Core philosophy: compose, don't overwrite

The user deliberately keeps Omarchy defaults wherever possible and layers
customizations on top. When integrating anything:

- Never replace an Omarchy-seeded config wholesale; append a clearly-marked
  personal section or use Omarchy's override points (`~/.config/hypr/*.lua`
  stubs exist exactly for this).
- `/usr/share/omarchy/` is package-owned: READ-ONLY, never edit. Reading is
  encouraged (`omarchy commands`, `cat $(which omarchy-<cmd>)` to understand
  behavior).
- `~/.config/**` is user-owned; Omarchy updates never touch it. Only
  `omarchy refresh <app>` (backs up first) or `omarchy reinstall configs`
  (DANGEROUS once home-manager owns `$HOME` - writes through symlinks)
  reset them.
- Theming flows through `omarchy theme set <name>` at runtime. Do not
  hardcode palettes into themed configs (the old Tokyo Night blocks from
  arch-setup were dropped for this reason).

## Two apply surfaces, both run BY THE USER

- System layer: `./build/omarchy-setup.sh` (self-sudoes, idempotent).
- User layer: `./rebuild.sh` (home-manager switch; lands with Phase 4.3).

Never run either on the user's behalf. Validate instead and tell the user
the change is ready to apply.

## Working on tmux configurations

Always test changes against a separate tmux server/socket so as not to
interfere with the server used for active development:

```sh
tmux -L verify-$$ -f config/tmux/tmux.conf new-session -d   # then list-keys/show-hooks
tmux -L verify-$$ kill-server                               # ALWAYS clean up
```

Note the grep trap: `tmux list-keys` shows ALL key tables; filter with
`list-keys -T prefix`. After editing the repo copy, sync the live file
(`~/.config/tmux/tmux.conf`) and reload with `tmux source-file`. Until
Phase 4.3 puts HM's link in place there are TWO copies - keep them in sync;
after Phase 4.3 the repo copy is authoritative via symlink.

## home-manager scope boundary

HM stays user-scope only and must not expand into desktop-config territory:

- HM owns: `.bashrc` (composed over omarchy's env-bootstrap + rc),
  `.ssh/config`, `.config/git/ignore`, `.config/tmux/tmux.conf`,
  opencode JSONs, agent skills (config/skills/, linked into
  `~/.agents/skills/` + `~/.claude/skills/`), the global agent context
  (config/agents/AGENTS.md as `~/.config/opencode/AGENTS.md`, plus
  instructions into `~/.agents/instructions/`), the npm-global prefix that
  holds pinned axi-family CLIs (see config/skills/install-axi.sh),
  `home.sessionPath` (tmux-scripts, npm-global bin), and packages not in
  Arch repos (treehouse, uv).
- Package placement rule: available in the Arch repos -> `omarchy pkg add`
  (system layer, e.g. ansible-core). AUR-only -> `yay` directly (system layer,
  e.g. blesh-git) - `omarchy pkg add` is just `pacman -S`, it cannot reach AUR.
  NOT packaged anywhere or needing user-scope pinning -> `home.packages`
  (nix layer). Never both.
- HM deliberately does NOT own: `~/.config/git/config` (hand-maintained on
  this box - don't add programs.git), `.config/nvim` (Phase 4.4 will link
  the kickstart fork; omarchy-nvim seed stays until then), any hyprland/
  shell/theme/terminal config (omarchy owns those).
- Do NOT add HM modules that generate hyprland-style desktop config; track
  plain override files under `config/hypr/` instead when Phase 5 lands.

## Patched kernel loop

~monthly, when Arch bumps `linux`: `~/build/linux/rebuild-patch.sh`
(staged by `./build/setup-patch.sh`), which builds and `pacman -U`s the new
patched packages. IgnorePkg protects them from `omarchy update`; the
`pre-refresh-pacman.d/keep-ignorepkg` hook survives pacman.conf rewrites.
See docs/macbookpro12-1-keyboard-kernel-patch.md before touching patches.
The `\\_SB` double-backslash in `apple-keyboard-spi.conf` is load-bearing -
never "fix" it to one backslash.
