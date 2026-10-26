{
  description = "Unified screen time dashboard for ActivityWatch on all your devices";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    jailed-agents.url = "github:andersonjoseph/jailed-agents";
  };

  outputs =
    {
      self,
      nixpkgs,
      jailed-agents,
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

      myScripts = {

        "dev" = ''
          set -euo pipefail
          set -a
          source .env
          set +a


          trap 'kill $(jobs -p) 2>/dev/null' SIGINT

          # watchexec --workdir ./client --ignore build -e gleam "gleam run -m lustre/dev build" &

          watchexec --workdir ./server --ignore build -e gleam \
            --stop-signal SIGKILL --stop-timeout 2 -r \
            "fuser -k ''${PORT}/tcp 2>/dev/null; gleam run"
        '';

        # regenerates server/src/server/sql.gleam after changing the schema or a query
        "sql" = ''
          set -euo pipefail
          cd server
          mkdir -p build
          rm -f build/schema.sqlite3
          sqlite3 build/schema.sqlite3 < priv/schema.sql
          gleam run -m parrot -- --sqlite build/schema.sqlite3
        '';
      };

      scriptPackages = pkgs.lib.mapAttrsToList (name: body: pkgs.writeShellScriptBin name body) myScripts;

      androidSdk =
        (pkgs.androidenv.composeAndroidPackages {
          platformVersions = [ "35" ];
          buildToolsVersions = [ "35.0.0" ];
        }).androidsdk;

      buildInputs =
        with pkgs;
        [
          pnpm
          nodejs
          gleam
          beam28Packages.erlang
          beam28Packages.rebar3
          inotify-tools
          tailwindcss-language-server
          watchexec
          curl
          docker
          docker-compose
          psmisc
          git
          cacert
          uv
          rustywind
          sqlite
          sqlitebrowser
          sqlite.dev

          gcc
          pkg-config
          makeWrapper
          cargo
          rustc

          (jailed-agents.lib.${system}.makeJailedOpencode {
            extraPkgs = with pkgs; [
              gleam
              beam28Packages.erlang
              sqlite
              python3
              nodejs
            ];
          })
          (jailed-agents.lib.${system}.makeJailedClaudeCode {
            extraPkgs = with pkgs; [
              gleam
              beam28Packages.erlang
              sqlite
              python3
              nodejs
              jdk17
              gradle
              androidSdk
              android-tools
            ];
            extraReadwriteDirs = [ "~/.claude" ];
          })

          jdk17
          gradle
          androidSdk
          android-tools

        ]
        ++ scriptPackages;
    in
    {
      packages = forAllSystems (system: rec {
        agent = nixpkgs.legacyPackages.${system}.callPackage ./nix/agent.nix { };
        default = agent;
      });

      homeManagerModules.default = import ./nix/hm-module.nix self;

      devShells.${system}.default = pkgs.mkShell {
        packages = buildInputs;

        DOCKER_BUILDKIT = 1;

        LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath buildInputs}";
        ESQLITE_USE_SYSTEM_SQLITE = 1;

        ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
        JAVA_HOME = "${pkgs.jdk17}";
        # Gradle otherwise downloads its own aapt2, which doesn't run on NixOS
        GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdk}/libexec/android-sdk/build-tools/35.0.0/aapt2";

        shellHook = ''
          export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export NIX_SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
          export CURL_CA_BUNDLE="$SSL_CERT_FILE"

          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath buildInputs}:$LD_LIBRARY_PATH"
          export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"
        '';
      };
    };
}
