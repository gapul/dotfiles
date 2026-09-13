# ダブルパペット用の appservice。@gapul:gapul.net 本人として送信できる登録を Synapse に置く。
#
# 何に使うか:
#   - ブリッジ: スマホの LINE から自分が送った発言を、ボットの代理ではなく
#     @gapul の発言として Matrix に出す (mautrix の double_puppet.secrets に
#     "as_token:<token>" を渡す標準の方式)
#   - 過去ログの取り込み: Synapse は送信時刻の上書き (?ts=) を appservice にしか
#     許さない。自分の古い発言を元の時刻で入れるにはこの登録が要る
#
# 名前空間は @gapul:gapul.net だけに絞る。mautrix の手順書は @.*:domain だが、
# このトークンで成りすませる範囲をわざわざ広げる理由が無い。
#
# トークンは初回に生成して /var/lib に置く。store には入らない。Synapse と
# ブリッジはグループ経由で読む。
{ pkgs, ... }:
let
  dataDir = "/var/lib/matrix-doublepuppet";
  registrationFile = "${dataDir}/registration.yaml";
in
{
  users.groups.matrix-doublepuppet = { };

  systemd.services.matrix-doublepuppet-registration = {
    description = "Generate the double puppeting appservice registration";
    before = [ "matrix-synapse.service" ];
    requiredBy = [ "matrix-synapse.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = baseNameOf dataDir;
      StateDirectoryMode = "0750";
      Group = "matrix-doublepuppet";
      UMask = "0027";
    };
    script = ''
      if [ ! -f '${registrationFile}' ]; then
        token() { ${pkgs.openssl}/bin/openssl rand -hex 32; }
        as_token=$(token)
        cat > '${registrationFile}.tmp' <<EOF
      id: doublepuppet
      url: null
      as_token: $as_token
      hs_token: $(token)
      sender_localpart: $(token)
      rate_limited: false
      namespaces:
        users:
          - regex: '@gapul:gapul\.net'
            exclusive: false
      EOF
        printf '%s' "$as_token" > '${dataDir}/as_token.tmp'
        mv '${dataDir}/as_token.tmp' '${dataDir}/as_token'
        mv '${registrationFile}.tmp' '${registrationFile}'
      fi
      chgrp matrix-doublepuppet '${dataDir}' '${registrationFile}' '${dataDir}/as_token'
    '';
  };

  services.matrix-synapse.settings.app_service_config_files = [ registrationFile ];
  systemd.services.matrix-synapse.serviceConfig.SupplementaryGroups = [ "matrix-doublepuppet" ];
}
