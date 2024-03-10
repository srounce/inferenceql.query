{ mkCljBin,
  openjdk17_headless,
  xorg,
}:
mkCljBin {
  projectSrc = ./.;
  name = "inferenceql.query-uberjar";
  version = "unstable";
  main-ns = "inferenceql.query.main";
  jdk = openjdk17_headless;

  # start
  builder-preBuild = ''
    export DISPLAY=:99
    Xvfb :99 2> /dev/null &
  '';

  builder-extra-inputs = [ xorg.xorgserver ];
}
