# Ruby side of Ampberry: the `ampberry` CLI (provisioning, settings, Wi-Fi onboarding, firewall,
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
  pname = "ampberry-tools";
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
    install -d $out/lib/ampberry $out/libexec/ampberry $out/bin $out/share/ampberry
    cp -r lib/. $out/lib/ampberry/
    install -m 0755 bin/ampberry $out/libexec/ampberry/ampberry
    install -m 0644 etc/ampberry/defaults.json $out/share/ampberry/defaults.json
    install -m 0644 etc/ampberry/actions.json $out/share/ampberry/actions.json
    # Host tools (systemctl, nmcli, ufw, apt-get ...) come from Raspberry Pi OS via the caller's
    # PATH on purpose; only the Ruby load path is wired here.
    makeWrapper ${ruby}/bin/ruby $out/bin/ampberry \
      --add-flags "-I$out/lib/ampberry" \
      --add-flags "$out/libexec/ampberry/ampberry"
    runHook postInstall
  '';

  meta = {
    description = "Ampberry appliance tools (provisioning, settings, Wi-Fi onboarding, firewall, control API, metadata daemon)";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "ampberry";
  };
}
