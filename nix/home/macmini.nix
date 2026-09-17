{
  config,
  lib,
  nixpkgsAgents,
  pkgs,
  ...
}:
let
  agentPkgs = nixpkgsAgents.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  # Place the AI stack's runtime assets via out-of-store symlinks with dotfiles as the single source.
  # Editing directly on the mini is reflected straight into the repo (same mechanism as nvim).
  aiService = name: {
    ".local/share/ai-stack/${name}".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/services/${name}";
  };
  aiWrapper = name: {
    ".local/bin/${name}".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/bin/${name}";
  };
in
{
  imports = [
    ../modules/home/darwin-agent-state-sync.nix
    ../modules/home/agy.nix
  ];

  # macmini-specific layer. The base CLI/zsh/XDG set inherits home/common.nix
  # composed on the flake side (no sops/age keys are brought in).
  # Layout follows XDG/ghq (the dedicated ~/ai was retired 2026-07-19):
  #   service bodies -> ~/.local/share/ai-stack/ (HM symlink)
  #   venvs -> ~/.local/share/venvs/, models -> ~/.local/share/models/
  #   (no app data here anymore: the web frontends moved to homeserver, minecraft to its own user)
  #   ComfyUI / GPT-SoVITS -> ~/Developer/github.com/<owner>/<repo> (ghq style)
  #   own projects with no upstream -> ~/Developer/projects/<name>
  #     (~/ai grew two of these back after the retirement; moved out 2026-08-12)
  # venvs/models/data are non-reproducible assets, so they're managed imperatively
  # (rebuild steps in configs/macmini/bootstrap.sh and README).

  home.packages = [
    # Orca starts agent CLIs from its Aqua LaunchAgent instead of an interactive shell.
    # Keep Codex declarative on the remote host so it is both discoverable and available
    # after unattended rebuilds.
    agentPkgs.codex
    agentPkgs.opencode

    # The study tutor renders plans and handouts with typst (show.py in the sandbox looks it
    # up under /nix/store). Declared here so a garbage collection can't take it away.
    pkgs.typst

    # Hermes's sandbox file-sync needs GNU tar (--no-overwrite-dir), and search
    # needs ripgrep. The sandbox symlinks ~/.local/bin/{tar,rg} at the stable
    # /etc/profiles path; without a declaration a GC severs them and the tutor
    # silently stops reading files (happened three times in one week).
    pkgs.gnutar
    pkgs.ripgrep

    # Sunshine — Moonlight のホスト側。iPhone / iPad からこの機械の画面を触る。
    #
    # macOS ホストは公式に experimental で、**ゲームパッドが動かない**
    # ("Gamepads do not work" と docs に明記されている)。キーボードとマウスの
    # ゲーム、エミュレータ、あるいは単に遠隔から画面を触る用途なら使える。
    # パッドを使うなら Windows 側を起こすほうが早い。
    #
    # 画面収録とアクセシビリティの許可は launchd では与えられないので、
    # 初回だけ手で通す (下の launchd.agents.sunshine の注記を参照)。
    pkgs.sunshine

    # ccm: default Claude Code launch form on the mac mini. This deliberately bypasses
    # permission prompts, so only use it when the active session is trusted.
    (pkgs.writeShellScriptBin "ccm" ''
      exec "$HOME/.local/bin/claude" \
        --dangerously-skip-permissions \
        --remote-control dotfiles \
        --continue \
        --add-dir "$HOME/.dotfiles" \
        "$@"
    '')
  ];

  # Claude Code on the mini gets the workstation's managed keys (bypassPermissions as the default
  # mode, theme, effort, ...) from settings.remote.json, the same merge remote-bootstrap applies over
  # nssh. Merged rather than linked: hooks and plugins stay host-owned, and Orca and the TUI rewrite
  # this file in place (configs/cli/claude/README.md). An unparsable file is reported and left alone
  # rather than failing an unattended switch.
  home.activation.claudeManagedSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 ${../../scripts/merge-claude-settings.py} \
      "${config.xdg.configHome}/claude/settings.json" \
      --managed ${../../configs/cli/claude/settings.remote.json} \
      || echo "warning: Claude settings merge failed; left untouched" >&2
  '';

  # launchd does not create the parent of StandardOutPath, and the dashboard agent's log moved out
  # of the (now deleted) project directory into XDG state.
  home.activation.manabiStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /bin/mkdir -p "${config.home.homeDirectory}/.local/state/manabi"
  '';

  # auto-fix パイプライン (GitHub issue → macmini の Claude Code → PR → CI → 自動マージ) が
  # 生きているかを1時間ごとに確かめる。監視対象と同じ GitHub Actions では回さない、という
  # 判断はスクリプト側の冒頭に書いてある。
  #
  # 元は手書きの plist と $HOME/autofix-monitor のスクリプトだった。中身は変えずに store へ
  # 移し、状態(ログと Claude の出力)だけ XDG の state 配下に分けている。
  #
  # Lives in home-manager, not nix-darwin's launchd.agents: activated over ssh, nix-darwin
  # loads /Library/LaunchAgents into the system domain as root (claude refuses to run, and
  # the logs turned root-owned, which then broke the real agent with EX_CONFIG) and never
  # reloads the copy in the login session, so it kept running the old script.
  launchd.agents.autofix-monitor = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "${../../configs/macmini/autofix-monitor/monitor.sh}"
      ];
      RunAtLoad = true;
      StartInterval = 3600;
      StandardOutPath = "${config.home.homeDirectory}/.local/state/autofix-monitor/stdout.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/autofix-monitor/stderr.log";
      EnvironmentVariables = {
        # launchd から起動されるとシェルの環境が入らないので、スクリプトが要る分だけ渡す。
        HOME = config.home.homeDirectory;
        XDG_STATE_HOME = "${config.home.homeDirectory}/.local/state";
      };
    };
  };

  # glances, the box's own metrics endpoint (the homelab dashboard scrapes it). Was a hand-written
  # plist; same spec, just declared. Bound to 0.0.0.0 because the scrape comes from the homeserver,
  # and the machine is only reachable over the tailnet anyway.
  launchd.agents.glances = {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.homeDirectory}/.local/bin/glances"
        "-w"
        "--bind"
        "0.0.0.0"
        "--port"
        "61208"
        "-t"
        "5"
        "--disable-webui"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      # Tier: a metrics collector should never win against the things it measures.
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/tmp/glances.log";
      StandardErrorPath = "/tmp/glances.log";
    };
  };

  # Keep a Claude Code Remote Control server registered for the Claude mobile/web apps.
  # It only opens outbound HTTPS connections to Anthropic; no inbound port is exposed.
  # DO_NOT_TRACK remains the global default, but Remote Control requires feature-flag
  # evaluation, so remove it only from this process. Start from the user's home so the
  # remote session can operate across the macmini instead of being tied to one checkout.
  # The remote-control subcommand expresses --dangerously-skip-permissions as the
  # equivalent bypassPermissions mode for every spawned session.
  launchd.agents.claude-remote-control = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "claude-remote-control" ''
          unset DO_NOT_TRACK DISABLE_TELEMETRY CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC DISABLE_GROWTHBOOK
          export PATH="$HOME/.local/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
          cd "$HOME"
          exec "$HOME/.local/bin/claude" remote-control \
            --name "macmini" \
            --spawn same-dir \
            --capacity 4 \
            --permission-mode bypassPermissions
        ''}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      ProcessType = "Standard";
      LowPriorityIO = true;
      Nice = 5;
      StandardOutPath = "/tmp/claude-remote-control.log";
      StandardErrorPath = "/tmp/claude-remote-control.log";
    };
  };

  # Orca recommends its desktop host on a Mac mini. Launch it inside the Aqua login
  # session so macOS Keychain and LaunchServices are available; the headless `orca
  # serve` path can deadlock in Electron startup on macOS 26. Remote sharing itself
  # is enabled once in Settings -> Remote Orca Servers and persists in Orca's state.
  launchd.agents.orca-desktop-server = {
    enable = true;
    config = {
      ProgramArguments = [
        "/Applications/Orca.app/Contents/MacOS/Orca"
      ];
      EnvironmentVariables = {
        PATH = "${config.home.profileDirectory}/bin:/Users/gapul/.local/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
        CODEX_HOME = "${config.xdg.dataHome}/codex";
        CODEX_SQLITE_HOME = "${config.xdg.stateHome}/codex/sqlite";
        XDG_CONFIG_HOME = "${config.xdg.configHome}";
        # Orca's bundled agent-browser picks a browser by walking /Applications in the order
        # Google Chrome, Chrome Canary, Chromium, Brave. Helium matches none of those names, so
        # this pin is what makes it the target at all — and it also keeps a Chrome that some
        # installer drops back in from quietly taking the job over again.
        AGENT_BROWSER_EXECUTABLE_PATH = "/Applications/Helium.app/Contents/MacOS/Helium";
      };
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      ProcessType = "Standard";
      LowPriorityIO = true;
      Nice = 5;
      LimitLoadToSessionType = "Aqua";
      StandardOutPath = "/tmp/orca-desktop-server.log";
      StandardErrorPath = "/tmp/orca-desktop-server.log";
    };
  };

  # Orca toggles its macOS login-item registration when the desktop process exits. On this
  # unattended host that can leave the declarative Home Manager agent disabled, which also
  # drops paired mobile and desktop clients. Re-enable and bootstrap only when the service is
  # absent; the normal KeepAlive policy handles ordinary process restarts.
  launchd.agents.orca-server-watchdog = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "orca-server-watchdog" ''
          domain="gui/$(${pkgs.coreutils}/bin/id -u)"
          label="org.nix-community.home.orca-desktop-server"
          plist="$HOME/Library/LaunchAgents/$label.plist"

          if ! /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
            /bin/launchctl enable "$domain/$label"
            /bin/launchctl bootstrap "$domain" "$plist" 2>/dev/null || true
          fi
        ''}"
      ];
      RunAtLoad = true;
      StartInterval = 60;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/tmp/orca-server-watchdog.log";
      StandardErrorPath = "/tmp/orca-server-watchdog.log";
    };
  };

  # Orca's browser client needs a secure context (`crypto.randomUUID` is unavailable on
  # plain HTTP). Keep a tailnet-only HTTPS/WSS reverse proxy in front of the desktop
  # server so iPhone Safari can load the UI and its encrypted WebSocket transport.
  launchd.agents.orca-tailscale-serve = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "orca-tailscale-serve" ''
          tailscale=/opt/homebrew/bin/tailscale
          if [ -x "$tailscale" ]; then
            "$tailscale" serve --bg --https=443 http://127.0.0.1:6768
          fi
        ''}"
      ];
      RunAtLoad = true;
      StartInterval = 300;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/tmp/orca-tailscale-serve.log";
      StandardErrorPath = "/tmp/orca-tailscale-serve.log";
    };
  };

  # geekfeed: ギーク情報と学生向け無料キャンペーンを毎朝集めて RSS/ICS を作り、push すると
  # Cloudflare Pages (geekfeed.pages.dev) が公開する。収集の実体は ~/Developer 側のリポジトリで、
  # ここで宣言するのは時刻だけ。--research は claude -p にウェブ調査させる分なので1日1回に留める。
  # git と gh は nix プロファイル側にいるため、PATH は publish.sh が自前で組み立てる。
  launchd.agents.geekfeed = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "geekfeed" ''
          repo="$HOME/Developer/github.com/gapul/geekfeed"
          [ -x "$repo/publish.sh" ] || exit 0
          exec "$repo/publish.sh" --research
        ''}"
      ];
      StartCalendarInterval = [
        {
          Hour = 7;
          Minute = 30;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/tmp/geekfeed.log";
      StandardErrorPath = "/tmp/geekfeed.log";
    };
  };

  # Hand-written agents the declarations above replace, plus one leftover that was already
  # disabled. Same shape as the workstation's retiredLaunchAgents list.
  home.activation.retiredMacminiAgents = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for f in net.gapul.glances.plist com.gapul.mopidy-auto.plist.disabled; do
      legacy="$HOME/Library/LaunchAgents/$f"
      if [ -e "$legacy" ]; then
        run /bin/launchctl bootout "gui/$(id -u)/''${f%.plist}" 2>/dev/null || true
        run rm -f "$legacy"
      fi
    done
  '';

  # Zaim → SQLite → Beancount ledger (personal-tools/zaim), plus Fava to read it.
  #
  # Hourly because the request is also what keeps the Zaim web session alive: the `_y` cookie
  # expires two hours after the last request (measured 2026-09-15; the value never changes and
  # isn't tied to an IP). Each run re-fetches the last 60 days so recategorised transactions
  # follow, regenerates zaim.beancount, runs bean-check, and commits the ledger repo when it
  # changed. The ledger lives under ~/Developer so restic already covers it (zaim.db included,
  # it's only gitignored). The cookie is logged in on the workstation and copied to
  # ~/.cache/zaim/cookie. ntfy fires once per distinct failure, not every hour.
  launchd.agents.zaim-sync = import ../lib/launchd-agent.nix {
    program = "${pkgs.writeShellScript "zaim-sync" ''
      tools="$HOME/Developer/github.com/gapul/personal-tools/zaim"
      ledger="$HOME/Developer/github.com/gapul/ledger"
      [ -f "$tools/zaim_web.py" ] && [ -f "$ledger/main.beancount" ] || exit 0
      state="$HOME/.local/state/zaim"
      mkdir -p "$state"
      py=${pkgs.python3}/bin/python3
      git="${pkgs.git}/bin/git -C $ledger"

      fail() {
        [ "$(cat "$state/failed" 2>/dev/null)" = "$1" ] && exit 1
        printf '%s' "$1" > "$state/failed"
        url="$HOME/.config/ntfy/url"
        tok="$HOME/.config/ntfy/token"
        [ -r "$url" ] && [ -r "$tok" ] || exit 1
        /usr/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $(cat "$tok")" \
          -H "Title: Zaim ledger (macmini)" \
          -H "Tags: warning" \
          -d "$1" "$(cat "$url")" >/dev/null 2>&1 || true
        exit 1
      }

      out=$($py "$tools/zaim_web.py" sync --db "$ledger/zaim.db" 2>&1) ||
        fail "同期に失敗: $out (Cookie切れなら母艦で zaim_web.py login → scp ~/.cache/zaim/cookie macmini:.cache/zaim/cookie)"
      out=$($py "$tools/zaim_beancount.py" --db "$ledger/zaim.db" --rules "$ledger/rules.toml" \
        --out "$ledger/zaim.beancount" 2>&1) || fail "帳簿の生成に失敗: $out"
      out=$(${pkgs.beancount}/bin/bean-check "$ledger/main.beancount" 2>&1) || fail "bean-check: $out"
      rm -f "$state/failed"
      if [ -n "$($git status --porcelain)" ]; then
        $git add -A && $git commit -q -m "zaim sync $(date +%F\ %H:%M)"
      fi
    ''}";
    schedule = [ { Minute = 17; } ];
  };

  # Fava for the ledger, tailnet-only HTTPS on :5075 via tailscale serve (same approach as Orca).
  # Fava reloads the files itself when zaim-sync rewrites them.
  launchd.agents.fava = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "fava" ''
          ledger="$HOME/Developer/github.com/gapul/ledger/main.beancount"
          if [ ! -f "$ledger" ]; then
            sleep 600
            exit 0
          fi
          [ -x /opt/homebrew/bin/tailscale ] &&
            /opt/homebrew/bin/tailscale serve --bg --https=5075 http://127.0.0.1:5075 >/dev/null 2>&1
          exec ${pkgs.fava}/bin/fava --host 127.0.0.1 --port 5075 "$ledger"
        ''}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      Nice = 10;
      StandardOutPath = "/tmp/fava.log";
      StandardErrorPath = "/tmp/fava.log";
    };
  };

  # OCR for Paperless (homeserver) done by Apple Vision here instead of tesseract there.
  # personal-tools/vision-ocr is a small Azure AI Document Intelligence look-alike, which is the
  # only remote OCR engine Paperless 3 speaks. Vision reads Japanese receipts that tesseract
  # garbles (compared on the same scan 2026-09-15). The CLI links Vision/PDFKit, so it is built
  # with Xcode's swiftc, not nix; the wrapper rebuilds it whenever the source is newer. Exposed
  # tailnet-only on :8930 through tailscale serve, like Fava and Orca.
  launchd.agents.vision-ocr = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "vision-ocr" ''
          src="$HOME/Developer/github.com/gapul/personal-tools/vision-ocr"
          bin="$HOME/.local/share/vision-ocr/vision-ocr"
          if [ ! -f "$src/server.py" ]; then
            sleep 600
            exit 0
          fi
          if [ ! -x "$bin" ] || [ "$src/vision-ocr.swift" -nt "$bin" ]; then
            mkdir -p "$(dirname "$bin")"
            /usr/bin/xcrun swiftc -O "$src/vision-ocr.swift" -o "$bin" || {
              sleep 60
              exit 1
            }
          fi
          [ -x /opt/homebrew/bin/tailscale ] &&
            /opt/homebrew/bin/tailscale serve --bg --https=8930 http://127.0.0.1:8930 >/dev/null 2>&1
          export VISION_OCR_BIN="$bin"
          export VISION_OCR_PUBLIC_URL=https://macmini.tail079f44.ts.net:8930
          exec ${pkgs.python3}/bin/python3 "$src/server.py" --port 8930
        ''}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/tmp/vision-ocr.log";
      StandardErrorPath = "/tmp/vision-ocr.log";
    };
  };

  # Nightly `git pull` on the checkout. The post-merge hook is what actually rebuilds; this only
  # exists because nothing was ever pulling here, so a merged flake.lock sat in GitHub while the
  # machine kept running last month's generation.
  #
  # It refuses to touch a dirty tree (this is the main tree, and work happens in worktrees) and
  # notifies through the same ntfy files restic uses — there is no screen to put a dialog on.
  launchd.agents.dotfiles-pull = import ../lib/launchd-agent.nix {
    program = "${pkgs.writeShellScript "dotfiles-pull" ''
      export PATH="${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      repo="$HOME/.dotfiles"
      notify() {
        url="$HOME/.config/ntfy/url"
        tok="$HOME/.config/ntfy/token"
        [ -r "$url" ] && [ -r "$tok" ] || return 0
        /usr/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $(cat "$tok")" \
          -H "Title: dotfiles (macmini)" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -d "$1" "$(cat "$url")" >/dev/null 2>&1 || true
      }
      cd "$repo" || exit 0
      if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        notify "作業ツリーが汚れているので pull を見送った"
        exit 0
      fi
      git fetch --quiet origin main || { notify "fetch に失敗"; exit 1; }
      if git merge-base --is-ancestor origin/main HEAD; then
        exit 0
      fi
      # pull の中で post-merge フックが just rebuild まで走る。
      if ! git pull --ff-only --quiet; then
        notify "pull / rebuild に失敗"
        exit 1
      fi
    ''}";
    schedule = [
      {
        Hour = 5;
        Minute = 30;
      }
    ];
  };

  # brew shellenv (here because the headless mini doesn't load home/darwin.nix) +
  # machine-local secrets (HF_TOKEN etc.) are read from local.zsh outside nix management.
  programs.zsh.initContent = lib.mkAfter ''
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    [ -f "$HOME/.config/zsh/local.zsh" ] && source "$HOME/.config/zsh/local.zsh"
  '';

  # Which flake attribute this machine is. `just rebuild` otherwise falls back to the
  # username, which names the workstation config — and both Macs report the same
  # LocalHostName, so there is nothing else to tell them apart.
  xdg.configFile."dotfiles/host".text = "macmini\n";

  # AI stack runtime assets (bodies in configs/macmini/{services,bin})
  home.file = lib.mkMerge (
    map aiService [
      "ai-stack.sh"
      "ai_panel.py"
      "diarize_merge.py"
      "fish_voicevox_shim.py"
      "llm_ask.py"
      "rag_server.py"
      "sbv2_tts.py"
    ]
    ++ map aiWrapper [
      "agy"
      "ask"
      "describe"
      "fish-voicevox"
      "ocr"
      "separate"
      "transcribe"
      "transcribe-diarize"
      "tts"
      "voice-clone"
    ]
    ++ [
      # The workstation's broker sends approved native credentials to this fixed remote helper.
      { ".local/bin/ask-native-fill".source = ../../configs/ask/native_fill.py; }
    ]
  );

  # A VOICEVOX-compatible front for Fish S2 Pro (mlx-speech), so anything that already speaks the
  # VOICEVOX API can use it by pointing at this port — presenta's video worker does, see
  # hosts/macmini-presenta.nix. Speech falls back to the AivisSpeech engine above when Fish fails
  # or would take longer than the caller waits, so a slow model never costs us a video.
  #
  # Fish S2 Pro's weights are under the Fish Audio Research License: research, personal and
  # evaluation use only. Serving presenta.gapul.net from it is a commercial use in that licence's
  # terms and needs a separate agreement with Fish Audio.
  #
  # The model (6.3GB) and the venv are imperative assets like the rest of the AI stack, see
  # configs/macmini/README.md.
  launchd.agents.fish-voicevox = {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.homeDirectory}/.local/bin/fish-voicevox"
        "--port"
        "10202"
        # The caller (workers/video/voicevox.ts) gives up after 120s per chunk. Stay under it.
        "--budget-seconds"
        "90"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/tmp/fish-voicevox.log";
      StandardErrorPath = "/tmp/fish-voicevox.log";
    };
  };

  # AI stack resident (replaces the old hand-written net.gapul.* plists. 2026-07-19)
  launchd.agents.ai-stack = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/bash"
        "${config.home.homeDirectory}/.local/share/ai-stack/ai-stack.sh"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/ai-stack.log";
      StandardErrorPath = "/tmp/ai-stack.log";
    };
  };
  # Rebuilds the study dashboard and deploys it to Cloudflare Pages every 15 minutes.
  # Replaces the last hand-written net.gapul.* plist (2026-08-12). The script stays out
  # of the store on purpose: its own directory is the wrangler deploy root, so it writes
  # the generated index.html and media/ next to its source.
  launchd.agents.manabi-dashboard-refresh = {
    enable = true;
    config = {
      ProgramArguments = [
        "/Users/Shared/manabi/dashboard/update-dashboard.sh"
      ];
      StartInterval = 900;
      # The deploy pulls from a sandbox user over ssh; letting it fire during login while
      # the rest of the stack is still coming up just logs a failure.
      RunAtLoad = false;
      # Batch: nobody is waiting on it, and it runs every 15 minutes.
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "${config.home.homeDirectory}/.local/state/manabi/refresh.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/manabi/refresh.log";
    };
  };
  # Sunshine を常駐させる。Moonlight (iOS の無料アプリ) がこの機械を見つけて
  # 繋ぎに来る。
  #
  # 初回だけ手が要る。どちらも TCC の許可で、宣言では与えられない:
  #   1. システム設定 > プライバシーとセキュリティ > 画面収録 に sunshine を追加
  #   2. 同 > アクセシビリティ にも追加 (キーボード/マウスの注入に要る)
  # 許可を与えたあと `launchctl kickstart -k gui/$UID/org.nix-community.home.sunshine`。
  #
  # ペアリングは https://localhost:47990 の Web UI から。ポートは tailnet 内だけに
  # 開いていて、外には出していない。
  # 画面収録の許可を sunshine の更新で失わないようにする。
  #
  # TCC は許可をバイナリの場所と署名で識別する。nix の store を直接指すと、
  # 更新のたびに別物になって許可が切れる。しかも画面収録は MDM でも無言に
  # 付与できないので、切れるたびに画面共有で入って押し直すことになる。
  #
  # 自己署名の identity で署名すると要件式から cdhash が落ち、identifier と
  # 証明書だけになる。中身が変わっても同じものとみなされる (実測で確認)。
  #
  # identity は機械ごとに一度 `tcc-signing-identity` を走らせて作る (sudo が
  # 要るので activation からは呼ばない)。無い間はここは何もしない。
  home.activation.tccStableSunshine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${../../configs/bin/tcc-stable-binary} \
      ${pkgs.sunshine}/bin/sunshine sunshine || true
  '';

  launchd.agents.sunshine = {
    enable = true;
    config = {
      # store のパスではなく署名済みの安定した場所を指す。TCC は許可を場所と
      # 署名で識別するので、store を直接指すと sunshine を更新するたびに
      # 画面収録の許可が切れる。詳しくは下の activation を参照。
      ProgramArguments = [ "${config.home.homeDirectory}/.local/libexec/tcc/sunshine" ];
      RunAtLoad = true;
      KeepAlive = true;
      # 配信中に他のバックグラウンド仕事に負けると映像が途切れる。ComfyUI と
      # 同じ Interactive にしておく。
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/sunshine.log";
      StandardErrorPath = "/tmp/sunshine.log";
    };
  };

  launchd.agents.comfyui = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/bash"
        "${config.home.homeDirectory}/Developer/github.com/comfyanonymous/ComfyUI/run-comfy.sh"
      ];
      WorkingDirectory = "${config.home.homeDirectory}/Developer/github.com/comfyanonymous/ComfyUI";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/comfyui.log";
      StandardErrorPath = "/tmp/comfyui.log";
    };
  };
}
