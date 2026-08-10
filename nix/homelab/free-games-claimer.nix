{
  # Epic / Prime Gaming / Steam の無料配布を自動で受け取る。2026-08-09 に CT101 へ
  # 足したので compose2nix の一括変換に間に合わず、移行時に宣言から漏れていた。
  #
  # イメージはタグではなくダイジェスト固定。公開リポジトリの commit 4fc0849 と
  # src/package.json の sha256 一致を確認したビルドを指している。ストアのログイン
  # 情報を握って自動操作する性質上、更新時は必ず差分を読んでから張り替えること。
  # :latest には戻さない。
  virtualisation.oci-containers.containers.fgc = {
    image = "ghcr.io/feldorn/free-games-claimer@sha256:640b1769d126c2272d664647bfeffa8b513d1025795ddb7791f91b2a7a1df5a6";
    volumes = [ "free-games-claimer_fgc:/fgc/data:rw" ];
    environment = {
      TZ = "Asia/Tokyo";
      LANG = "ja_JP.UTF-8";
      # microsoft.js (Bing Rewards) と gog.js は意図的に外してある。
      CLAIM_CMD = "prime-gaming.js; epic-games.js; steam.js";
      CLAIM_CMD_MANUAL = "prime-gaming.js; epic-games.js; steam.js";
      LOOP = "86400";
      START_TIME = "09:00";
      RUN_ON_STARTUP = "0";
      # 受け取りはせず通知だけするウォッチャー。
      UBISOFT_ACTIVE = "1";
      HUMBLE_ACTIVE = "1";
      FANATICAL_ACTIVE = "1";
      LENOVO_ACTIVE = "1";
      NOTIFY_TITLE = "free-games";
      NOTIFY_LEVEL = "actions";
      # 旧ホストの IP を指したままだったので新ホストへ。
      PUBLIC_URL = "http://192.168.116.98:7080";
    };
    # NOTIFY (ntfy の publish URL) と PANEL_PASSWORD。後者は VNC_PASSWORD にも使う。
    environmentFiles = [ "/var/lib/secrets/free-games-claimer.env" ];
    ports = [
      "6080:6080" # noVNC。各ストアへの初回ログインを手でやるための入口
      "7080:7080" # コントロールパネル
    ];
    log-driver = "journald";
    extraOptions = [ "--network-alias=fgc" ];
  };
}
