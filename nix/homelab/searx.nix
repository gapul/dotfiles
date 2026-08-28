# メタ検索 (SearXNG)。tailnet 内のみ。
#
# ここだけコンテナではなくネイティブモジュールなのは、default.nix の方針を破って
# いるように見えて実は逆で、あの方針が「移設コストに見合わないから既存のスタックは
# コンテナのまま」という話だから。これは新規で、移すデータが無い。そしてこのサービスの
# 設定の本体はエンジンの取捨選択で、コンテナにすると settings.yml を /var/lib へ手で
# 置くことになる。それは README が「設定が web UI やコマンドラインに住むのをやめる」と
# 言っている状態そのものになる。services.searx なら下の settings がそのまま git に載る。
#
# 上流の settings.yml にマージされる (use_default_settings)。エンジンは name で
# 突き合わせるので、既定で無効なものを1行で起こせる。
#
# limiter は入れない。あれは公開インスタンス向けのボット対策で、有効にすると valkey が
# 要る。ここは tailnet 内の単独ユーザーなので、守る相手がいない。
#
# --- ブロックについて (調べた結果) ---
# 「VPS でやらないとブロックされる」は逆に近い。Google が先に潰すのは AWS/GCP/Azure や
# 大手 VPS のレンジで、住宅 IP のほうが長生きする。ただし住宅 IP なら安全でもない。
#
# 停止時間の既定値 (searx/settings.yml):
#   429 / Access Denied ......... 180秒
#   通常の CAPTCHA .............. 1時間
#   Cloudflare 経由の拒否 ....... 1日
#   reCAPTCHA ................... 7日
#   Cloudflare 経由の CAPTCHA ... 15日
# つまり日常的に踏むほうは3分〜1時間で軽い。痛いのは下の2つで、Google が本気で
# 嫌がったときに来る。個人利用の量なら滅多に引かないはずで、引いてもそのエンジンが
# 抜けるだけで検索自体は他が答える。だから google も startpage も切らずに best-effort で
# 有効なままにしてある。壊れたら勝手に外れる。
#
# 代わりに、既定で無効な mojeek と qwant を起こしておく。mojeek は自前クローラの独立
# インデックスなので、Google 系の対ボット網に巻き込まれない。ここが倒れずに残る。
{ nixpkgsUnstable, ... }:
{
  # searxng は nixpkgs 26.05 系列だと 2026-05-16 版で止まっており、検索エンジン側の
  # 変更に追随できず brave / duckduckgo / qwant / mojeek / startpage が一斉に
  # CAPTCHA や access denied を返す状態になっていた (実際に全滅した)。
  #
  # スクレイパは壊れ続けるものなので、ここだけ unstable に寄せる。安定版であることの
  # 意味が薄い類のパッケージで、古いことがそのまま機能しないことを意味する。
  services.searx.package =
    (import nixpkgsUnstable.legacyPackages.x86_64-linux.path {
      system = "x86_64-linux";
    }).searxng;

  services.searx = {
    enable = true;

    # secret_key だけ。envsubst で下の $SEARXNG_SECRET に入る。
    # 他の homelab と同じく手で置く (README.md 参照)。
    environmentFile = "/var/lib/secrets/searx.env";

    settings = {
      server = {
        # Caddy が同じ箱から叩くので loopback で足りる。
        bind_address = "127.0.0.1";
        port = 8088;
        base_url = "https://search.gapul.net/";
        secret_key = "$SEARXNG_SECRET";
        # 公開しないので、どちらも要らない (limiter を true にすると valkey が要る)。
        limiter = false;
        public_instance = false;
      };

      engines = [
        # 既定で無効。自前クローラの独立インデックスで、Google 系が軒並み
        # CAPTCHA に沈んだときに残る側。ここを起こすのが今回の肝。
        {
          name = "mojeek";
          disabled = false;
        }
        # 同じく既定で無効。これも Bing/Google とは別系統。
        # ただし 2026-08 時点では CAPTCHA に沈んでいる。自動で外れるので置いてある。
        {
          name = "qwant";
          disabled = false;
        }
        # これも自前クローラ。鍵が要らず、実測で 53 件返した (mojeek と同じ役割で、
        # Google 系が全滅したときに残る側を厚くする)。
        {
          name = "mwmbl";
          disabled = false;
        }
      ];
    };
  };
}
