{
  description = "AirPlay as Flake. AirPlay receiver appliance managed with Nix";

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
      lib = nixpkgs.lib;

      selfVersion = self.shortRev or self.dirtyShortRev or "dev";
      # Build number = number of commits in the repo: human-sized, monotonic, easy to bump to or
      # roll back to. Nix only knows it for a clean checkout; a dirty tree deploys as "dev".
      selfBuild = if self ? revCount then toString self.revCount else "dev";

      # One appliance per file in devices/<id>.json: hostname, HAT overlay, radios, LAN, the
      # shairport-sync defaults. The same JSON reaches the device as /etc/ampberry/device.json,
      # so the Ruby tools and the flake read one definition. devices/<Id>.md is the install record.
      deviceIds = [
        "ampberry"
        "hifiberry"
      ];
      devices = lib.genAttrs deviceIds (id: builtins.fromJSON (builtins.readFile (./devices + "/${id}.json")));

      # `version` names the tools/UI derivations; passing the same one keeps them byte-identical
      # (no rebuild on the device when the flake is consumed as an input, see lib.withShairport).
      pkgsFor =
        system: version:
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

      targetPkgs = pkgsFor target selfVersion;

      # The appliance configuration for one device; `shairport` = { src, version } swaps in
      # another shairport-sync release (the on-device "Update" button).
      mkSystem =
        {
          device,
          version ? selfVersion,
          build ? selfBuild,
          shairport ? null,
        }:
        let
          p = pkgsFor target version;
          shairportPkg =
            if shairport == null then
              p.shairport-sync-airplay2
            else
              p.pkgs.callPackage ./nix/packages/shairport-sync.nix {
                inherit (p) unstable;
                shairportSrc = shairport.src;
                shairportVersion = shairport.version;
              };
        in
        system-manager.lib.makeSystemConfig {
          modules = [
            ./nix/system/ampberry.nix
            ./nix/system/firewall.nix
            ./nix/system/branding.nix
          ];
          specialArgs = {
            ampberry = {
              shairport-sync-airplay2 = shairportPkg;
              inherit (p)
                nqptp
                ampberry-tools
                ampberry-ui
                ;
              inherit version build device;
              network = device.network;
              flakeSource = self;
              # the system-manager CLI for the device, built with the same nixpkgs as the closure
              systemManager = system-manager.packages.${target}.default;
            };
          };
        };
    in
    {
      # Packages for the device (aarch64-linux) and, for local development/validation, the dev
      # systems too (the Ruby tools and the Rails UI build anywhere; shairport only on Linux).
      packages = lib.genAttrs (lib.unique (devSystems ++ [ target ])) (
        system:
        let
          p = pkgsFor system selfVersion;
        in
        {
          inherit (p) ampberry-tools ampberry-ui;
          default = p.ampberry-tools;
        }
        // lib.optionalAttrs (lib.hasSuffix "-linux" system) {
          inherit (p) shairport-sync-airplay2 nqptp;
        }
      );

      # One system per device: applied with
      #   system-manager switch --flake .#<id> --target-host pi@<host> --sudo
      # or, on the device itself (first boot / Clean reboot),
      #   system-manager switch --store-path $(cat /etc/ampberry/system-path)
      systemConfigs = lib.mapAttrs (_: device: mkSystem { inherit device; }) devices;

      # The same appliance with a newer shairport-sync release on top. The device's "Update"
      # button writes a tiny flake (/var/lib/ampberry/shairport-update) that takes this flake as
      # an input and calls this with the release tarball; build/flakeVersion are passed through
      # because a flake consumed as a `path:` input has no git metadata of its own.
      lib.withShairport =
        {
          src,
          version,
          device ? "ampberry",
          build ? selfBuild,
          flakeVersion ? selfVersion,
        }:
        {
          systemConfigs.${device} = mkSystem {
            inherit build;
            device = devices.${device};
            version = flakeVersion;
            shairport = { inherit src version; };
          };
        };

      inherit devices;

      checks.${target} = {
        # The Ruby test suite runs as part of the package build (doCheck); this exposes it.
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
              shellcheck
              ruby_3_4
              bundix
              nixfmt-rfc-style
              system-manager.packages.${system}.default
            ];
            shellHook = ''
              echo "airplay-os dev shell — ruby -Ilib -Itest … · bundix · nix build .#ampberry-ui"
            '';
          };
        }
      );

      formatter = forDev (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
