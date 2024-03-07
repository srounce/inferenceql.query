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
        systemWithLinux = builtins.replaceStrings [ "darwin" ] [ "multiplatform" ] system;

        crossPkgsLinux = pkgs.pkgsCross.${systemWithLinux};

        jdk = pkgs.openjdk17;
        clojure = pkgs.clojure.override { jdk = jdk; };

        pname = "iql";

        # TODO: is the inherit necessary given override ?
        uber = pkgs.callPackage ./uber.nix {inherit clojure;};

        mkJavaBin = {pkgs}: pkgs.stdenv.mkDerivation rec {
          name = "inferenceql.query";
          inherit pname;
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ pkgs.openjdk17 ];
          installPhase = ''
            makeWrapper ${pkgs.openjdk17}/bin/java $out/bin/${pname} \
              --add-flags "-jar ${uber}"
          '';
        };

        nativeBin = mkJavaBin {inherit pkgs ;};

        ociBin = mkJavaBin {pkgs = crossPkgsLinux;} ;

        ociImg = pkgs.dockerTools.buildImage {
          name = "inferenceql.query";
          tag = "latest";
          # architecture
          copyToRoot = [ ociBin ];
          config = {
            Cmd = [ "${ociBin}/bin/${pname}" ];
          };
        };

        ociImgWithSppl = pkgs.dockerTools.buildImage {
          name = "inferenceql.query";
          fromImage = inputs.gpm-sppl.ociImg;
          copyToRoot = [ ociBin ];
          config = {
            Cmd = [ "${ociBin}/bin/${pname}" ];
          };
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [ jdk clojure ];
        };

        packages = rec {
          inherit uber ociImg nativeBin ociBin ociImgWithSppl;
          bin = nativeBin;
          default = bin;
        };
      };
    };
}
