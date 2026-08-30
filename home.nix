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
  # (the pi coding agent binary is mise-managed, outside both layers; its
  # config is linked below.)
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
    # Phase 4.4: nvim is the vendored kickstart fork (config/nvim), linked as a
    # whole directory so live edits apply instantly. force clobbers the
    # omarchy-nvim-seeded ~/.config/nvim - move it aside before the first
    # switch (mv ~/.config/nvim{,.omarchy-seed.bak}). Inside the tree,
    # lua/config/omarchy-theme.lua keeps `omarchy theme set` working.
    ".config/nvim" = {
      source = link "nvim";
      force = true;
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
    # ble.sh line editor config (autosuggestions + syntax highlighting).
    # init.sh is ble.sh's stock config path (~/.config/blesh/init.sh), loaded by
    # ble.sh itself at attach; wired from the tail of config/bash/bashrc-personal.
    ".config/blesh/init.sh".source = link "blesh/init.sh";
    # Lid sleep override: toggle script + the user unit it starts/stops
    # (systemd-inhibit handle-lid-switch). Needs the logind drop-in from
    # build/omarchy-setup.sh to have any effect. The unit is declarative and
    # started on demand by ~/.local/bin/lid-sleep (never enabled, so a reboot
    # always returns to closing-the-lid-suspends).
    ".local/bin/lid-sleep".source = link "bin/lid-sleep";
    # OpenCode Go usage for the omarchy.agents bar panel: the collector writes
    # ~/.local/state/omarchy/agents/usage/opencode.json (the panel discovers
    # it on its own), refreshed by the declarative user timer. No packaged
    # omarchy-agent-usage-* collector covers opencode, and the update script
    # only scans the read-only package bin, so this runs standalone.
    ".local/bin/omarchy-agent-usage-opencode".source = link "bin/omarchy-agent-usage-opencode";
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
    # pi coding agent: Zen's free-model gateway 429s every request that does
    # not carry the official-client header fingerprint (FreeUsageLimitError),
    # so the provider override injects them. Only this file is linked -
    # auth.json, models-store.json, settings.json and sessions/ stay
    # unmanaged runtime state next to it.
    ".pi/agent/models.json" = {
      source = link "pi/models.json";
      force = true;
    };
  };

  # User systemd units, generated and enabled declaratively by home-manager
  # (no manual `systemctl --user enable` needed on switch). These replace the
  # earlier raw unit-file links in home.file.
  systemd.user.enable = true;
  systemd.user.services.lid-awake = {
    Unit.Description = "Lid-close suspend inhibitor (agents keep working with lid closed)";
    Service = {
      Type = "simple";
      ExecStart = "/usr/bin/systemd-inhibit --what=handle-lid-switch sleep infinity";
    };
  };
  systemd.user.services.opencode-usage = {
    Unit.Description = "Refresh OpenCode Go usage record for the omarchy.agents panel";
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/omarchy-agent-usage-opencode";
    };
  };
  systemd.user.timers.opencode-usage = {
    Unit.Description = "Refresh OpenCode Go usage every 15 minutes for the omarchy.agents panel";
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
