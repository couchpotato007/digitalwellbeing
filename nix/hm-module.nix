# Home Manager module running the agent as a systemd user service.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.digitalwellbeing-agent;
  inherit (lib) mkOption types;
in
{
  options.services.digitalwellbeing-agent = {
    enable = lib.mkEnableOption "the digital wellbeing agent, which forwards ActivityWatch data to the server";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.agent;
      defaultText = lib.literalExpression "digitalwellbeing.packages.\${system}.agent";
    };

    serverUrl = mkOption {
      type = types.str;
      example = "https://wellbeing.example.org";
    };

    device = mkOption {
      type = types.str;
      example = "laptop";
      description = "Name of this device on the dashboard, unique per device.";
    };

    tokenFile = mkOption {
      type = types.str;
      example = "/run/agenix/wellbeing-token";
      description = ''
        File containing the server's ADMIN_TOKEN. It is read when the service
        starts and never copied to the Nix store, so it works with agenix or
        sops-nix.
      '';
    };

    activitywatchUrl = mkOption {
      type = types.str;
      default = "http://localhost:5600";
    };

    interval = mkOption {
      type = types.ints.unsigned;
      default = 300;
      description = "Seconds between syncs.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.digitalwellbeing-agent = {
      Unit = {
        Description = "Digital wellbeing agent";
        After = [ "activitywatch.service" ];
      };
      Service = {
        Environment = [
          "SERVER_URL=${cfg.serverUrl}"
          "DEVICE=${cfg.device}"
          "ACTIVITYWATCH_URL=${cfg.activitywatchUrl}"
          "INTERVAL_SECONDS=${toString cfg.interval}"
        ];
        ExecStart = toString (
          pkgs.writeShellScript "digitalwellbeing-agent" ''
            TOKEN="$(< ${lib.escapeShellArg cfg.tokenFile})"
            export TOKEN
            exec ${lib.getExe cfg.package}
          ''
        );
        Restart = "on-failure";
        RestartSec = 30;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
