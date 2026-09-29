# matrix-line: Matrix と LINE を繋ぐブリッジ (mautrix-go の bridgev2)。
#
# nixpkgs には無い。mautrix 公式の LINE ブリッジは存在せず、これは Beeper が
# 取り込んだコミュニティ実装 (元は highesttt/matrix-line-messenger)。GitHub の
# beeper/line が今の本流で、go.mod のモジュール名は旧名のまま。
#
# LINE の Chrome 拡張として振る舞うので、ログインすると Chrome 拡張版 LINE の
# セッションは切れる (逆も同じ)。同時に使えるのはどちらか一方だけ。
#
# タグが打たれていないので commit で固定する。
#
# olm は mautrix-go の E2EE が要求する。insecure の印付きなので、使う host は
# nixpkgs.config.permittedInsecurePackages に "olm-3.2.16" が要る。homeserver は
# nix/homelab/matrix-bridges.nix で許可済みで、理由もそこに書いてある。
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "matrix-line";
  version = "1.2.0-unstable-2026-09-28";

  src = fetchFromGitHub {
    owner = "beeper";
    repo = "line";
    rev = "3b3c06640383e4323074784b7f242e41e9b85d35";
    hash = "sha256-3GiSFzCSKIEN7vqgWXqkGfUY0Bf3f1cD3g6oqpiDwZQ=";
  };

  vendorHash = "sha256-qs0FaqCgKo0a9wrER6G1fAJ/UcOvoZEH2gNvS/hkm2E=";

  # sqlite が cgo なので無効にはできない。
  env.CGO_ENABLED = "1";

  buildInputs = [ olm ];

  subPackages = [ "cmd/matrix-line" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=${finalAttrs.version}"
    "-X main.Commit=${finalAttrs.src.rev}"
  ];

  # 上流のテストは LINE への実接続を前提にしたものが混ざっている。
  doCheck = false;

  meta = {
    description = "Matrix と LINE を繋ぐブリッジ";
    homepage = "https://github.com/beeper/line";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "matrix-line";
  };
})
