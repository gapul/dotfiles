{
  pkgs,
  lib,
  user,
  ...
}:
{
  # Windows とデュアルブートする HP ノート (x86_64, Intel 内蔵 GPU)。
  # 実機で `nixos-generate-config` が吐いた hardware-configuration.nix を
  # 同じ hosts/ に置いて下の import を有効化する (リポジトリには未コミットでよい)。
  imports = [
    ./nixos-laptop-hardware.nix
  ];

  # --- ブートローダ: lanzaboote (Secure Boot 対応) ---
  # 通常の systemd-boot を無効化し、署名付き UKI を使う lanzaboote に置換。
  # メニュー自体は systemd-boot ベースなので Windows Boot Manager も自動検出される
  # (ESP の EFI/Microsoft/Boot を検出。os-prober 不要)。
  #
  # ⚠️ 初回インストール〜鍵登録までの間は Secure Boot を一旦 OFF のまま進める。
  #    `sbctl create-keys` → `sbctl enroll-keys --microsoft` → BIOS で Secure Boot ON
  #    の手順は docs/NIXOS_DUALBOOT.md の Phase 8 を参照。
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  # メニュー表示秒数。Windows と NixOS を両方使うので取り逃さないよう余裕を持たせる。
  boot.loader.timeout = 5;
  boot.lanzaboote = {
    enable = true;
    # sbctl が鍵を置く場所。`sbctl create-keys` の既定と合わせる。
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 8; # ESP が 100MB しかなければ 3〜5 に下げる
  };
  # ESP 自体は暗号化できない (ファームウェアが平文で読むため) が、Secure Boot で
  # カーネル/initrd (UKI) が署名検証されるので、ESP 上のブート列の改ざんは検知される。
  # Windows 既設 ESP を流用するので、生成された hardware-configuration.nix の
  # fileSystems."/boot" が ESP (vfat, 例: /dev/nvme0n1p1) を指すことを確認する。

  # --- ディスク暗号化 (LUKS) ---
  # 実際の cryptroot デバイス (UUID) は nixos-generate-config が
  # hardware-configuration.nix の boot.initrd.luks.devices に書き込む。手順は
  # docs/NIXOS_DUALBOOT.md の Phase 4-5 を参照。
  # スワップは平文パーティションを避け zram (メモリ内・暗号化された RAM 上) を使う。
  zramSwap.enable = true;

  # systemd ベースの initrd (TPM2 自動解錠に必要 + モダンな initrd)。lanzaboote と併用可。
  boot.initrd.systemd.enable = true;
  # cryptroot を TPM2 で自動解錠する。Secure Boot 有効化後に
  #   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 <LUKSパーティション>
  # で PCR 7 (Secure Boot 状態) へ鍵を登録する (docs 付録A)。未登録ならパスフレーズに
  # フォールバックするので安全。device 本体は hardware-configuration.nix の cryptroot で定義。
  boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];

  # --- 運用メンテ (デュアルブートの固定パーティション容量を枯らさない) ---
  # Nix store を自動 GC + 重複排除。Windows と容量を分け合う以上、store の肥大を抑える。
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings = {
    # ⚠️ 必須: これが無いと `nixos-rebuild switch --flake` が動かない。
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true; # store の重複排除
    # Hyprland をソースビルドせず公式バイナリキャッシュから取得 (数十分の短縮)。
    # nix-community は darwin 側 (hosts/darwin.nix) と同じ最小権限ポリシーで追加。
    substituters = [
      "https://cache.nixos.org"
      "https://hyprland.cachix.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  # nh (nix helper): darwin と同じワークフロー。`nh os switch` で再構築できる。
  # GC は上の nix.gc に任せるため nh.clean は無効のまま (二重 GC 回避)。
  programs.nh = {
    enable = true;
    flake = "/home/${user.username}/.dotfiles/nix";
  };

  # ファーム更新を Linux 側から意図したタイミングで行う。BIOS の不意更新で
  # Secure Boot 鍵 / TPM 測定値が変わって回復キーを要求される事故を減らせる。
  services.fwupd.enable = true;

  networking.hostName = "nixos-laptop";
  networking.networkmanager.enable = true;

  # 自宅 homelab は Tailscale 上 (*.gapul.net)。このマシンも参加させる。
  # 初回のみ `sudo tailscale up` で認証する。
  services.tailscale.enable = true;

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";
  console.keyMap = "us"; # JIS 配列なら "jp"

  # Windows とのデュアルブートで時計がズレる問題への対策。
  # NixOS は RTC を UTC として扱う。Windows 側も
  #   reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
  # で UTC に揃えると両 OS で時刻が一致する (手順は docs/NIXOS_DUALBOOT.md 参照)。

  # --- Intel 内蔵 GPU ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # Gen8+ (推奨)
      intel-vaapi-driver # 古い世代向けフォールバック (旧 vaapiIntel)
    ];
  };

  nixpkgs.config.allowUnfree = true;

  # --- ラップトップ電源/熱/入力 (HP ノート) ---
  services.tlp.enable = true; # バッテリー最適化 (充電閾値等は後で調整可)
  services.thermald.enable = true; # Intel CPU の熱制御 (サーマルスロットリング適正化)
  services.libinput.enable = true; # タッチパッド (タップ・自然スクロール等)
  # 蓋を閉じたらサスペンド (既定動作。必要なら logind で上書き)。
  # バッテリー残量/明るさは brightnessctl + waybar 側で扱う。

  # 無線/BT 等のプロプライエタリ firmware (ノートの Intel WiFi/Bluetooth に必須)。
  hardware.enableRedistributableFirmware = true;
  # SSD の定期 TRIM (寿命・性能維持)。
  services.fstrim.enable = true;

  # --- デスクトップ: Hyprland (Wayland タイル型コンポジタ) ---
  # Hyprland 本体 + xdg-desktop-portal-hyprland + XWayland をまとめて有効化。
  programs.hyprland.enable = true;

  # ログイン: greetd + tuigreet (軽量・Wayland 対応。TTY から Hyprland を起動)。
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
      user = "greeter";
    };
  };

  # GUI 権限昇格ダイアログ用の polkit エージェント (Hyprland は DE 同梱が無いため明示)。
  security.polkit.enable = true;

  # 画面ロック: hyprlock の PAM/セキュリティラッパーをシステム側で用意する
  # (見た目の設定と hypridle の常駐は home-manager 側 home/hyprland.nix に置く)。
  programs.hyprlock.enable = true;

  # Electron/Chromium・Firefox を Wayland ネイティブで動かす (HiDPI のにじみ回避)。
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };
  # GTK アプリ設定の保存先 dconf (一部 GUI アプリが要求)。
  programs.dconf.enable = true;
  # ファイル選択ダイアログ等のため GTK portal も併用 (hyprland portal は同梱済)。
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # キーボード配列は Hyprland の input{kb_layout} で設定する。コンソールは console.keyMap。
  # fcitx5 の日本語入力は下の i18n.inputMethod が Wayland 用 env も含めて面倒を見る。

  # 日本語入力 (fcitx5 + Mozc)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [ fcitx5-mozc ];
  };

  services.printing.enable = true;
  # mDNS (.local 名前解決・ネットワークプリンタ自動検出)。
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Bluetooth (キーボード/イヤホン等)。
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # フォント (ghostty/waybar の Nerd Font グリフ + 日本語/絵文字)。
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    hackgen-nf-font # ghostty 設定が前提にする HackGen Console NF
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # --- ユーザー (home-manager は flake 側で接続) ---
  users.users.${user.username} = {
    isNormalUser = true;
    description = user.username;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # SSH は公開鍵のみ (パスワード認証を無効化)。鍵は Bitwarden 管理の方針に合わせる。
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # 指紋認証 (HP ノートの指紋リーダー)。sudo / ログイン / hyprlock の解除に使える。
  # 初回のみ `sudo fprintd-enroll $USER` で指紋を登録する。
  # ※ LUKS 解錠は起動時 (initrd) なので指紋は使えず、パスフレーズ/TPM のまま。
  services.fprintd.enable = true;

  # --- コンテナ (podman: rootless + docker 互換) ---
  # `docker` コマンドは podman の別名として使える (dockerCompat)。
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true; # コンテナ間の名前解決
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    sbctl # Secure Boot 鍵の生成/登録/検証 (lanzaboote 運用に使う)

    # Hyprland を初回から使えるようにする最小セット。
    # 本格的な rice (keybind/waybar 設定/壁紙) は home-manager の
    # wayland.windowManager.hyprland に寄せて、ここからは順次外す想定。
    ghostty # メインターミナル (設定は home/hyprland.nix で symlink)
    kitty # Hyprland 素の SUPER+Q が開くフォールバック (home の $terminal は ghostty)
    wofi # アプリランチャー (SUPER+R 等に割り当て)
    hyprpaper # 壁紙 (waybar/mako は home-manager 管理に移行)
    wl-clipboard # クリップボード (wl-copy / wl-paste)
    cliphist # クリップボード履歴 (wofi と連携)
    hyprpolkitagent # polkit 認証ダイアログ (hyprland 設定で autostart)
    grim # スクリーンショット撮影
    slurp # 範囲選択 (grim と併用)
    brightnessctl # 画面輝度
    playerctl # メディアキー
  ];

  # NTFS の Windows パーティションを読み書きするなら有効化 (任意)
  # boot.supportedFilesystems = [ "ntfs" ];

  # 初回インストールした NixOS のバージョン。一度決めたら変更しない。
  system.stateVersion = "26.05";
}
