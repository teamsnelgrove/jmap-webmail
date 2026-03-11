{
  description = "JMAP Webmail — a modern Next.js JMAP email client";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    packages.${system}.default = pkgs.buildNpmPackage {
      pname = "jmap-webmail";
      version =
        (builtins.fromJSON (builtins.readFile ./package.json)).version;

      src = ./.;

      npmDepsHash = "sha256-cwRvpo/UofIDA0Dg8nkhlzGcd7vbxsR8BGbojTpswHM=";

      nodejs = pkgs.nodejs_22;
      nativeBuildInputs = [pkgs.makeWrapper];

      env.NEXT_TELEMETRY_DISABLED = "1";

      buildPhase = ''
        runHook preBuild
        npx next build --webpack
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out/share/jmap-webmail
        cp -r .next/standalone/. $out/share/jmap-webmail/
        cp -r .next/static $out/share/jmap-webmail/.next/static
        cp -r public $out/share/jmap-webmail/public

        # Wrapper script
        mkdir -p $out/bin
        makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/jmap-webmail \
          --add-flags "$out/share/jmap-webmail/server.js"

        runHook postInstall
      '';
    };

    nixosModules.default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.services.jmap-webmail;
    in {
      options.services.jmap-webmail = {
        enable = lib.mkEnableOption "JMAP Webmail";

        port = lib.mkOption {
          type = lib.types.port;
          default = 3000;
          description = "Port the webmail server listens on.";
        };

        jmapServerUrl = lib.mkOption {
          type = lib.types.str;
          description = "Public URL of the JMAP server (e.g. https://mail.example.com).";
        };

        appName = lib.mkOption {
          type = lib.types.str;
          default = "Webmail";
          description = "Application display name.";
        };

        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "File containing extra environment variables (OAuth secrets, session secret, etc.).";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.system}.default;
          defaultText = lib.literalExpression "jmap-webmail.packages.\${pkgs.system}.default";
          description = "The jmap-webmail package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.jmap-webmail = {
          description = "JMAP Webmail";
          after = ["network.target"];
          wantedBy = ["multi-user.target"];

          environment = {
            NODE_ENV = "production";
            PORT = toString cfg.port;
            HOSTNAME = "127.0.0.1";
            NEXT_TELEMETRY_DISABLED = "1";
            JMAP_SERVER_URL = cfg.jmapServerUrl;
            APP_NAME = cfg.appName;
          };

          serviceConfig = {
            Type = "simple";
            WorkingDirectory = "${cfg.package}/share/jmap-webmail";
            ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.package}/share/jmap-webmail/server.js";
            Restart = "on-failure";
            RestartSec = 5;

            # Sandboxing
            DynamicUser = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictSUIDSGID = true;

            EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
          };
        };
      };
    };
  };
}
