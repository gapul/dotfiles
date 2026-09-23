{
  config,
  lib,
  pkgs,
  ...
}:
let
  stateDir = "/var/db/homeserver-external-monitor";
  emailFile = config.sops.secrets."pii/email_personal".path;
  passwordFile = config.sops.secrets."pii/gmail_app_password_mail".path;

  monitor = pkgs.writeShellApplication {
    name = "homeserver-external-monitor";
    runtimeInputs = with pkgs; [ curl ];
    text = ''
            set -u
            umask 077

            state_dir=${lib.escapeShellArg stateDir}
            mkdir -p "$state_dir"

            send_mail() {
              local transition="$1" name="$2" url="$3" timestamp email password
              timestamp="$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')"
              email="$(tr -d '\r\n' < ${lib.escapeShellArg emailFile})"
              password="$(tr -d '\r\n ' < ${lib.escapeShellArg passwordFile})"

              if [ "$transition" = DOWN ]; then
                body="''${timestamp} (JST)、Mac miniからの60秒ごとのHTTPS確認において、''${name} (''${url}) が3回連続で失敗しました。
      監視状態がDOWNに遷移しました。
      対象の手動確認をお願いします。"
              else
                body="''${timestamp} (JST)、''${name} (''${url}) において、失敗していたHTTPS応答が回復しました。
      監視状態がRECOVEREDに遷移しました。
      対象の手動確認をお願いします。"
              fi

              {
                printf 'From: %s\r\n' "$email"
                printf 'To: %s\r\n' "$email"
                printf 'Subject: [homeserver] %s: %s\r\n' "$transition" "$name"
                printf 'Content-Type: text/plain; charset=UTF-8\r\n'
                printf '\r\n%s\r\n' "$body"
              } | curl --silent --show-error --fail --ssl-reqd \
                --url smtps://smtp.gmail.com:465 \
                --config <(printf 'user = "%s:%s"\n' "$email" "$password") \
                --mail-from "$email" --mail-rcpt "$email" --upload-file -
            }

            check_target() {
              local id="$1" name="$2" url="$3"
              local state_file="$state_dir/$id.state"
              local count_file="$state_dir/$id.failures"
              local previous=unknown failures=0

              [ -r "$state_file" ] && previous="$(<"$state_file")"
              [ -r "$count_file" ] && failures="$(<"$count_file")"
              if ! [[ "$failures" =~ ^[0-9]+$ ]]; then
                failures=0
              fi

              if curl --silent --show-error --fail --location \
                --connect-timeout 5 --max-time 15 --output /dev/null "$url"; then
                printf '0\n' > "$count_file"
                if [ "$previous" = down ]; then
                  if send_mail RECOVERED "$name" "$url"; then
                    printf 'up\n' > "$state_file"
                  fi
                else
                  printf 'up\n' > "$state_file"
                fi
                return
              fi

              failures=$((failures + 1))
              printf '%s\n' "$failures" > "$count_file"
              if [ "$failures" -ge 3 ] && [ "$previous" != down ]; then
                # Only persist the transition after SMTP accepted it. If the independent
                # route is temporarily unavailable, retry instead of losing the alert.
                if send_mail DOWN "$name" "$url"; then
                  printf 'down\n' > "$state_file"
                fi
              fi
            }

            # The first URL answers whether the host/tunnel path is alive. The second
            # catches ntfy itself being down while the rest of the host still responds.
            check_target homeserver homeserver https://status.gapul.net/
            check_target ntfy ntfy https://ntfy.gapul.net/v1/health
    '';
  };
in
{
  # An independent route is essential: publishing to ntfy cannot report that
  # ntfy or its host is down. The existing Gmail app password is scoped to mail
  # and remains encrypted to the Mac mini's SSH host key.
  sops.secrets."pii/email_personal" = { };
  sops.secrets."pii/gmail_app_password_mail" = { };

  launchd.daemons.homeserver-external-monitor = {
    serviceConfig = {
      ProgramArguments = [ (lib.getExe monitor) ];
      RunAtLoad = true;
      StartInterval = 60;
      ProcessType = "Background";
      StandardOutPath = "/var/log/homeserver-external-monitor.log";
      StandardErrorPath = "/var/log/homeserver-external-monitor.log";
    };
  };

  system.activationScripts.preActivation.text = lib.mkAfter ''
    /bin/mkdir -p ${stateDir}
    /bin/chmod 0700 ${stateDir}
  '';
}
