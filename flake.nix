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
        jdk = pkgs.openjdk17;
        clojure = pkgs.clojure.override { jdk = jdk; };

        build-clojure = pkgs.runCommand "build-clojure" {
          __noChroot = true;
          src = ./deps.edn;
          nativeBuildInputs = [ clojure pkgs.git pkgs.makeWrapper ];
        } ''
          mkdir -p $out

          makeWrapper ${pkgs.clojure}/bin/clojure ./build-clojure \
            --set GIT_SSL_CAINFO ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
            --set CLJ_CONFIG $out/.clojure \
            --set GITLIBS $out/.gitlibs \
            --set JAVA_TOOL_OPTIONS "-Duser.home=$out"

          cp $src ./deps.edn

          ./build-clojure -A:build -P
          ./build-clojure -P

          mkdir -p $out/bin
          cp ./build-clojure $out/bin/build-clojure
        '';

        pname = "iql";

        uber = pkgs.stdenv.mkDerivation {
          name = "inferenceql.query uberjar";
          src = ./.;
          nativeBuildInputs = [ build-clojure pkgs.git ];
          buildPhase = ''
            cp -R $src .
            build-clojure -T:build uber
          '';
          installPhase = ''
            cp -R target/*.jar $out
          '';
        };

        mkJavaBin = platform: let
          crossPlatformPkgs = inputs.nixpkgs.legacyPackages.${platform};
        in pkgs.stdenv.mkDerivation rec {
          name = "inferenceql.query";
          inherit pname;
          src = ./.;
          nativeBuildInputs = [ crossPlatformPkgs.makeWrapper ];
          buildInputs = [ crossPlatformPkgs.openjdk17 ];
          installPhase = ''
            makeWrapper ${crossPlatformPkgs.openjdk17}/bin/java $out/bin/${pname} \
              --add-flags "-jar ${uber}"
          '';
        };

        nativeBin = mkJavaBin system;

        ociBin = mkJavaBin "x86_64-linux";

        ociImg = pkgs.dockerTools.buildImage {
          name = "inferenceql.query";
          tag = "latest";
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
