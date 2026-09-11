{
  # AdGuard Home の代わりの Blocky。AdGuard の設定もここに宣言してあったので、
  # これは宣言的かどうかの話ではない。AdGuard は状態の半分を自分で書くファイルに
  # 持つ (管理アカウントと、Web UI で変えたもの全部) ので、それを nix と噛み合わせ
  # ようとすると mutableSettings = true にして両者が一致することを祈ることになる。
  # Blocky は UI も書き込み状態も持たない。設定はこの YAML が全部。
  #
  # 失うもの: 問い合わせログの閲覧と、クライアント別ルールのページ。メトリクスは
  # Prometheus 形式で出て、API は :4000 で答える。
  #
  # 副は macmini (hosts/macmini-dns.nix)。設定は lib/blocky-settings.nix で共有して
  # いて、この機械との差は待ち受けアドレスだけ。以前ここには「Raspberry Pi が
  # AdGuard を主リゾルバとして動かしているので家の DNS はこの機械に依存しない」と
  # 書いてあったが、Pi は 2026-08-24 に退役していて、その間この機械が唯一の
  # リゾルバだった。
  services.blocky = {
    enable = true;
    # ループバックとこの機械自身のアドレスだけ。0.0.0.0 にはできない: podman の
    # ブリッジが aardvark-dns のために :53 を要る。AdGuard が踏んだのと同じ衝突。
    #
    # tailnet アドレスも足してある。tailnet の DNS 設定からこの解決器を指すため
    # で、これが無いと外出先の端末は家の blocky を引けない (広告遮断も
    # gapul.net の内向き解決も効かない)。
    settings = import ../lib/blocky-settings.nix {
      listen = "127.0.0.1:53,192.168.116.98:53,100.127.129.31:53";
    };
  };

  # tailscale0 は blocky より後に上がる。tailnet アドレスを名指しで待ち受ける以上、
  # 起動順で「まだ存在しないアドレスに bind できない」で落ちうるので、非ローカル
  # アドレスへの bind を許す。After= で順序を付ける手もあるが、tailscaled が
  # 再接続でアドレスを付け直す局面まではカバーできない。
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  # 53 番は Blocky のもの。このホストでは他の何にも渡さない。
  services.resolved.enable = false;

  # ここだけは LAN から届く必要がある。クライアントがこのアドレスを直接指す。
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
