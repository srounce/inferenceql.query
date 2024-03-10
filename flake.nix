{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    gpm-sppl = {
      type = "github";
      owner = "InferenceQL";
      repo = "inferenceql.gpm.sppl";
       ref = "ships/add-oci-image-package";
       rev = "0ed4147155dbda40a6e62cc6e28418464f96af4d";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    clj-nix = {
      url = "github:jlesquembre/clj-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      perSystem = { system, pkgs, ... }: let
        # in OCI context, whatever our host platform we want to build same arch but linux
        systemWithLinux = builtins.replaceStrings [ "darwin" ] [ "linux" ] system;

        crossPkgsLinux = inputs.nixpkgs.${systemWithLinux}.legacyPackages;
        #inputs.nixpkgs.legacyPackages.${systemWithLinux};

        gpm-sppl-image = inputs.gpm-sppl.packages.${system}.ociImg;

        uber = pkgs.callPackage ./uber.nix { };

        jdk = pkgs.openjdk17;
        clojure = pkgs.clojure.override { jdk = jdk; };

        ociImg = pkgs.dockerTools.buildLayeredImage {
          name = "inferenceql.query";
          tag = "latest";
          #architecture
          contents = [ uber ];
          config.Cmd = [ "inferenceql.query-uberjar" ];
        };

        ociImgWithSppl = pkgs.dockerTools.buildLayeredImage {
          name = "inferenceql.query";
          tag = "sppl";
          fromImage = gpm-sppl-image;
          contents = [ uber ];
          config.Cmd = [ "inferenceql.query-uberjar" ];
        };
      in {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.clj-nix.overlays.default
          ];
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            jdk
            clojure
            pkgs.deps-lock
          ];
        };

        packages = rec {
          inherit
            uber
            ociImg
            ociImgWithSppl;

          bin = uber;
          default = bin;
        };
      };
    };
}
