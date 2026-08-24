# Omarchy Migration Plan (archeus → omarchy, MacBookPro12,1)

Plan for replacing this hand-built Arch + home-manager setup with omarchy as
the base system, while carrying over the non-negotiables: the tmux +
tmux-sessionizer workflow, the working internal keyboard/trackpad, and
declarative user-config management via nix/home-manager (which coexists with
omarchy cleanly - Phase 4). The terminal is flexible: omarchy's default foot
is fine as long as image.nvim can still render images inline, which decides
the terminal choice in Phase 4 (spoiler: ghostty).

Companion docs: [arch-setup-mac.md](arch-setup-mac.md) (the current install),
[macbookpro12-1-keyboard-spi-fix.md](macbookpro12-1-keyboard-spi-fix.md),
[macbookpro12-1-keyboard-kernel-patch.md](macbookpro12-1-keyboard-kernel-patch.md),
[macbookpro12-1-keyboard-s3-resume.md](macbookpro12-1-keyboard-s3-resume.md),
[macbookpro12-1-keyboard-backlight.md](macbookpro12-1-keyboard-backlight.md),
and [omarchy-features-review.md](omarchy-features-review.md) (the earlier
feature comparison). The omarchy checkout referenced throughout is
`~/examples/omarchy` (basecamp/omarchy, `quattro` branch).

## Verdict up front

The migration is viable. Omarchy is two pacman packages (`omarchy`,
`omarchy-settings`) on top of stock Arch - it does not own the kernel build,
`/etc/modprobe.d`, `/etc/mkinitcpio.conf.d`, `/etc/udev/rules.d`, or locally
installed packages, which is exactly where the entire keyboard fix lives. Its
installer will do nothing for a MacBookPro12,1 (its SPI-keyboard fix only
matches `MacBook[89],1|MacBook1[02],1|MacBookPro13,x|MacBookPro14,x`), so the
fix ports over as a post-install step. The old `pacman -U` of a locally built
kernel is not blocked by omarchy's update guard (the guard only intercepts
`-S`+`-u` sysupgrades), and `IgnorePkg` keeps `omarchy update` from
overwriting the patched kernel.

## How omarchy is shaped (migration-relevant facts)

- **Two layers.** `omarchy-settings` owns `/etc` drop-ins (mkinitcpio hooks,
  NetworkManager, sysctl, oomd, plymouth, sddm, snapper, limine configs) and
  seeds `/etc/skel`; `omarchy` owns `/usr/share/omarchy` (the `omarchy-*`
  commands, install scripts, themes, the Quickshell desktop). User config in
  `~/.config/**` is explicitly yours - `manual/31-dotfiles.md` says so, and
  `~/.bashrc` additions are never overwritten.
- **Boot stack differs from here.** Omarchy boots via **Limine + UKI**
  (`/boot/EFI/Linux/omarchy_linux.efi`), not GRUB. It still uses **mkinitcpio**
  with drop-ins in `/etc/mkinitcpio.conf.d/` - `etc/mkinitcpio.conf.d/
  omarchy_hooks.conf` sets `HOOKS=(base udev plymouth keyboard autodetect
  microcode modconf kms keymap consolefont block encrypt filesystems fsck
  btrfs-overlayfs)`. Two consequences that matter to us: `modconf` is present
  (so `/etc/modprobe.d` reroutes get bundled into the image for the LUKS
  prompt), and the initramfs is **busybox/udev, not systemd** (matters for the
  reroute fallback, see Phase 2).
- **Updates run through `omarchy update`.** Raw `sudo pacman -Syu` is aborted
  by an ALPM hook (`omarchy-update-pacman-guard`) unless bypassed with
  `sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu`. `pacman -U` (local
  packages) and `pacman -S <name>` (single installs) are NOT blocked.
  `omarchy update` = free-space check → snapper snapshot → pacman -Syu →
  migrations → hooks → restart checks.
- **`omarchy refresh pacman` rewrites `/etc/pacman.conf`** from a channel
  template - hand-edits like `IgnorePkg` are lost when it runs. The sanctioned
  survival mechanism is the `pre-refresh-pacman` hook in
  `~/.config/omarchy/hooks/pre-refresh-pacman.d/` (its shipped `.sample` is
  literally about re-adding IgnorePkg lines).
- **Snapshots.** snapper + `limine-snapper-sync` replace this repo's
  `build/snapshot.sh` + GRUB snapshot submenu. The snapshot safety net
  survives the migration with different commands.
- **AUR helper is yay**, not paru. `omarchy-pkg-add <pkg>` installs from
  either repo or AUR, and `omarchy update` runs `yay -Sua` for foreign
  packages. acpi_call-dkms, actkbd, google-chrome, and handy-bin all resolve
  via yay. (pi and treehouse stay nix packages - no AUR needed.)
- **The Quickshell shell replaces waybar + mako + wofi + hyprlock +
  hypridle** with one process. All of those configs are retired, not ported.
- **Terminals are pluggable**: foot is the default; alacritty, ghostty, and
  kitty are first-class `omarchy-install-terminal` options, each with a
  config template and theme integration (`ghostty.conf.tpl` etc. in
  `default/themed/`).
- **Theming is runtime-safe for tmux**: `omarchy-theme-set-tmux` only sets
  tmux options/environments in the running server - it never rewrites
  `~/.config/tmux/tmux.conf`. Omarchy has a built-in `tokyo-night` theme.
- **What omarchy already ships that we hand-built here** (no porting needed):
  NetworkManager `wifi.powersave=2`, `fs.inotify.max_user_watches=524288`,
  systemd-oomd tuning, power-profiles init at login
  (`omarchy-powerprofiles-init`, with the shell watching UPower for AC
  changes), a snapshotting update flow, and a large capture/audio/network
  script suite.

## What carries over, what is replaced, what dies

| Current (arch-setup) | On omarchy | Action |
| --- | --- | --- |
| Kernel patch stack (0001 PIO + 0002 S3, `rebuild-patch.sh`) | n/a - omarchy ships stock `linux` | **Port** (Phase 2). Same rebuild loop per kernel bump |
| `apple-keyboard-spi.conf` SIEN(1) reroute, `blacklist-lpss-dma.conf` | n/a | **Port** to `/etc/modprobe.d/` |
| `MODULES=(...)` in `/etc/mkinitcpio.conf` | omarchy owns HOOKS, MODULES unset | **Port** as a drop-in in `/etc/mkinitcpio.conf.d/` |
| `60-spi-pio.rules` udev PM pin | n/a | **Port** |
| actkbd + F5/F6 backlight stepping | n/a (omarchy's system-sleep keyboard-backlight script is ASUS/hibernate-specific) | **Port** |
| modprobe.d backlight floors (`kbd-backlight.conf`, `backlight-screen.conf`) | n/a | **Port** |
| GRUB + btrfs snapshot submenu + `restore.sh` | Limine + snapper + `limine-snapper-sync` | **Replaced** by omarchy; learn the new flow |
| tmux.conf + tmux-scripts (sessionizer family) | omarchy ships its own tmux config | **Port** (Phase 3) - full replacement of `~/.config/tmux/tmux.conf` |
| treehouse via flake input | n/a | **Keep** - the flake input survives (nix stays, Phase 4.3) |
| zsh + p10k + omz via home-manager | bash + starship is the omarchy default | **Retire** - a few personal fragments port into the HM `~/.bashrc` (Phase 4.2) |
| kitty via pacman + config symlink | foot default; ghostty implements the kitty graphics protocol (foot does not) | **Switch** to ghostty via `omarchy-install-terminal ghostty` (Phase 4.1) |
| waybar/mako/wofi/hyprlock/hypridle configs | Quickshell shell | **Retire** |
| hyprland.lua (Lua DSL, Hyprland 0.56) | omarchy's Lua config: `hyprland.lua` + `bindings.lua`/`input.lua`/`monitors.lua`/`looknfeel.lua`/`autostart.lua` | **Port selectively** (Phase 5) |
| Tier-1 scripts from `omarchy-features-review.md` (capture suite, nightlight, launch-or-focus, window toggles, audio switch/restart, wifi QR, taildrop, keybinding cheatsheet) | omarchy ships all of these natively | **Retire** - use the omarchy commands |
| home-manager flake (`flake.nix`/`home.nix`) | disjoint surface: pacman world + `/etc` + `/usr/share/omarchy` vs `$HOME` | **Keep** - slimmed to what omarchy does not own (Phase 4.3) |
| `system-packages.nix` + `build/system-packages.sh` | pacman/yay + `omarchy-pkg-add` | **Retire** |
| `build/system-config.sh` | n/a | **Replaced** by a new `build/omarchy-setup.sh` (Phase 2/6) |
| nvim kickstart fork submodule | omarchy-nvim is default | **Port** user's own nvim config (Phase 4.4) |
| opencode (pacman) | in omarchy base packages | **Keep**, same pin |
| pi coding agent (nix pkg) | AUR alternative exists | **Keep** - stays in `home.packages` |
| tailscale + taildrop scripts | `omarchy-install-service-tailscale` + omarchy's taildrop commands | **Replaced** |

## Phase 0 - Prepare on archeus (before touching the disk)

### 0.1 Full backup

Omarchy's full-disk install wipes the drive; the btrfs snapshot safety net
dies with it. Back up to an external drive:

- `$HOME` in full (worktrees under `~/.treehouse/` can be pruned first with
  `treehouse prune --all` to shrink the copy; leases you care about should be
  committed/pushed).
- Secrets that are not in the repo: `~/.ssh/` (includes the `github` key),
  `~/.pi/agent/auth.json`, `~/.gnupg/`, browser profiles if wanted
  (`~/.config/google-chrome/`), `~/.local/share/` for apps worth keeping.
- A manifest for rebuilds:

```sh
pacman -Qqen > ~/backup/pacman-native.txt
pacman -Qqem > ~/backup/pacman-foreign.txt
sudo tar czf ~/backup/etc-modprobe-mkinitcpio.tar.gz \
  /etc/modprobe.d /etc/mkinitcpio.conf /etc/udev/rules.d /etc/actkbd.conf \
  /etc/systemd/system/actkbd.service
```

- The encrypted secrets: `.env` / ansible-vault material used by opencode
  (see [opencode-secrets.md](opencode-secrets.md)) - the `.env` lives
  untracked in this repo; push or copy it.

Keep the external backup until Phase 2 verification is green; it is also the
rollback path (see Risks).

### 0.2 Make the repo the source of truth for the fix

Two live files are NOT repo-tracked yet (they were created during the original
install per arch-setup-mac.md): `/etc/modprobe.d/apple-keyboard-spi.conf` and
`/etc/modprobe.d/blacklist-lpss-dma.conf`. Commit copies into
`config/modprobe.d/` now so the migration (and any future reinstall) deploys
from the repo, not from a memory of what `/etc` contained:

```sh
cp /etc/modprobe.d/apple-keyboard-spi.conf  ~/arch-setup/config/modprobe.d/
cp /etc/modprobe.d/blacklist-lpss-dma.conf  ~/arch-setup/config/modprobe.d/
```

Note the `\\_SB` double-backslash in `apple-keyboard-spi.conf` is load-bearing
(kmod strips one level; a single `\_SB` silently fails with
`AE_BAD_PARAMETER` - see the SPI-fix doc). Never "fix" it to one backslash.

### 0.3 Prebuild the patched kernel (day-one shortcut)

The kernel build takes 1-2 h on this machine. Do it BEFORE migrating and stash
the packages, so the first omarchy boot gets a working keyboard in minutes
instead of hours:

```sh
~/build/linux/rebuild-patch.sh   # or the manual flow in the kernel-patch doc
mkdir -p ~/backup/kernel-pkgs
cp ~/build/linux/linux-*.pkg.tar.zst ~/backup/kernel-pkgs/   # linux + linux-headers
```

A kernel package built here installs cleanly on the omarchy system: same
distro, same package name (`linux`), the version just needs to be >= what the
ISO installed (it will be, or at worst equal-with-higher-pkgrel - if omarchy's
stock kernel is NEWER than the stashed build, still install the stash; the
downgrade is safe for the keyboard fix and you rebuild on the next bump).
Also copy `build/rebuild-patch.sh`, `setup-patch.sh`, and both patch files
into the backup - they are repo-tracked, but `~/build/linux/` also holds the
imported PGP keys and ccache state that make the next build fast.

### 0.4 Hardware and media

- **USB keyboard + mouse required.** The internal keyboard/trackpad are dead
  in omarchy's live ISO (the fix is not baked into its kernel or initramfs) -
  same situation as the original Arch install.
- USB stick with the omarchy ISO (from omarchy.org). Apple Secure Boot is
  already disabled on this machine (Arch boots), nothing to redo.
- Optionally: test-boot the ISO first and confirm Wi-Fi works (BCM43602 on
  brcmfmac + linux-firmware - the installer's Broadcom fix targets BCM4360/
  4331 only and correctly ignores this chip; brcmfmac is in-tree). This is the
  go/no-go smoke test for the whole migration.

## Phase 1 - Install omarchy

1. Boot the ISO holding Option, pick the orange EFI Boot device.
2. Full-disk install, encryption on (a fresh LUKS passphrase is set here).
   The internal keyboard stays dead through the installer - use the USB one.
3. Answer the wizard (keyboard layout, username, etc.). At first login the
   Quickshell desktop comes up; the USB keyboard/mouse still drive everything.

Do NOT spend time configuring the desktop yet - keyboard first.

## Phase 2 - Internal keyboard (critical path)

Everything below assumes the repo is cloned to `~/arch-setup` on the new
system (Wi-Fi password via the shell's network menu, then `git clone` + copy
the `.env`/secrets back from backup as needed).

### 2.1 Packages

```sh
omarchy-pkg-add acpi_call-dkms   # AUR via yay; dkms + base-devel are in the ISO's set
omarchy-pkg-add actkbd           # AUR
```

`acpi_call-dkms` builds against the installed stock kernel now, and will
rebuild against the patched kernel automatically when it replaces stock
(DKMS pacman hook). If `yay` first-run prompts for a sudo loop, run it from a
terminal, not the foot split.

### 2.2 modprobe.d

Deploy from the repo (this is what the new `build/omarchy-setup.sh` will do;
run manually the first time):

```sh
sudo install -Dm644 ~/arch-setup/config/modprobe.d/apple-keyboard-spi.conf /etc/modprobe.d/
sudo install -Dm644 ~/arch-setup/config/modprobe.d/blacklist-lpss-dma.conf /etc/modprobe.d/
sudo install -Dm644 ~/arch-setup/config/modprobe.d/kbd-backlight.conf /etc/modprobe.d/
sudo install -Dm644 ~/arch-setup/config/modprobe.d/backlight-screen.conf /etc/modprobe.d/
```

- `apple-keyboard-spi.conf` - the SIEN(1) install reroute (still required even
  with the patched kernel: the DMI quirk fixes DMA only, not the bogus
  `UIST=1` ACPI report).
- `blacklist-lpss-dma.conf` - redundant on the patched kernel (dw_dmac is
  built-in), kept as belt-and-braces for any stock-kernel boot.
- The two backlight floors (SMC keyboard LED at 50% after applesmc loads -
  covers the LUKS prompt; intel_backlight at 50% after i915).

Omarchy's only modprobe.d file is `omarchy-usb-autosuspend.conf`; no
conflicts.

### 2.3 mkinitcpio drop-in

Omarchy sets HOOKS but leaves MODULES alone, and its own drop-ins use
`MODULES+=` (thunderbolt) or guarded reads. Write a drop-in that sorts BEFORE
`omarchy_hooks.conf` (name starting with a letter < 'o') so a plain
assignment cannot be clobbered by anything later, and use `MODULES=(...)`:

```sh
sudo tee /etc/mkinitcpio.conf.d/apple-spi-keyboard.conf >/dev/null <<'EOF'
# MacBookPro12,1 internal keyboard/trackpad: acpi_call first (the modprobe.d
# install reroute fires SIEN(1) through it when applespi is modprobed), then
# the SPI host stack, then applespi. applesmc rides along so the modprobe.d
# kbd-backlight floor can fire inside the initramfs too.
MODULES=(acpi_call spi_pxa2xx_platform spi_pxa2xx_pci applespi applesmc)
EOF
```

`modconf` in omarchy's HOOKS bundles `/etc/modprobe.d` into the image, so the
reroute executes when `applespi` is modprobed in early userspace - the same
mechanism that works today on the systemd initramfs. Omarchy's `kms` hook is
unaffected (the iGPU is Intel; the kms-dropping logic only triggers on
nvidia_drm early-loads).

**Known risk + fallback:** mkinitcpio's busybox `base` initramfs must use
kmod's real `modprobe` for `install` commands to be honored (busybox's
builtin modprobe ignores them). mkinitcpio ships kmod modprobe for exactly
this, but verify on first boot. If the keyboard is dead at the LUKS prompt
while working after login, switch to the initcpio-hook form from
[macbookpro12-1-keyboard-spi-fix.md](macbookpro12-1-keyboard-spi-fix.md):
under omarchy's busybox/udev initramfs the hook's `run_hook` DOES execute
(it was only dead under the systemd initramfs). Drop
`/etc/initcpio/hooks/apple-spi` + `/etc/initcpio/install/apple-spi` from that
doc, remove `applespi` from the MODULES drop-in above (the hook loads the
stack in the right order itself), and add `apple-spi` to HOOKS via a drop-in
that sorts AFTER `omarchy_hooks.conf` (mkinitcpio sources conf.d files in
lexical order, and omarchy's own thunderbolt drop-in relies on the same
trick):

```sh
sudo tee /etc/mkinitcpio.conf.d/zz-apple-spi-hook.conf >/dev/null <<'EOF'
# Loaded after omarchy_hooks.conf, so HOOKS is already set - just append.
HOOKS+=(apple-spi)
EOF
```

### 2.4 udev rule (runtime PM pin)

```sh
sudo install -Dm644 ~/arch-setup/config/udev/rules.d/60-spi-pio.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=pci
```

Still required: the minimal patch does not include the upstream
runtime-autosuspend lockout, and without `power/control=on` on the SPI
controller (PCI ID `0x9ce6`) PIO mode hits PCIe Completion Timeouts.

### 2.5 Patched kernel

Install the stashed packages over omarchy's stock kernel:

```sh
sudo pacman -U ~/backup/kernel-pkgs/linux-*.pkg.tar.zst
```

Not blocked by the update guard (`pacman -U` is not a sysupgrade). The
mkinitcpio pacman hook rebuilds the initramfs/UKI for the new kernel version;
`limine-mkinitcpio-hook` refreshes the Limine entries. DKMS rebuilds
acpi_call for it. Then protect it (omarchy's pacman.conf template has no stock `# Pacman
won't upgrade...` comment to anchor on, but it does have `HoldPkg`):

```sh
sudo sed -i '/^HoldPkg/a IgnorePkg = linux linux-headers linux-docs' /etc/pacman.conf
```

And make that survive `omarchy refresh pacman` (which rewrites pacman.conf
from a template) via the sanctioned hook:

```sh
mkdir -p ~/.config/omarchy/hooks/pre-refresh-pacman.d
cat > ~/.config/omarchy/hooks/pre-refresh-pacman.d/keep-ignorepkg <<'EOF'
#!/bin/bash
# Re-add the patched-kernel hold after omarchy-refresh-pacman rewrites
# /etc/pacman.conf from the channel template.
if ! grep -q '^IgnorePkg' /etc/pacman.conf; then
  sudo sed -i '/^HoldPkg/a IgnorePkg = linux linux-headers linux-docs' /etc/pacman.conf
fi
EOF
chmod +x ~/.config/omarchy/hooks/pre-refresh-pacman.d/keep-ignorepkg
```

### 2.6 Rebuild the UKI and reboot

```sh
sudo mkinitcpio -P          # regenerates initramfs + omarchy UKI for all presets
ls -l /boot/EFI/Linux/      # verify omarchy_linux.efi was just rewritten
sudo reboot
```

At the reboot: keyboard must work at the **Plymouth LUKS prompt** and in the
desktop. Verify:

```sh
uname -r                                  # e.g. 7.1.6-arch1-1.1 (patched pkgrel)
journalctl -k -b | grep -Ei 'applespi|pxa2xx|disabling DMA'
# expect: "pxa2xx_spi_pci 0000:00:15.4: MacBookPro12,1 detected: disabling DMA..."
# expect: applespi bound to spi-APP000D:00, "Apple SPI Keyboard"/"Apple SPI Touchpad"
lsinitcpio /boot/EFI/Linux/omarchy_linux.efi 2>/dev/null | grep -E 'acpi_call|apple-keyboard-spi' \
  || sudo lsinitcpio $(ls /boot/initramfs-*.img | head -1) | grep -E 'acpi_call|modprobe.d'
```

### 2.7 actkbd (F5/F6 backlight stepping)

```sh
sudo install -Dm644 ~/arch-setup/config/actkbd/actkbd.conf /etc/actkbd.conf
sudo install -Dm644 ~/arch-setup/config/actkbd/actkbd.service /etc/systemd/system/
sudo install -Dm755 ~/arch-setup/config/actkbd/kbd-backlight-step /usr/local/bin/
sudo systemctl enable --now actkbd.service
```

The unit's device path (`/dev/input/by-path/pci-0000:00:15.4-cs-00-event-kbd`)
is a stable udev by-path link, identical on the new install.

### 2.8 Suspend

The 0002 S3-resume patch rides along in the stashed kernel, so deep sleep
keeps working as it does today (keyboard/trackpad survive wake). Verify once:
suspend, wake, type. If a future kernel bump regresses it, the stopgap is a
cmdline drop-in: `/etc/default/limine` is where omarchy's kernel cmdline lives
(`@@CMDLINE@@` in the limine template), so
`mem_sleep_default=s2idle` goes there - mirroring how the T2 fix ships its
cmdline via `/etc/limine-entry-tool.d/`.

**Phase 2 exit criteria:** internal keyboard + trackpad work at the LUKS
prompt, in the desktop, after suspend/wake; F5/F6 step the keyboard
backlight; `pacman -Q linux` shows the patched pkgrel.

## Phase 3 - tmux stack

The goal: `prefix f` sessionizer, `t` todos, `W` treehouse picker working
with the repo's tmux.conf.

1. **Config placement.** Omarchy's tmux config lives at
   `~/.config/tmux/tmux.conf`; tmux looks for a user config at either
   `~/.tmux.conf` or `~/.config/tmux/tmux.conf`. Omarchy leaves no
   `~/.tmux.conf` behind - keep it that way and take over the XDG location,
   so there is exactly one user config no matter which path tmux resolves
   first:

```sh
rm -f ~/.tmux.conf
ln -sfn ~/arch-setup/config/tmux/tmux.conf ~/.config/tmux/tmux.conf
```

   Omarchy will not overwrite it: theming is runtime-only (see primer), and
   updates never touch `~/.config`. Once home-manager is switched in
   (Phase 4.3), its `home.file.".config/tmux/tmux.conf"` entry - moved from
   the current `.tmux.conf` entry at migration time - owns this link and the
   manual `ln -sfn` can be dropped. The `omarchy reinstall configs` caveat
   from Phase 4.3 applies here too.

2. **Scripts on PATH.** home-manager's `home.sessionPath` keeps doing this
   exactly as today (tmux-scripts dir stays in `home.nix`). Before the first
   HM switch, a temporary export works:

```sh
echo 'export PATH="$HOME/arch-setup/config/tmux/tmux-scripts:$PATH"' >> ~/.bashrc
```

3. **treehouse.** Stays a nix flake package - no AUR step. `treehouse` lands
   on PATH with the first `./rebuild.sh` after Phase 4.3. The worktree pool
   under `~/.treehouse/` comes back from the Phase 0 backup if you want the
   leases preserved; otherwise it rebuilds on demand.

4. **fzf/jq** are in omarchy's base package set - the sessionizer's picker
   works out of the box. Per-project `.tmux-sessionizer-config` /
   `setup-local-env.sh` files come back with the projects (they are
   gitignored globally - the ignores live in the repos' git config, which
   restores with each clone; verify one).

Verify: `tmux source-file ~/.config/tmux/tmux.conf`, then `prefix f` opens
the sessionizer and window names stay fixed (`automatic-rename off` survives
the port since it is all in our conf). `prefix W` (treehouse pool) becomes
testable after Phase 4.3's first `./rebuild.sh` puts `treehouse` on PATH.

## Phase 4 - Terminal, shell, nix, and apps

### 4.1 Terminal: ghostty (image.nvim decides), foot stays the fallback

The nvim image requirement decides the terminal: image.nvim renders inline
images via the **kitty graphics protocol**, which foot does not implement.
Ghostty does (it's a headline feature on ghostty.org), and it's a first-class
omarchy terminal, so:

```sh
omarchy-install-terminal ghostty
```

This installs ghostty, makes it the default terminal for Super+Return and
`xdg-terminal-exec`, and seeds `~/.config/ghostty/` from omarchy's template
- which the theme system then drives via `ghostty.conf.tpl`, so no config
porting at all. Nothing from our kitty.conf is worth carrying: its only
non-default lines were `shell /usr/bin/zsh` (moot now) and kitty-internal
copy/paste maps. Foot remains installed as the fallback terminal.

image.nvim's `backend = "kitty"` drives any terminal implementing the
protocol, ghostty included, and the tmux passthrough line is already in our
tmux.conf (`set -gq allow-passthrough on`, Phase 3). Verify after nvim is
ported (4.4): open an image inside tmux-inside-ghostty and confirm it
renders. If image.nvim's terminal auto-detection balks at
`TERM=xterm-ghostty`, pin the backend explicitly in its setup - the protocol
itself is identical.

### 4.2 Shell: omarchy's bash + ported personal fragments

The interactive shell is omarchy's default - bash + starship + the omarchy
rc aliases/functions. The zsh/oh-my-zsh/Powerlevel10k stack is retired, and
so is the repo's Tokyo Night TTY1 bash prompt: login is graphical (SDDM →
Hyprland from the first boot), so the TTY prompt ceremony buys nothing.
What actually matters from `config/zsh/personal.zsh` is four lines, which
port into the HM-managed `~/.bashrc` (next section):

```bash
export EDITOR='nvim'
alias vim="nvim"
alias opencode='if [[ -f ~/arch-setup/.env ]]; then set -a; source ~/arch-setup/.env; set +a; fi; /usr/bin/opencode'
bind -x '"\C-f": tmux-sessionizer'   # readline form of the old zsh bindkey -s ^f
```

(The tmux-scripts PATH export from personal.zsh is already covered by
`home.sessionPath`.) At migration time, rewrite `config/bash/bashrc` to
contain exactly these fragments behind the omarchy composition shown below -
the Tokyo Night prompt blocks go away. `config/zsh/` and `config/kitty/`
become dead weight; delete or keep as historical.

### 4.3 Nix + home-manager: kept, with an interference boundary

Nix and home-manager stay for user-config management. They coexist with
omarchy without interference because the surfaces are disjoint: omarchy is
pacman packages + `/etc` drop-ins + `/usr/share/omarchy` + the files it
seeds into `~/.config`; home-manager writes only inside `$HOME`. The rules
that keep it that way:

- **Install nix exactly as on archeus**: run `bootstrap.sh` after the
  omarchy install. Omarchy is stock Arch systemd, so the socket-activated
  daemon + systemd-sysusers flow is unchanged (the bootstrap.sh comments
  remain the source of truth). Ignore its package-install steps - only the
  nix daemon setup matters. `nix` is not in omarchy's package set; nothing
  conflicts with it.
- **flake.nix unchanged**: nixpkgs-unstable + home-manager master + the
  treehouse input (still consumed as `treehousePackage` in `home.packages`).
- **home.nix slimmed to what omarchy does not own**. Target shape:
  - keep: `programs.git` (incl. the sessionizer ignores), `programs.ssh`,
    `programs.direnv`, `home.packages` (pi-coding-agent, uv, btop,
    treehousePackage), `home.sessionPath` (tmux-scripts), and `home.file`
    entries for `.bashrc` (force), `.ssh/config` (force),
    `.config/tmux/tmux.conf` (the entry moved from `.tmux.conf`),
    `.config/nvim`, `.config/chrome-flags.conf` (google-chrome stays, AUR),
    the opencode JSONs, and `.pi/agent/models.json`.
  - drop: `programs.zsh` entirely; the zsh/p10k/kitty/waybar/mako/wofi/
    hypr* file links (retired or omarchy/theme-owned now);
    the `.bash_profile` link (omarchy's `/etc/skel` handles login shells;
    HM owning only `.bashrc` is enough since login is graphical); the
    taildrop-receive user service IF omarchy's tailscale commands
    (`omarchy-install-service-tailscale` + `omarchy-tailscale-receive`)
    cover the workflow - keep the service otherwise, it works unchanged.
  - `~/.bashrc` becomes a composition: omarchy's env bootstrap and rc
    first (so all omarchy shell functions/aliases survive HM owning the
    file), then the personal fragments from 4.2. Omarchy's own default
    .bashrc has exactly this shape - HM just owns the file:

    ```bash
    # top of the repo's config/bash/bashrc (rewritten at migration time)
    [[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap

    # If not running interactively, don't do anything else
    [[ $- != *i* ]] && return

    # All the default Omarchy aliases and functions
    source "$OMARCHY_PATH/default/bash/rc"

    # ...personal fragments (EDITOR, aliases, bind -x ^f)...
    ```

    Package upgrades only ever rewrite `/etc/skel/.bashrc` (never an
    existing user's copy), so the composition is stable.
- **Two update flows, zero overlap**: `omarchy update` owns the pacman
  world; `./rebuild.sh` (pruned - the waybar bounce block goes away, the
  `home-manager switch` line stays) plus periodic `nix flake update` own
  the nix world. The ALPM update guard never sees nix commands. The AGENTS.md
  rule carries over verbatim: the user always runs `./rebuild.sh` themselves.
- **`omarchy reinstall configs` is the one real hazard** (also flagged in
  Phase 3): it replays `/etc/skel/.` over `$HOME` with `cp -af`, and `cp`
  writes *through* symlinks - so it would overwrite the repo files behind
  HM's links (e.g. `config/bash/bashrc`) instead of replacing the links.
  If it ever runs: `git -C ~/arch-setup checkout -- config/` to restore,
  then `./rebuild.sh` to re-assert. Better: don't run it casually - it also
  factory-resets every other omarchy-seeded config.
- **Disk**: the nix store lives on the snapshotted root subvolume, so
  snapper snapshots grow with it and omarchy update's 10 GiB free-space
  gate guards the full-disk case. `nix-collect-garbage -d` occasionally,
  same as today.

First switch: `./rebuild.sh` (after the Phase 3 manual symlinks are removed
where HM takes over, and after `rm -f ~/.tmux.conf` if HM ever linked it
there). HM's `force = true` entries clobber the omarchy-seeded copies -
that's intended.

### 4.4 Apps and tools

```sh
omarchy-pkg-add google-chrome     # AUR (was AUR here too)
omarchy-pkg-add handy-bin         # speech-to-text; wtype is in omarchy's base set
omarchy-install-service-tailscale # tailscale service + omarchy taildrop commands
omarchy-pkg-add nodejs npm        # for pi's npm:opencode-pi@1.1.4 bridge
```

- **opencode** is already an omarchy base package (pacman pin, same as now).
  `config/opencode/` configs are owned by HM (4.3).
- **pi** stays a nix package (4.3). Restore `~/.pi/agent/auth.json` from
  backup (never repo-tracked); the `config/pi/models.json` HM link stays.
  `settings.json` stays untracked.
- **nvim**: keep the kickstart fork - the HM `.config/nvim` link as today
  (remove the omarchy-nvim-seeded `~/.config/nvim` first if the seed put
  files there). Then run the 4.1 image.nvim verification.
- **lazygit, btop, fzf, tesseract, starship** etc. are all in omarchy's
  base set - do not reinstall them.
- **AUR helper**: omarchy's flows use yay (installed by default). paru can
  be installed alongside without harm, but nothing needs it - the scripts
  that referenced it retire with `build/system-packages.sh`.

## Phase 5 - Desktop customizations

Omarchy's Hyprland config splits into `~/.config/hypr/*.lua` overrides; port
from our single `config/hypr/hyprland.lua` (Hyprland 0.56 Lua DSL both sides,
so most lines move verbatim):

| Our config section | Omarchy destination |
| --- | --- |
| MONITORS (scale 1.25) | `~/.config/hypr/monitors.lua` |
| INPUT (touchpad scroll_factor 0.5, pointer accel) | `~/.config/hypr/input.lua` |
| LOOK AND FEEL (gaps, borders, campfire gradient) | `~/.config/hypr/looknfeel.lua` (or keep omarchy defaults + theme first) |
| MY PROGRAMS + AUTOSTART (handy daemon, power-profile init) | `~/.config/hypr/autostart.lua` via `o.launch_on_start(...)`; note omarchy already runs `omarchy-powerprofiles-init` |
| KEYBINDINGS (Super+C/V copy-paste, Super+Q/T, audio/capture/nightlight/launch-or-focus/window toggles) | `~/.config/hypr/bindings.lua` - but FIRST check omarchy's built-ins: it already has capture (Super+Shift+S family), nightlight toggle, launch-or-focus, and the window toggles (gaps/transparency/pop/fullscreen) as native commands; only bind what's missing (Mac-style Super+C/V via wtype, speech-to-text Alt+Space, wifi QR if wanted) |

Theme: `omarchy theme set "Tokyo Night"` - bar, shell, ghostty/foot
templates, tmux runtime colors, browser, obsidian all follow. Our hardcoded
Tokyo Night palette in tmux.conf stays as-is (it already matches).

Wallpaper: drop the pokemon night bg into
`~/.config/omarchy/backgrounds/tokyo-night/`.

**Do not port:** waybar/mako/wofi/hyprlock/hypridle configs (Quickshell owns
all of it - the lock/idle pipeline is configured via
`~/.config/omarchy/shell.json`), and the Tier-1/Tier-2 helper scripts from
`omarchy-features-review.md` (omarchy ships them; the review doc becomes a
historical record).

## Phase 6 - Remaining system config and the repo's new role

Nothing else from `build/system-config.sh` needs porting by hand - omarchy
ships the NetworkManager powersave, sysctl watchers, oomd tuning, and
power-profile init. The one open item: **AC/battery profile switching on
plug/unplug**. Omarchy's shell watches UPower (`UPower.onBattery`) for its
own UI; if the profile does not visibly switch on plug events during testing,
port `config/udev/rules.d/90-power-profile.rules` to `/etc/udev/rules.d/`
unchanged.

Write the Phase 2/3 deploy steps into a new `build/omarchy-setup.sh`
(modprobe.d + mkinitcpio drop-in + udev rule + actkbd, with the
cmp-and-rebuild-initramfs logic from `system-config.sh` adapted to
`mkinitcpio -P` for the UKI). From then on the repo has two apply surfaces,
matching the two managers:

- `build/omarchy-setup.sh` - system-level (root `/etc` files + kernel-fix
  deploy). The successor to `system-config.sh` + `system-packages.sh`.
- `./rebuild.sh` - user-level (home-manager switch), pruned of the waybar
  bounce. The AGENTS.md rule "the user always runs ./rebuild.sh themselves"
  carries over verbatim.
- `system-packages.nix` + `build/system-packages.sh` retire (omarchy +
  `omarchy-pkg-add` own the system package set; reconcile with
  `pacman -Qqen`/`-Qqem` if an inventory is wanted). `bootstrap.sh` narrows
  to the nix-daemon installer (Phase 4.3).
- Kernel bumps: same loop as today - `~/build/linux/rebuild-patch.sh`, then
  `sudo pacman -U` the new packages. `omarchy update` leaves them alone via
  IgnorePkg; `omarchy update` DOES still update everything else, run AUR
  updates via yay, snapshot first, and run migrations.
- Update AGENTS.md: paru→yay, GRUB→Limine/snapper, home-manager now
  *composes* with omarchy (owns `~/.bashrc`, tmux, nvim, ssh, git, pi,
  opencode; omarchy owns the rest of `~/.config` and all of `/etc`), and
  point the keyboard docs at the omarchy drop-in variant of the fix.

## Risks and rollback

- **Disk wipe is total.** The external backup is the only rollback until
  Phase 2 passes. Escape hatch if omarchy disappoints: reinstall plain Arch
  from this repo's docs (they remain the source of truth for that path) and
  restore the home backup - the fix stack is fully documented to rebuild.
- **Busybox modprobe + install reroute** (Phase 2.3 risk): mitigation is the
  initcpio-hook fallback, which is proven to work under busybox initramfs.
- **Stashed kernel older than omarchy's stock**: harmless for the keyboard
  (PIO quirk is version-independent); just rebuild at the next convenient
  bump. If the stash is somehow unbootable (it is the same binary that runs
  now, so unlikely), boot works via Limine's fallback entry and the stock
  kernel + USB keyboard gets you back in.
- **omarchy reinstall configs is hazardous to HM symlinks** (Phase 4.3):
  `cp -af /etc/skel/.` writes *through* home-manager's symlinks into the
  repo files, and factory-resets every omarchy-seeded config besides. After
  any run: `git -C ~/arch-setup checkout -- config/` then `./rebuild.sh`.
  Channel switches (`omarchy channel set`) are safe - they only touch
  pacman repo config and packages.
- **Update guard friction**: any personal habit of raw `pacman -Syu` must
  become `omarchy update` (or the explicit bypass env var). Local
  `pacman -U` for kernel rebuilds stays unaffected.
- **Two package managers, two update rhythms**: forgetting the nix side
  leaves user packages stale (harmless); forgetting `omarchy update` blocks
  system updates. Neither flow can corrupt the other - their file sets are
  disjoint.
- **Known macOS-hardware gaps** (manual/44-mac-support.md): none apply to
  12,1 beyond what we already handle (it predates T1/T2).

## Condensed checklist

- [ ] Phase 0: backup home + secrets + package lists + /etc fix files
      (manifests + `/etc` tarball + kernel stash are in `~/backup`; run
      `build/home-backup.sh <mounted-drive>` for the full home copy)
- [x] Phase 0: commit `apple-keyboard-spi.conf` + `blacklist-lpss-dma.conf` to repo
- [x] Phase 0: prebuild patched kernel, stash `.pkg.tar.zst` + build dir
- [ ] Phase 0: USB keyboard/mouse + omarchy ISO; optional ISO smoke boot
- [ ] Phase 1: full-disk encrypted install (USB input throughout)
- [ ] Phase 2: acpi_call-dkms + actkbd installed
- [ ] Phase 2: 4x modprobe.d deployed; mkinitcpio MODULES drop-in; udev rule
- [ ] Phase 2: `pacman -U` patched kernel; IgnorePkg + pre-refresh-pacman hook
- [ ] Phase 2: `mkinitcpio -P`; reboot; keyboard at LUKS + desktop + after suspend
- [ ] Phase 2: actkbd F5/F6 stepping; backlight floors at boot
- [ ] Phase 3: tmux.conf symlink (HM takes over in 4.3) + PATH; sessionizer works
- [ ] Phase 4: ghostty via omarchy-install-terminal; image.nvim renders in tmux+ghostty
- [ ] Phase 4: personal.zsh fragments ported into composed HM `~/.bashrc`
- [ ] Phase 4: bootstrap.sh nix daemon setup; home.nix slimmed; first `./rebuild.sh`
- [ ] Phase 4: apps (chrome, handy, tailscale, node/npm, opencode, pi auth, nvim)
- [ ] Phase 5: input.lua/monitors.lua/bindings.lua ports; Tokyo Night theme; wallpaper
- [ ] Phase 6: `build/omarchy-setup.sh` written; rebuild.sh pruned; AGENTS.md + docs updated
