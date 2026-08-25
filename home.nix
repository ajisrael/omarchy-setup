# home-manager, user scope ONLY. Omarchy owns the desktop (Hyprland config,
# Quickshell shell/bar, themes, terminal theme integration) and all of /etc;
# this module owns the disjoint $HOME surface: ssh, direnv, the composed
# .bashrc + tmux conf links, opencode JSONs, and packages that are not in
# the Arch repos. Do not expand it into desktop-config generation.
{ pkgs, config, treehousePackage, ... }:
{
  home.username = "ajisrael";
  home.homeDirectory = "/home/ajisrael";
  home.stateVersion = "26.05";

  targets.genericLinux.enable = true;

  programs.home-manager.enable = true;

  # git config is deliberately NOT HM-managed: ~/.config/git/config is
  # hand-maintained on this box. Only the global excludes file is linked
  # (git reads ~/.config/git/ignore automatically, no config key needed).
  # It carries the per-project files used by tmux-sessionizer's
  # apply_session_config - machine/project local, never committed.

  # Key is named ~/.ssh/github (not a default identity file), so pin it to the
  # host - otherwise ssh only offers it when it is loaded into the agent.
  # enableDefaultConfig = false keeps home-manager from injecting its own
  # defaults; the "Host *" block below replicates them explicitly.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
      "github.com" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/github";
        IdentitiesOnly = true;
      };
    };
  };

  # treehouse comes from its own flake input (not nixpkgs) - consumed by
  # tmux-sessionizer-treehouse for the worktree pool (see config/tmux/).
  # btop is omarchy's; uv is not in the Arch repos.
  # (pi coding agent was dropped - not part of the workflow yet.)
  home.packages = [ pkgs.uv treehousePackage ];

  # direnv: environment switcher. The bash hook is NOT auto-injected (HM does
  # not own .bashrc via programs.bash here) - config/bash/bashrc-personal
  # sources `direnv hook bash` explicitly. nix-direnv can be enabled when wanted.
  programs.direnv = {
    enable = true;
    silent = true;
  };

  # tmux-sessionizer scripts on PATH so prefix-f / C-f resolve them.
  home.sessionPath = [ "/home/ajisrael/omarchy-setup/config/tmux/tmux-scripts" ];

  # Live-editable configs: plain files in the repo, symlinked into $HOME.
  # Editing the file in place is instantly picked up - no re-switch needed.
  home.file = let
    repo = "/home/ajisrael/omarchy-setup";
    link = path:
      config.lib.file.mkOutOfStoreSymlink "${repo}/config/${path}";
  in {
    ".ssh/config".force = true; # programs.ssh generates it
    ".bashrc" = {
      source = link "bash/bashrc";
      force = true; # composed over omarchy's env-bootstrap + rc; clobbers the seeded copy
    };
    ".config/tmux/tmux.conf" = {
      source = link "tmux/tmux.conf";
      force = true; # composed: omarchy default + personal section
    };
    ".config/git/ignore".source = link "git/ignore";
    # hyprland personal override stubs (Phase 5): input.lua (touchpad feel),
    # monitors.lua (eDP-1 scale 1.6). Plain files - omarchy owns everything
    # else under ~/.config/hypr/; these two replace its seeded stubs.
    ".config/hypr/input.lua" = {
      source = link "hypr/input.lua";
      force = true;
    };
    ".config/hypr/monitors.lua" = {
      source = link "hypr/monitors.lua";
      force = true;
    };
    # Personal keybindings (SUPER+CTRL+ALT+S lid-sleep toggle). Same pattern
    # as input.lua/monitors.lua: replaces omarchy's seeded stub (kept as
    # bindings.lua.pre-repo on first link).
    ".config/hypr/bindings.lua" = {
      source = link "hypr/bindings.lua";
      force = true;
    };
    # Lid sleep override: toggle script + the user unit it starts/stops
    # (systemd-inhibit handle-lid-switch). Needs the logind drop-in from
    # build/omarchy-setup.sh to have any effect.
    ".local/bin/lid-sleep".source = link "bin/lid-sleep";
    ".config/systemd/user/lid-awake.service".source = link "systemd/user/lid-awake.service";
    # opencode: force-clobbers the stock omarchy seeds with the real configs
    # (MCP servers, permissions, theme, vim plugin). Restart opencode after a
    # switch to pick up changes. node_modules/ next to these are runtime state.
    ".config/opencode/opencode.json" = {
      source = link "opencode/opencode.json";
      force = true;
    };
    ".config/opencode/tui.json" = {
      source = link "opencode/tui.json";
      force = true;
    };
  };
}
