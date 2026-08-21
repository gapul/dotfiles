# SSH 認証局

各ホストの `authorized_keys` に公開鍵を撒くのをやめ、短命の証明書で入る構成。

## なぜ

鍵を配る方式は、ホストが増えるたび、鍵を作り直すたびに全台を触ることになる。失効も「全部から消して回る」しか手段がない。サーバ側は実際に手置きのままだった（`hosts/homeserver.nix` の旧コメント）。

CA なら、信頼する側の設定は1回で終わる。以後、機械を増やしても証明書を切るだけで、サーバには触らない。証明書には有効期限があるので、失効は放っておけば起きる。

## CA 鍵の置き場所

MacBook の Secure Enclave。`protection = "bio"` なので、**署名のたびに Touch ID が要る**。

これが構成の要になっている。CA は全ホストへの入場券を発行できる鍵なので、Mac にコードを実行できる攻撃者がいても、人が物理的に指を置かない限り証明書が生まれない状態にしたい。常時起動のサーバに CA を置くと、その機械を取られた瞬間に無承認で刷り放題になるため、あえて選んでいない。

鍵の種類は `sk-ecdsa-sha2-nistp256@openssh.com`。`nix-secure-enclave-key` が CryptoTokenKit の identity を macOS 標準の SSH プロバイダ経由で見せるので、OpenSSH からは FIDO 認証器と同じ扱いになり、`-w` でプロバイダを指すだけで通常の CA 署名に乗る。

```sh
nix-secure-enclave-key setup --key-file ~/.ssh/id_enclave_key --label auth --protection bio
```

enclave の identity は **1本だけ**にしている。`nix-secure-enclave-key` は2本目以降に対して
使える秘密鍵スタブを作らず、公開鍵の参照ファイルしか置かないため（`ssh-keygen -s` が
`invalid format` で落ちる）。したがって enclave を割り当てられる役は1つで、その1つは
「都度承認が効くこと」の価値が高い CA に使っている。

クライアント側の鍵は enclave である必要がない。証明書は任意の公開鍵に載せられるので、
既存の Bitwarden 管理の鍵（`~/.ssh/id_ed25519.pub`）をそのまま証明書の対象にしている。

公開鍵は `nix/keys/ssh-user-ca.pub` にコミットしてある。CA の公開鍵は信頼する側が全員持つものなので、公開リポジトリに置いて問題ない。

## 予備 CA を作らない理由

予備 CA は `TrustedUserCAKeys` に載せっぱなしになる。使うのが数年に一度でも、任意の principal の証明書を発行できる権限は毎日そこにある。

一方、予備に求めているのは「Mac が死んでも各ホストに入れること」だけで、証明書の発行権ではない。なので後述の break-glass 鍵で代替する。ログイン権しか持たないぶん、常時抱えるリスクが小さい。

## 使い方

```sh
just ssh-cert                          # ~/.ssh/id_ed25519.pub に 8 時間
just ssh-cert ~/tmp/laptop.pub 720     # 別マシンの鍵に 30 日
```

証明書は公開鍵の隣に `-cert.pub` として出る。OpenSSH は IdentityFile の隣にある `-cert.pub` を
自動で拾うので、`~/.ssh/config` に追加の記述は要らない。Bitwarden の agent で鍵が出ている
場合も、証明書ファイルさえ隣にあれば ssh はそれを使う。

## Mac 以外のマシン

証明書を発行できるのは Touch ID のあるこの Mac だけなので、他のマシンは**自分で更新できない**。
なので有効期限を長めに切って、Mac で発行したものを持っていく。

```sh
scp nixos-laptop:.ssh/id_ed25519.pub ~/tmp/laptop.pub
just ssh-cert ~/tmp/laptop.pub 720
scp ~/tmp/laptop-cert.pub nixos-laptop:.ssh/id_ed25519-cert.pub
```

この非対称性は仕様。承認する端末を1台に絞ると決めた結果で、その1台が物理的に必要になる。

## break-glass 鍵

CA が使えない状況（Mac の故障・紛失）からの復旧用。**日常では一切使わない**専用の鍵を1本作り、秘密鍵は Bitwarden に入れて、agent には登録しない。agent に入れると常用鍵になってしまい、専用である意味が消える。

```sh
ssh-keygen -t ed25519 -a 100 -C "break-glass" -f /tmp/break-glass   # パスフレーズを付ける
# 秘密鍵を Bitwarden に保存してから
shred -u /tmp/break-glass   # macOS では rm -P
```

公開鍵を各ホストの `authorized_keys` に置く。CA を配るときに一度は各ホストを触るので、そのついでで済む。

## 信頼する側

`nix/modules/nixos/ssh-ca.nix` を import するだけ。`homeserver` と `nixos-laptop` に入れてある。

`AuthorizedPrincipalsFile` は使っていない。CA を信頼している場合、sshd は principal リストにログイン名が入っている証明書を受け入れる。`just ssh-cert` は `-n` にログイン名を入れて署名するので、これで足りる。

Proxmox の CT はまだ NixOS 化されていないので、`/etc/ssh/sshd_config` に手で以下を足す。

```
TrustedUserCAKeys /etc/ssh/gapul-user-ca.pub
```
