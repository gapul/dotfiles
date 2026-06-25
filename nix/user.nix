# Fork した時はこの 1 ファイルを編集すれば全体に反映される。
# darwinConfigurations / homeConfigurations の attribute 名も
# username に揃える (`just rebuild` / `nh` がそのまま動く)。
{
  # macOS のユーザー名(/Users/<username> に対応)
  username = "yuki";

  # git commit の author 情報
  # メールはパブリックリポへの個人アドレス露出を避けるため GitHub noreply を使用。
  # (実アドレスは secrets.yaml の pii: に暗号化集約)
  gitUser = "gapul";
  gitEmail = "92638132+gapul@users.noreply.github.com";

  # dotfiles 自身の GitHub URL(bootstrap.sh / nssh が clone する時に使う)
  dotfilesRepo = "https://github.com/gapul/dotfiles.git";
}
