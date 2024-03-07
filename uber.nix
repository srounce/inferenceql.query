{ stdenv,
  git,
  clojure,
  makeWrapper,
  runCommand,
  cacert,
}: let
  build-clojure = runCommand "build-clojure" {
    __noChroot = true;
    src = ./deps.edn;
    nativeBuildInputs = [ clojure git makeWrapper ];
  } ''
    mkdir -p $out

    makeWrapper ${clojure}/bin/clojure ./build-clojure \
      --set GIT_SSL_CAINFO ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --set CLJ_CONFIG $out/.clojure \
      --set GITLIBS $out/.gitlibs \
      --set JAVA_TOOL_OPTIONS "-Duser.home=$out"

    cp $src ./deps.edn

    ./build-clojure -A:build -P
    ./build-clojure -P

    mkdir -p $out/bin
    cp ./build-clojure $out/bin/build-clojure
  '';
in stdenv.mkDerivation {
  name = "inferenceql.query-uberjar";
  version = "unstable";
  src = ./.;

  nativeBuildInputs = [ build-clojure git ];
  buildPhase = ''
    cp -R $src .
    build-clojure -T:build uber
  '';
  installPhase = ''
    cp -R target/*.jar $out
  '';
}
