{ pkgs, user, ... }:
{
  # ヘッドレス LLM ワーカー (M4 Mac mini / 24GB)。
  # 常用ワークステーション (darwin.nix) と違い GUI cask は一切積まず、
  # Ollama を launchd で常駐させて Tailscale / LAN 越しに推論 API を出すだけの構成。
  imports = [ ./darwin-common.nix ];

  networking = {
    hostName = "macmini";
    computerName = "macmini";
    localHostName = "macmini";
  };

  # ヘッドレス運用なので brew は最小限 (Tailscale の daemon のみ)。
  # GUI cask を積まないことで rebuild が速く・攻撃面も小さい。
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall"; # 宣言外の brew は自動 uninstall
      upgrade = false;
    };
    brews = [
      "tailscale" # tailnet 参加 (認証は初回のみ `sudo tailscale up`)
      # --- ローカル AI スタック (2026-07 追加。cleanup=uninstall で消えるのを防ぐ) ---
      "ffmpeg" # 音声/動画変換 (transcribe/tts/voice-clone/audio-separation の前処理)
      "uv" # Python 環境管理 (mlx_whisper / venv 各種: diarize/sbv2/gsv/sep/rag)
      "aria2" # 大物モデルの self-healing 多重接続 DL (macmini 直 hf-mirror/GitHub)
      "socat" # apple container のホストポート公開バグ回避 (host->containerIP 転送)
      "container" # Apple 純正コンテナランタイム (Open WebUI/AnythingLLM/Minecraft)。
      # 初回のみ runtime 起動+カーネル設定が必要: `container system start` /
      # `container system kernel set --recommended` (宣言不可・手動 or ai-stack.sh)。
    ];
    casks = [
      # ヘッドレス保守用のリモート GUI。SSH で足りない GUI 作業 (権限承認ダイアログ・
      # 初回の自動ログイン設定等) のときだけ使う。無人アクセスの有効化と Screen Recording
      # 権限付与 (TCC) は宣言できないので初回のみ GUI で実施する。
      "rustdesk"
    ];
  };

  # Ollama 本体 (nix パッケージ)。GUI の ollama-app cask は使わない。
  environment.systemPackages = [ pkgs.ollama ];

  # Ollama を LaunchAgent で常駐させる。
  # daemon (root) でなく agent (ログインユーザ) にするのは、Apple Silicon の Metal GPU を
  # 確実に掴ませるため。GUI セッション上で走るので、自動ログインの有効化が前提になる。
  launchd.agents.ollama = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.ollama}/bin/ollama"
        "serve"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/${user.username}/Library/Logs/ollama.log";
      StandardErrorPath = "/Users/${user.username}/Library/Logs/ollama.log";
      EnvironmentVariables = {
        # LAN + tailnet から叩けるよう全 IF で listen。外部公開はしない前提。
        # tailnet 限定に絞りたくなったら 127.0.0.1 に戻して `tailscale serve 11434` で出す。
        OLLAMA_HOST = "0.0.0.0:11434";
        # アイドル 30 分でモデルをアンロード (24GB を空ける)。常駐させたければ "-1"。
        OLLAMA_KEEP_ALIVE = "30m";
      };
    };
  };

  # ヘッドレス運用の下ごしらえ (nix-darwin に型付きオプションが無いので冪等スクリプト)。
  # postActivation は darwin-common が使うので、こちらは preActivation に置いて衝突を避ける。
  system.activationScripts.preActivation.text = ''
    # スリープ抑止: 無人でも推論を受けられるよう寝かせない。
    /usr/bin/pmset -a sleep 0          >/dev/null 2>&1 || true
    /usr/bin/pmset -a disablesleep 1   >/dev/null 2>&1 || true
    # Remote Login (SSH) を有効化。鍵認証は既存の運用 (Bitwarden agent 等) をそのまま使う。
    /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1 || true
  '';
}
