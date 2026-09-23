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
  # DoH は自分のホスト名を引けないので、ここはアドレスで書く。
  bootstrapDns = [
    { upstream = "9.9.9.10"; }
    { upstream = "149.112.112.10"; }
  ];

  blocking = {
    denylists.ads = [
      # hosts 形式。AdGuard 自身のリスト — この機械が前に使っていたもの — は
      # AdGuard の `||domain^` 記法で、blocky はそれを 0 件として読む。
      # ダウンロードは成功し、blocking は enabled と言い、何も遮断されない。
      # 黙って失敗するので、出所より形式のほうが効くと明記しておく。
      "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    ];
    clientGroupsBlock.default = [ "ads" ];
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
