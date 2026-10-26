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
      pkgs = import nixpkgs { inherit system; };

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
      };

      scriptPackages = pkgs.lib.mapAttrsToList (name: body: pkgs.writeShellScriptBin name body) myScripts;

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
            ];
            extraReadwriteDirs = [ "~/.claude" ];
          })

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
