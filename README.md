# omarchy-setup

Customizations on top of [Omarchy](https://omarchy.org/) for the
MacBookPro12,1 workstation `archeus`. Omarchy is the base system and stays
stock wherever possible; this repo carries only what Omarchy does not own:

- the MacBookPro12,1 internal keyboard/trackpad fix (patched kernel +
  initramfs/modprobe/udev stack),
- F5/F6 keyboard-backlight stepping via actkbd,
- the tmux session workflow composed on top of Omarchy's tmux config,
- home-manager for user-scope config and out-of-repo packages.

`~/arch-setup` is the historical record of the previous hand-built Arch
setup; do not evolve it. The migration story that led here is in
[docs/omarchy-migration-plan.md](docs/omarchy-migration-plan.md).

## Layout

| Path | What |
| --- | --- |
| `build/omarchy-setup.sh` | System-layer deploy (idempotent, self-sudoes). See below. |
| `build/setup-patch.sh`, `build/rebuild-patch.sh`, `build/*.patch` | Patched-kernel build loop (`setup-patch.sh` stages into `~/build/linux/`). |
| `config/modprobe.d/` | SPI SIEN(1) reroute, dw_dmac blacklist, kbd/screen backlight floors -> `/etc/modprobe.d/`. |
| `config/udev/rules.d/` | `60-spi-pio.rules` (SPI runtime-PM pin), `90-power-profile.rules` (AC/battery profile switch, pending Phase 6 testing). |
| `config/actkbd/` | F5/F6 backlight stepping: conf, systemd unit, helper script. |
| `config/libinput/local-overrides.quirks` | Tags the SPI keyboard as internal so touchpad disable-while-typing fires -> `/etc/libinput/local-overrides.quirks`. |
| `config/hypr/input.lua` | Personal input stub: natural scroll, tap-to-click off. HM-linked to `~/.config/hypr/input.lua`; everything else under hypr/ stays Omarchy's. |
| `config/hypr/monitors.lua` | eDP-1 scale 1.6 (GDK_SCALE 2). HM-linked to `~/.config/hypr/monitors.lua`. |
| `config/tmux/tmux.conf` | Composed tmux config = Omarchy default + personal section. |
| `config/tmux/tmux-scripts/` | Sessionizer family (f sessionizer, todos, treehouse pool). |
| `config/bash/bashrc-personal` | Shell fragments sourced by `~/.bashrc`. |
| `flake.nix` / `home.nix` | home-manager, user scope only (pending Phase 4.3 slim-down). |
| `docs/macbookpro12-1-keyboard-*.md` | The full keyboard-fix saga: SPI DMA quirk, kernel patches, S3 resume, backlight. |

## Two apply surfaces

- **System layer** (`sudo`, `/etc`, packages): `./build/omarchy-setup.sh`.
  Deploys modprobe.d, the mkinitcpio MODULES drop-in, the udev rule, actkbd,
  the patched kernel (`pacman -U` from `~/build/linux/linux/`), the IgnorePkg
  hold, and the `pre-refresh-pacman.d/keep-ignorepkg` hook. cmp-gated; only
  rebuilds the initramfs when something changed.
- **User layer** (`$HOME`, nix): `./rebuild.sh` (home-manager switch).
  **The user always runs these scripts themselves** - never on someone's
  behalf.

## Recreate from scratch

Prerequisite hardware: **USB keyboard + mouse.** The internal keyboard is
dead until Phase "keyboard fix" completes below (also true in the installer).

1. **Install Omarchy** from its ISO: full disk, encryption on. Answer the
   wizard; let it boot to the Quickshell desktop.
2. **Clone this repo**: connect Wi-Fi (network menu in the shell), then
   `git clone <this-repo> ~/omarchy-setup`.
3. **Packages**: `yay -S acpi_call-dkms actkbd` (AUR; run from a terminal,
   not a foot split, in case yay prompts for sudo).
4. **Kernel**: restore the stashed packages from backup if available
   (`~/backup/kernel-pkgs/linux-*.pkg.tar.zst` -> `~/build/linux/linux/`),
   otherwise build: `./build/setup-patch.sh && ~/build/linux/rebuild-patch.sh`
   (1-2 h). `omarchy-setup.sh` installs them either way.
5. **Deploy**: `./build/omarchy-setup.sh`.
6. **Reboot and verify**:
   ```sh
   uname -r                                  # local pkgrel, e.g. ...-1.1
   journalctl -k -b | grep -Ei 'disabling DMA|applespi'
   ```
   Keyboard must work at the Plymouth LUKS prompt, in the desktop, and after
   suspend/wake. F5/F6 must step the keyboard backlight.
7. **Nix + home-manager**: `./build/bootstrap-nix.sh` (installs the nix
   daemon per the gotchas inline, then runs the first switch straight from
   the flake). Later changes: `./rebuild.sh`.
8. **User workflow**: tmux config lands via HM link at
   `~/.config/tmux/tmux.conf`; `treehouse` comes back on PATH with the first
   rebuild; per-project `.tmux-sessionizer-config` files return with each
   clone.
9. **Secrets**: `.env` for opencode (see
   [docs/opencode-secrets.md](docs/opencode-secrets.md)), `~/.ssh/`,
   `~/.gnupg/`.

## Daily ops cheatsheet

```sh
omarchy update          # NEVER raw `pacman -Syu` (ALPM guard blocks it)
omarchy pkg add <pkg>   # repo or AUR installs
omarchy commands        # discover everything else
```

- **Kernel bumps** (~monthly): `~/build/linux/rebuild-patch.sh`, reboot.
  IgnorePkg keeps `omarchy update` off the patched kernel; the
  `pre-refresh-pacman.d/keep-ignorepkg` hook re-adds the hold after
  `omarchy refresh pacman` rewrites `/etc/pacman.conf`.
- **Rollback**: snapper snapshots + Limine snapshot menu replace the old
  GRUB/btrfs flow (`limine-snapper-sync` manages entries).
- **Theme**: `omarchy theme set <name>` - drives shell, terminals, and syncs
  colors into running tmux at runtime. Never rewrite themed configs by hand;
  layer overrides instead.
- **HAZARD**: never run `omarchy reinstall configs` once home-manager owns
  `$HOME` files - it `cp -af`s `/etc/skel/.` over `$HOME`, writing *through*
  HM symlinks into this repo's files. If it ever runs:
  `git checkout -- . && ./rebuild.sh`.

## Migration status

Tracked against docs/omarchy-migration-plan.md:

- [x] Phase 0-2: backup, install, keyboard fix fully deployed and verified
- [x] Phase 3: tmux stack (composed conf live; sessionizer scripts on PATH)
- [x] Phase 4.1: ghostty installed as default terminal
- [x] Phase 4.2: bash personal fragments (EDITOR, vim alias, opencode
      wrapper, C-f sessionizer) via config/bash/bashrc-personal
- [x] Phase 4.3: nix daemon bootstrapped, flake slimmed, first switches
      green (`./build/bootstrap-nix.sh` + `./rebuild.sh`). HM owns
      .bashrc/tmux.conf/git-ignore/opencode links; treehouse back on
      PATH for `prefix W`.
- [x] Secrets restore: `.vault.env` + `.env` restored from the backup drive
      (`.env` copied as plaintext; `build/decrypt-secrets.sh` remains for
      re-deriving it from `.env.vault` - requires `ansible-core`, install
      with `omarchy pkg add ansible-core` if wanted). The `~/.ssh/github`
      key, `known_hosts`, and gnupg public keyring are also restored.
      NOTE: `.env` contents are never read or printed by agents.
- [ ] Phase 4.4: nvim config ONLY (kickstart fork via HM `.config/nvim`
      link). All other apps install ad hoc with `omarchy pkg add` /
      `omarchy install <name>` when needed - deliberately NOT pre-ported.
      NOTE: opencode + node already present via mise - do NOT double-install
      pacman nodejs/npm; keep mise as their owner.
- [x] Phase 5: Hyprland ports done - input.lua (natural scroll on,
      tap-to-click off) + monitors.lua (scale 1.6) tracked and HM-linked;
      Super+C/V universal copy-paste is stock Omarchy (no port needed);
      sensitivity/scroll_factor kept at Omarchy defaults. Validated with
      hyprctl reload + configerrors.
- [ ] Phase 6: test AC/battery profile switching; retire arch-setup to archive
