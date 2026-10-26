# The agent as an Erlang shipment. Hex dependencies are fetched from the
# checksums in agent/manifest.toml, so `gleam update` needs no hash changes here.
{
  lib,
  stdenv,
  fetchurl,
  gleam,
  beamPackages,
  makeWrapper,
}:
let
  inherit (beamPackages) erlang;
  manifest = lib.importTOML ../agent/manifest.toml;
  hexPackages = builtins.filter (p: p.source == "hex") manifest.packages;
  tarball =
    p:
    fetchurl {
      url = "https://repo.hex.pm/tarballs/${p.name}-${p.version}.tar";
      sha256 = lib.toLower p.outer_checksum;
    };
  # Tells gleam that build/packages is up to date, so it doesn't download.
  packagesToml = builtins.toFile "packages.toml" (
    "[packages]\n" + lib.concatMapStrings (p: "${p.name} = \"${p.version}\"\n") hexPackages
  );
in
stdenv.mkDerivation {
  pname = "digitalwellbeing-agent";
  version = (lib.importTOML ../agent/gleam.toml).version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../agent/gleam.toml
      ../agent/manifest.toml
      ../agent/src
      ../shared/gleam.toml
      ../shared/src
    ];
  };

  nativeBuildInputs = [
    gleam
    erlang
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    cd agent
    # gleam re-resolves all versions over the network for path dependencies
    # it hasn't fingerprinted yet, so compile `shared` in as part of the agent
    cp ../shared/src/*.gleam src/
    sed -i '/^shared = /d' gleam.toml manifest.toml
    sed -i '/name = "shared"/d' manifest.toml
    mkdir -p build/packages
    ${lib.concatMapStrings (p: ''
      mkdir build/packages/${p.name}
      tar -xOf ${tarball p} contents.tar.gz | tar -xz -C build/packages/${p.name}
    '') hexPackages}
    # writable, gleam rewrites it
    install -m 644 ${packagesToml} build/packages/packages.toml
    gleam export erlang-shipment
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
    cp -r build/erlang-shipment $out/lib/digitalwellbeing-agent
    makeWrapper $out/lib/digitalwellbeing-agent/entrypoint.sh $out/bin/digitalwellbeing-agent \
      --add-flags run \
      --prefix PATH : ${lib.makeBinPath [ erlang ]}
    runHook postInstall
  '';

  meta = {
    description = "Forwards ActivityWatch usage data to a digital wellbeing server";
    mainProgram = "digitalwellbeing-agent";
    platforms = lib.platforms.unix;
  };
}
