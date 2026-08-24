{
  description = "ajisrael's Omarchy box (archeus) - MacBookPro12,1";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Worktree pool manager used by tmux-sessionizer-treehouse. Not packaged
    # in nixpkgs; ships its own flake output (same consumption pattern as
    # the macOS dotfiles repo).
    treehouse = {
      url = "github:kunchenguid/treehouse";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, treehouse, ... }: {
    packages.x86_64-linux.home-manager =
      home-manager.packages.x86_64-linux.home-manager;

    homeConfigurations.archeus = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      # Upstream's go test suite fails in the Nix sandbox at 2.2.1: its
      # no-mistakes CI-gate fixtures assert against their own repo's PR
      # attestation tooling and are broken regardless of environment. The
      # failures are in gate-string unit tests, not the worktree core - skip
      # the check phase (same package otherwise as the macOS side consumes).
      extraSpecialArgs.treehousePackage =
        treehouse.packages.x86_64-linux.default.overrideAttrs { doCheck = false; };
      modules = [ ./home.nix ];
    };
  };
}
