# Blocky の設定本体。homeserver と macmini の両方から読む。
#
# 2台で同じ設定を持つ理由は整理整頓ではなく正しさの側にある。クライアントは
# DHCP で渡された 2 つのリゾルバのどちらを引くか選べるので、片方だけ広告リストが
# 違ったり上流が違ったりすると、同じ端末の同じ問い合わせが日によって違う答えを
# 返す。それは追いかけられないので、差は待ち受けアドレスだけに閉じる。
{ listen }:
{
  ports = {
    dns = listen;
    http = 4000; # metrics + API. dns2.gapul.net が homeserver 側のこれを指す。
  };

  upstreams.groups.default = [ "https://dns10.quad9.net/dns-query" ];
  # IPv4 only for outgoing connections (upstream and list downloads). macmini has no IPv6
  # route, and the downloader dials the AAAA answer first and does not fall back inside an
  # attempt, so raw.githubusercontent.com failed 3/3 and two of three lists were missing
  # (2026-09-26). homeserver was fine only by luck of the answer order.
  connectIPVersion = "v4";
  # DoH は自分のホスト名を引けないので、ここはアドレスで書く。
  bootstrapDns = [
    { upstream = "9.9.9.10"; }
    { upstream = "149.112.112.10"; }
  ];

  blocking = {
    # 形式が先で出所は後。blocky が読めるのは hosts 形式・素のドメイン・ワイルドカード
    # (*.example.com)・正規表現だけ。AdGuard の `||domain^` 記法 (oisd の既定形式、
    # AdGuard DNS filter) は 0 件として黙って読まれ、blocking は enabled と言い、何も
    # 遮断されない。だから oisd も hagezi も wildcard 版の URL を指す。
    #
    # 2026-09-26 に NextDNS (profile 43b9d5) の設定をここへ引き継いだ。NextDNS 側は
    # oisd + AdGuard DNS filter + nextdns-recommended、Security は脅威インテリジェンス・
    # cryptojacking・typosquatting・DGA、allowlist 2 件。nextdns-recommended は非公開なので
    # 相当物なし。AdGuard DNS filter は oisd big の取り込み元に入っている。
    denylists = {
      # oisd big (NextDNS で使っていたもの) と hagezi Multi PRO++ の併用。実測 (2026-09-26)
      # で両者は 6 割ずつ互いに無いドメインを持つ補完関係だった。oisd は「壊さない」方針で
      # apex (doubleclick.net 自体など) を落とさず、PRO++ がそこを埋める。PRO++ には
      # Native Tracker (Apple / Windows・Office / Samsung / Xiaomi など、OS 組み込みの
      # テレメトリ) も PRO++ の段階で組み込まれている。前はここに StevenBlack があったが、
      # 両者に無い分は古いカウンターや使い捨て TLD の残骸で、逆に amazon-adsystem.com の
      # apex を落とすなど副作用の方が目立つので外した。
      ads = [
        "https://big.oisd.nl/domainswild"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.plus.txt"
      ];
      # hagezi Threat Intelligence Feeds (medium): NextDNS の Security タブの代わり。
      # フル版 (45MB) ではなく medium (18MB)。誤検知が少なく、macmini のメモリにも優しい。
      threats = [
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif.medium.txt"
      ];
    };
    # NextDNS の allowlist をそのまま。インライン定義 (YAML の literal block と同じ扱い)。
    allowlists.ads = [
      ''
        # carried over from the NextDNS allowlist
        1088045785.rsc.cdn77.org
        cdn.kde.org

        # Affiliate-network (ASP) click and conversion hosts, mostly Japanese networks.
        # A point-site reward (moppy/hapitas -> ASP redirect -> merchant) is attributed
        # through these; when they fail to resolve the application still goes through
        # and the reward is silently rejected weeks later. Blocking them saves no ads,
        # it only breaks attribution, so they are allowed for every client. Checked
        # against the ads group on 2026-09-27; the last three were not blocked and are
        # listed so the set stays complete when the upstream lists change.
        *.valuecommerce.com
        *.a8.net
        *.trafficgate.net
        *.accesstrade.net
        *.afi-b.com
        *.affiliate-b.com
        *.rentracks.jp
        *.j-a-net.jp
        *.link-a.net
        *.felmat.net
        *.af.moshimo.com
        *.adcrops.net
        *.tcs-asp.net
        *.ebis.ne.jp
        *.linksynergy.com
        *.presco.tv
        *.monetrack.com
      ''
    ];
    clientGroupsBlock.default = [
      "ads"
      "threats"
    ];
    # The lists are 5-18MB each; the 5s default timeout is for small ones. Retry with a real
    # pause so a flaky first fetch does not leave a group empty until the 4h refresh.
    loading.downloads = {
      timeout = "60s";
      attempts = 5;
      cooldown = "5s";
    };
    # 0.0.0.0 ではなく NXDOMAIN。クライアントが再試行をやめるし、
    # ブラックホールにソケットを吊るしたままにしない。
    blockType = "nxDomain";
  };

  caching = {
    minTime = "5m";
    maxTime = "30m";
    prefetching = true;
  };

  prometheus.enable = true;
  # 問い合わせはディスクに残さない。検索できるログが要るなら
  # queryLog.type = "csv" とパスをここに置く。
  queryLog.type = "none";
  log.level = "info";
}
