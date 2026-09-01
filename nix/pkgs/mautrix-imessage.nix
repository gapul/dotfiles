# mautrix-imessage: Matrix と iMessage を繋ぐブリッジ。
#
# nixpkgs には無い。他の mautrix ブリッジ (discord / signal / meta / telegram) は
# 入っているが、これだけ macOS 専用なので誰も入れていない。
#
# なぜ Mac が要るか: iMessage には外から叩ける API が無い。このブリッジは
# ~/Library/Messages/chat.db を読み、送信は Messages.app を動かして行う。つまり
# 「iMessage にログイン済みの Mac」そのものが接続の実体で、Linux に置き換えられない。
# homeserver に置けない唯一のブリッジ。
#
# タグが打たれていないので commit で固定する。上流は GitLab (mau.dev) が正で、
# GitHub は鏡だが、鏡の方が fetchFromGitHub でそのまま取れるのでこちらを使う。
#
# ビルドの確認 (2026-09-01, aarch64-darwin):
#   mautrix-imessage 0.1.0+dev.300ba6d0 (unknown with go1.26.6)
#
# olm が insecure の印付きなので、これを使う host は
# nixpkgs.config.permittedInsecurePackages に "olm-3.2.16" が要る。homeserver 側は
# nix/homelab/matrix-bridges.nix で既に許可済みで、そこに理由も書いてある。
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "mautrix-imessage";
  version = "0-unstable-2026-05-14";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "imessage";
    rev = "300ba6d0e5566d1f841d42ee1555779a9b6fa4be";
    hash = "sha256-qKSb4/kktqNHyOKOOLDrAqV+GZ5StU3lGUc3/90CE+c=";
  };

  vendorHash = "sha256-xTzxL4pk6tmWcEhd0bbdwP70hEqNDjB/xahLWY5nRKQ=";

  # sqlite が cgo なので無効にはできない。
  env.CGO_ENABLED = "1";

  # libheif は付けない。
  #
  # 付けると HEIC を変換できるので本当は欲しいのだが、vendor されている Go
  # バインディング (strukturag/libheif v1.19.5) が nixpkgs の libheif と噛み合わない。
  # C 側の enum が別型になっていて `cannot use uint32(channel) as _Ctype_heif_channel`
  # で通らない。古い libheif に固定する手はあるが、ローリングの方針に反するうえ、
  # 画像処理ライブラリの更新を止めることになる。
  #
  # 上流の build.sh も libheif が見つからなければ tag を外すので、これは想定内の
  # 構成。代償は iMessage の写真が .heic のまま Matrix に届くこと。バインディングが
  # 追いついたら tags = [ "libheif" ] と pkg-config を戻す。

  # olm は mautrix-go の E2EE が要求する。他のブリッジ (nix/homelab/matrix-bridges.nix)
  # で許可した libolm と同じもので、非推奨の印が付いている。ここでも使うのは
  # ブリッジ側の E2EE を有効にしたときだけで、今は有効にしていない。
  # E2EE を入れるときに、あちらと合わせて判断し直すこと。
  buildInputs = [ olm ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=${finalAttrs.version}"
    "-X main.Commit=${finalAttrs.src.rev}"
  ];

  # 上流のテストは chat.db と Messages.app がある実機を前提にしている。
  doCheck = false;

  meta = {
    description = "Matrix と iMessage を繋ぐブリッジ (macOS 専用)";
    homepage = "https://github.com/mautrix/imessage";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.darwin;
    mainProgram = "mautrix-imessage";
  };
})
