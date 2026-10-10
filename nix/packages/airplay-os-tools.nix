# Ruby side of AirPlay OS: the `airplay-os` CLI (provisioning, settings, Wi-Fi onboarding, firewall,
# the root-side control handler) and the metadata daemon. Ruby stdlib only; tests run at build time.
{
  lib,
  stdenvNoCC,
  ruby_3_4,
  makeWrapper,
  src,
  version,
}:

let
  ruby = ruby_3_4;
in
stdenvNoCC.mkDerivation {
  pname = "airplay-os-tools";
  inherit version;

  src = lib.cleanSourceWith {
    src = src;
    filter =
      path: _type:
      let
        rel = lib.removePrefix (toString src + "/") (toString path);
        top = builtins.head (lib.splitString "/" rel);
      in
      builtins.elem top [
        "lib"
        "bin"
        "test"
        "etc"
        "docs" # the test suite checks every device definition (docs/devices)
      ];
  };

  nativeBuildInputs = [
    ruby
    makeWrapper
  ];

  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${ruby}/bin/ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -d $out/lib/airplay_os $out/libexec/airplay-os $out/bin $out/share/airplay-os
    cp -r lib/. $out/lib/airplay_os/
    install -m 0755 bin/airplay-os $out/libexec/airplay-os/airplay-os
    install -m 0644 etc/airplay-os/actions.json $out/share/airplay-os/actions.json
    # Host tools (systemctl, nmcli, ufw, apt-get ...) come from Raspberry Pi OS via the caller's
    # PATH on purpose; only the Ruby load path is wired here.
    makeWrapper ${ruby}/bin/ruby $out/bin/airplay-os \
      --add-flags "-I$out/lib/airplay_os" \
      --add-flags "$out/libexec/airplay-os/airplay-os"
    runHook postInstall
  '';

  meta = {
    description = "AirPlay OS appliance tools (provisioning, settings, Wi-Fi onboarding, firewall, control API, metadata daemon)";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "airplay-os";
  };
}
