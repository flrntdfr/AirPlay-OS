{
  description = "Ampberry — AirPlay 2 speaker appliance on Raspberry Pi OS, managed with Nix (system-manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only for the two audio packages: 5.5.2 is the iOS/macOS 27 compatibility release.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    system-manager = {
      url = "github:numtide/system-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      system-manager,
      ...
    }:
    let
      target = "aarch64-linux";
      devSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forDev = nixpkgs.lib.genAttrs devSystems;

      version = self.shortRev or self.dirtyShortRev or "dev";
      # Build number = number of commits in the repo: human-sized, monotonic, easy to bump to or
      # roll back to. Nix only knows it for a clean checkout; a dirty tree deploys as "dev".
      build = if self ? revCount then toString self.revCount else "dev";

      # The network the appliance lives on. Not a secret, so it belongs here, not in secrets.env.
      network = {
        lanCidrs = [ "192.168.178.0/24" ];
        wifiInterface = "wlan0";
        hotspotCidr = "10.42.0.0/24"; # NetworkManager shared mode default
      };

      pkgsFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          unstable = nixpkgs-unstable.legacyPackages.${system};
        in
        rec {
          inherit pkgs unstable;
          shairport-sync-airplay2 = pkgs.callPackage ./nix/packages/shairport-sync.nix { inherit unstable; };
          nqptp = unstable.nqptp;
          ampberry-tools = pkgs.callPackage ./nix/packages/ampberry-tools.nix {
            src = self;
            inherit version;
          };
          ampberry-ui = pkgs.callPackage ./nix/packages/ampberry-ui.nix {
            src = self;
            inherit version;
          };
        };

      targetPkgs = pkgsFor target;
    in
    {
      # Packages for the device (aarch64-linux) and, for local development/validation, the dev
      # systems too (the Ruby tools and the Rails UI build anywhere; shairport only on Linux).
      packages = nixpkgs.lib.genAttrs (nixpkgs.lib.unique (devSystems ++ [ target ])) (
        system:
        let
          p = pkgsFor system;
        in
        {
          inherit (p) ampberry-tools ampberry-ui;
          default = p.ampberry-tools;
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-linux" system) {
          inherit (p) shairport-sync-airplay2 nqptp;
        }
      );

      # The appliance: applied with
      #   system-manager switch --flake .#ampberry --target-host pi@ampberry.local --sudo
      # or, on the device itself (first boot / Clean reboot),
      #   system-manager switch --store-path $(cat /etc/ampberry/system-path)
      systemConfigs.ampberry = system-manager.lib.makeSystemConfig {
        modules = [
          ./nix/system/ampberry.nix
          ./nix/system/firewall.nix
          ./nix/system/branding.nix
        ];
        specialArgs = {
          ampberry = {
            inherit (targetPkgs)
              shairport-sync-airplay2
              nqptp
              ampberry-tools
              ampberry-ui
              ;
            inherit version build network;
            flakeSource = self;
            # the system-manager CLI for the device, built with the same nixpkgs as the closure
            systemManager = system-manager.packages.${target}.default;
          };
        };
      };

      checks.${target} = {
        # The Perl test suite runs as part of the package build (doCheck); this exposes it.
        ampberry-tools = targetPkgs.ampberry-tools;
      };

      devShells = forDev (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              perl
              perlPackages.PerlCritic
              perltidy
              shellcheck
              ruby_3_4
              bundix
              nixfmt-rfc-style
              system-manager.packages.${system}.default
            ];
            shellHook = ''
              echo "ampberry dev shell — prove -l t/ · bundix · nix build .#ampberry-tools"
            '';
          };
        }
      );

      formatter = forDev (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
