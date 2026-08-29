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

      # エンジンを足すときは、必ず結果に**エンジン名が出ること**まで確認する。
      # SearXNG は知らないショートカットを検索語として扱うので、`!foo` が
      # 結果を返しても foo が動いている証拠にならない。存在しないエンジンを
      # 2 つ入れてしまった (luxxle / rawweb)。`/config` に載っているかで実在を、
      # 結果へのエンジン名の出現で稼働を確かめる。
      #
      # duckduckgo / startpage / brave は既定で有効なまま残す。どれも
      # 2026-08 時点では CAPTCHA や rate limit に沈んでいるが、エンドポイント
      # 自体は生きていて (202 / 302 / 200 が返る)、対ボットのチャレンジを
      # 越えられないだけ。向こう側の気分で戻ることがあるので、SearXNG の
      # 自動 suspend に任せる。
      #
      # 恒久的に効かせたいなら公式 API に寄せる道がある。braveapi エンジンが
      # 同梱されていて、api_key を入れれば安定する (無料枠あり)。marginalia も
      # 同様。どちらも鍵の取得が要るので、必要になったときに。
      engines = [
        # mojeek は「Google 系が沈んでも残る側」として起こしていたが、2026-08-29
        # 時点でスクレイピングそのものが塞がれた。homeserver / 母艦 / 外部の
        # 3 経路すべてで 403 が返る (UA を変えても同じ) ので、IP の問題ではなく
        # 向こう側の変更。実装が追いつくまで切る。
        {
          name = "mojeek";
          disabled = true;
        }
        # qwant も別系統だが、2026-08 時点で CAPTCHA に沈んでいる。自動で
        # 外れるとはいえ毎回叩きに行って待たされるので、明示的に切る。
        {
          name = "qwant";
          disabled = true;
        }
        # これも自前クローラ。鍵が要らず、実測で 53 件返した (mojeek と同じ役割で、
        # Google 系が全滅したときに残る側を厚くする)。
        {
          name = "mwmbl";
          disabled = false;
        }
        # duckduckgo の別実装。既定の duckduckgo は CAPTCHA に沈んでいるが、
        # こちらは通る。日本語のクエリでも結果が返り、結果にエンジン名が
        # 出ることまで確認した。
        {
          name = "duckduckgo web";
          disabled = false;
        }
        # 対ボット網に巻き込まれていない側を厚くする。どちらも鍵が要らない。
        {
          name = "privacywall";
          disabled = false;
        }
        {
          name = "searchmysite";
          disabled = false;
        }
      ];
    };
  };
}
