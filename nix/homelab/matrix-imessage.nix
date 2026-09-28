# iMessage ブリッジの appservice 登録。ブリッジ本体はここには無い。
#
# 他の mautrix ブリッジは全部この箱で動くが、iMessage だけは chat.db と Messages.app が
# 要るので macmini で動く (nix/home/macmini-imessage.nix)。Synapse から見ると「tailnet の
# 向こうにいる appservice」で、この箱に置くのは登録ファイルだけ。
#
# トークンの流れ: 他のブリッジは同じ箱で --generate-registration して Synapse に渡すが、
# ここでは機械が別なので、as_token / hs_token を secrets/matrix-imessage.yaml に置いて
# 両方の host 鍵で開ける形にした (.sops.yaml)。この箱は登録ファイルに、macmini は
# ブリッジの config に、同じ値を差し込む。トークンを作り直すときは両方が同時に変わる。
#
# url は macmini の tailnet アドレス。Synapse はイベントをここへ push する。macmini 側の
# ファイアウォール (hosts/macmini.nix の socketfilterfw) に穴が要るのはそのため。
{ config, ... }:
let
  domain = "gapul.net";
  macmini = "100.105.135.49";
  port = 29332;
  registration = "matrix-imessage-registration.yaml";
in
{
  sops.secrets = {
    "matrix_imessage/as_token".sopsFile = ../../secrets/matrix-imessage.yaml;
    "matrix_imessage/hs_token".sopsFile = ../../secrets/matrix-imessage.yaml;
  };

  # 名前空間はブリッジが --generate-registration で出すものと同じ (2026-09-28 に実機で
  # 生成して写した)。bot と imessage_* を exclusive で取る。push_ephemeral は既読や
  # 入力中の転送に要る (config の appservice.ephemeral_events と対)。
  sops.templates.${registration} = {
    owner = "matrix-synapse";
    mode = "0400";
    restartUnits = [ "matrix-synapse.service" ];
    content = ''
      id: imessage
      url: http://${macmini}:${toString port}
      as_token: ${config.sops.placeholder."matrix_imessage/as_token"}
      hs_token: ${config.sops.placeholder."matrix_imessage/hs_token"}
      sender_localpart: imessagebot
      rate_limited: false
      namespaces:
        users:
          - regex: '^@imessagebot:${builtins.replaceStrings [ "." ] [ "\\." ] domain}$'
            exclusive: true
          - regex: '^@imessage_.*:${builtins.replaceStrings [ "." ] [ "\\." ] domain}$'
            exclusive: true
      de.sorunome.msc2409.push_ephemeral: true
      push_ephemeral: true
    '';
  };

  services.matrix-synapse.settings.app_service_config_files = [
    config.sops.templates.${registration}.path
  ];
}
