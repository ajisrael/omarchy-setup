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

- Agent attention toasts (config/opencode/plugins/omarchy-notify.ts, HM-linked
  into ~/.config/opencode/plugins/) fire Omarchy notification-daemon toasts
  via omarchy-notification-send when a session needs the user (permission,
  question, error, idle-after-work). Each toast carries an omarchy-exec hint
  -> config/bin/omarchy-notification-jump (HM-linked to ~/.local/bin/), which
  on click switches the attached tmux client to the notifying window, makes
  its pane active, and raises the foot window (found by walking the tmux
  client's ppid ancestry against hyprctl clients). Load-bearing details: the
  exec command is resolved at TOAST TIME (socket + TMUX_PANE from the
  opencode process env) because click time runs from the shell process with
  no tmux env; a libnotify "default" action would instead keep opencode
  blocked on the toast and die unanswered on shell restart. Omarchy popups
  render no inline buttons (only one click action), so permission toasts
  click through to config/bin/omarchy-permission-menu: Omarchy's option menu
  with Accept/Reject POSTing `{"response":"once"|"reject"}` to the opencode
  server the plugin bakes into the exec (serverUrl is a PluginInput field)
  and "Jump to window" falling through to the jump script. Suppression:
  paneIsVisible() compares the pane's session:window against every attached
  client's current view, so toasts only fire when the user is NOT looking at
  that window. Restart opencode to pick up plugin edits.

- HM owns: `.bashrc` (composed over omarchy's env-bootstrap + rc),
  `.ssh/config`, `.config/git/ignore`, `.config/tmux/tmux.conf`,
  opencode JSONs, agent skills (config/skills/, linked into
  `~/.agents/skills/` + `~/.claude/skills/`), the global agent context
  (config/agents/AGENTS.md as `~/.config/opencode/AGENTS.md`, plus
  instructions into `~/.agents/instructions/`), the npm-global prefix that
  holds pinned axi-family CLIs (see config/skills/install-axi.sh),
  `home.sessionPath` (tmux-scripts, npm-global bin), packages not in
  Arch repos (treehouse, uv), and the AC stay-awake watcher
  (`config/bin/ac-stay-awake` -> `~/.local/bin/`, `ac-stay-awake.service`
  user unit): flips Omarchy's idle stay-awake flag while plugged in so the
  screen never blanks or locks on AC power, and the waynergy client
  (`config/waynergy/config.ini` -> `~/.config/waynergy/`, `waynergy.service`
  user unit): the AUR `waynergy` binary is the system layer, its wlr backend
  injects the synergy server's input via Hyprland's virtual pointer/keyboard
  (no portal, no uinput). The synergy server is a macOS primary, so the
  waynergy config pins the mac keycodes map (`xkb_keymap`, kVK+8 codes) with
  `xkb_key_offset = 7` - keyboard keys arrive as raw macOS scancodes, not evdev.
  Mac Command is an exception: the server sends it as raw 56 (kVK+1), so the
  `[raw-keymap]` entry `56 = 64` is what makes it land on Super. Two layers are
  load-bearing and both live in the repo:
  (1) `56 = 64` (+ xkb_key_offset 7 = keycode 71) so the wlr backend emits
  71 - 8 = 63 = the `LWIN` keycode in the mac map; and (2) the keymap ALSO maps
  keycode 71 to `Super_L` (`<LWIN2> = 71` + symbols entry): Hyprland keybinds
  read `m_lastMods` from waynergy's `modifiers` request, which is serialized
  from waynergy's own internal xkb state fed by keycode 71. Without layer (2)
  the Command key types text but never triggers SUPER keybinds (workspace
  switch etc.) - which is precisely the bug we fixed. When debugging, remember
  waynergy tracks modifiers itself (synergy's server mod mask is ignored); the
  emitted protocol keycode is always `key - 8`.
- Package placement rule: available in the Arch repos -> `omarchy pkg add`
  (system layer, e.g. ansible-core). AUR-only -> `yay` directly (system layer,
  e.g. blesh-git) - `omarchy pkg add` is just `pacman -S`, it cannot reach AUR.
  NOT packaged anywhere or needing user-scope pinning -> `home.packages`
  (nix layer). Never both.
- HM deliberately does NOT own: `~/.config/git/config` (hand-maintained on
  this box - don't add programs.git), `.config/nvim` (Phase 4.4 will link
  the kickstart fork; omarchy-nvim seed stays until then), shell/theme/
  terminal config (omarchy owns those).
- Exception: the hyprland personal override stubs ARE HM-owned (Phase 5
  landed early). `config/hypr/{bindings,input,monitors}.lua` are linked into
  `~/.config/hypr/` (see `home.nix`), and the nix-store target is writable.
  Do NOT edit them under `~/.config/hypr/` directly; edit the repo copy and
  run `./rebuild.sh`.
- After a `./rebuild.sh` swap, Hyprland does NOT auto-reload configs replaced
  by symlinks. rebuild.sh now runs `hyprctl reload` (and prints any
  `hyprctl configerrors`) at the end, so a rebuild is fully self-contained.
  If editing hypr files directly (no rebuild), still run `hyprctl reload` and
  check `hyprctl configerrors` yourself.
- Do NOT add HM modules that generate hyprland-style desktop config; track
  plain override files under `config/hypr/` instead.

## Radio recovery scripts (maint/)

`maint/bt-recover` and `maint/wifi-recover` are manual one-shot recovery
helpers (mirror-style CLIs: no args = recover-if-degraded, `--check` probes,
`--force` ignores health). wifi-recover is ALSO the canonical recovery used
around every suspend/resume via `config/systemd/system-sleep/brcmfmac-reload`
(installed to `/usr/local/sbin/wifi-recover` by omarchy-setup.sh); edit it in
the repo, not in place.

Wi-Fi wedge after suspend: BCM43602 firmware stops answering and every
cfg80211 call returns -5 (EIO) while the interface stays UP and rfkill stays
unblocked, so the shell wifi module shows an empty list in both states. The
blast radius of the fix is a driver reload. LOAD-BEARING ORDER: `brcmfmac_wcc`
holds a reference on `brcmfmac`, so `modprobe -r brcmfmac` alone ALWAYS
fails silently - unload `brcmfmac_wcc` first, then `brcmfmac`, then
`modprobe brcmfmac_wcc` (pulls the core back in). Never "simplify" an inline
`modprobe -r brcmfmac` back into a hook; that was the original bug.

PROBING AT RESUME CANNOT WORK - do not reintroduce it as an "optimization".
Two independent failure modes were observed with the old probe-based hook:
(i) `iw dev link` returns exit 0 with "Not connected." on a wedged-but-
disconnected interface without any firmware round-trip, so it reports
"healthy" while the chip is dead; (ii) the firmware can die AFTER the probe
passes (chip answered at 20:50:07, wedged at 20:50:09 under NetworkManager's
reconnect load). So the post-resume hook reloads UNCONDITIONALLY (the
original inline hook's true intent), and a stale wedge is additionally caught
pre-suspend (`--pre-suspend`: probe with a real firmware round-trip - station
dump when associated, sudo scan otherwise - and reload only if degraded),
because a wedged chip BLOCKS suspend entry: `brcmf_pcie_pm_enter_D3` times
out and `PM: Some devices failed to suspend` aborts the sleep.

`maint/wifi-cycle-test` reproduces the wedge in seconds without a long lid
close: it arms an RTC alarm (`rtcwake -m no`), `systemctl suspend`s (so the
real systemd-sleep hooks run - NOT `rtcwake -m mem`, which bypasses them),
then greps the journal for hook output and checks health. A wedge can make
the machine fail to suspend at all, which also makes the D3-timeout symptom
directly observable from this script.

## Patched kernel loop

~monthly, when Arch bumps `linux`: `~/build/linux/rebuild-patch.sh`
(staged by `./build/setup-patch.sh`), which builds and `pacman -U`s the new
patched packages. IgnorePkg protects them from `omarchy update`; the
`pre-refresh-pacman.d/keep-ignorepkg` hook survives pacman.conf rewrites.
See docs/macbookpro12-1-keyboard-kernel-patch.md before touching patches.
The `\\_SB` double-backslash in `apple-keyboard-spi.conf` is load-bearing -
never "fix" it to one backslash.
