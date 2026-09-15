# 自分のドメインで外とつながる発信の置き場。どれも軽いものだけを選んだ (合計でメモリ数百 MB)。
#
#   social.gapul.net  GoToSocial      Fediverse のアカウント @gapul@gapul.net の本体
#   relay.gapul.net   nostr-rs-relay  自分の Nostr 投稿を必ず残す個人リレー (書き込みは自分の鍵だけ)
#   blog.gapul.net    WriteFreely     Fediverse からフォローできる長文ブログ (1 人用)
#
# 3 つとも tailnet の外の人に届かないと意味が無いので、Caddy ではなく cloudflared のトンネルで
# 出す (homelab/cloudflared.nix)。家の IP は出ない。
#
# アカウント名は @gapul@gapul.net (account-domain = gapul.net)。GoToSocial 本体は social.gapul.net に
# 置き、gapul.net 直下の webfinger / host-meta / nodeinfo は CF Pages のポートフォリオ
# (gapul/gapul.net) の _redirects で social.gapul.net に回す。gapul.net の MX には触らない。
# host と account-domain は初回起動で DB に焼き込まれ、後から変えると作り直しになる。
#
# Nostr の鍵 (NIP-05 は gapul.net/.well-known/nostr.json):
#   npub16t57vts9q96ht7c80n9h40l4grvfq35x7hq7de9kdxpqu02fjr2s7q08y5
# 秘密鍵は /var/lib/secrets/nostr.env にだけあり、投稿の受け口が使う。
{ ... }:

let
  nostrPubkeyHex = "d2e9e62e05017575fb077ccb7abff540d8904686f5c1e6e4b669820e3d4990d5";
in
{
  services.gotosocial = {
    enable = true;
    settings = {
      host = "social.gapul.net";
      account-domain = "gapul.net";
      protocol = "https";
      bind-address = "127.0.0.1";
      port = 8110;
      # cloudflared が同じ箱の中から繋ぐので、転送元はループバックだけを信用する。
      trusted-proxies = [ "127.0.0.1/32" ];
      letsencrypt-enabled = false;
      accounts-registration-open = false;
      landing-page-user = "gapul";
      instance-languages = [
        "ja"
        "en"
      ];
      # 他サーバーの画像などのキャッシュは短く。自分の投稿の添付は消えない。
      media-remote-cache-duration = "168h";
    };
  };

  services.nostr-rs-relay = {
    enable = true;
    port = 8112;
    settings = {
      info = {
        relay_url = "wss://relay.gapul.net/";
        name = "gapul";
        description = "gapul's personal relay. Only accepts events from its owner.";
        pubkey = nostrPubkeyHex;
      };
      network = {
        address = "127.0.0.1";
        # トンネル経由なので接続元は 127.0.0.1 に見える。レート制限を実 IP で掛けるため。
        remote_ip_header = "cf-connecting-ip";
      };
      # 公開の無料リレーにしない。書き込めるのは自分の鍵だけ。読むのは誰でもよい。
      authorization.pubkey_whitelist = [ nostrPubkeyHex ];
      limits.messages_per_sec = 5;
    };
  };

  services.writefreely = {
    enable = true;
    host = "blog.gapul.net";
    settings = {
      app = {
        host = "https://blog.gapul.net";
        site_name = "gapul";
        single_user = true;
        federation = true;
        public_stats = false;
        open_registration = false;
      };
      server = {
        bind = "127.0.0.1";
        port = 8111;
      };
    };
    # 最初の管理ユーザーの初期パスワード。既定値は store に置かれた "nixos" なので必ず差し替える。
    # 読むのは初回だけ (ユーザーが 0 人のとき)。ログイン後に画面から変える。
    admin = {
      name = "gapul";
      initialPasswordFile = "/var/lib/secrets/writefreely-admin.password";
    };
  };
}
