{
  lib,
  pkgs,
  user,
  claudeAcp,
  nixpkgsAgents,
  sopsNix,
  ...
}:
let
  fastPkgs = import ../lib/unstable-pkgs.nix {
    nixpkgsUnstable = nixpkgsAgents;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  fabricServer = pkgs.callPackage ../pkgs/fabric-server.nix { };
  geyser = pkgs.callPackage ../pkgs/geyser.nix { };
  fabricMods = import ../pkgs/fabric-mods.nix { inherit (pkgs) fetchurl; };
  aivisSpeechEngine = pkgs.callPackage ../pkgs/aivisspeech-engine.nix { };

  # Both Minecraft servers run the same Fabric build with the same server-side mods, so a plain
  # launcher joins either one. Fabric replaced Paper on 2026-09-26: the game version can move the
  # day Mojang ships (Paper's stable builds trail by weeks), the optimisation mods match Paper's
  # performance, and nothing here depends on a Bukkit plugin any more. Anything that would need a
  # client mod does not go on these servers; a modpack world is a separate, temporary instance.
  #
  # version/protocol are what lazymc reports while the server sleeps. The protocol number is not
  # in Fabric's API, so scripts/update-custom-packages.sh looks it up and rewrites both here.
  inherit (fabricServer) mcVersion;
  mcProtocol = 777;
  fabricInstance =
    extra:
    {
      java = pkgs.temurin-bin-25;
      memory = "2G";
      version = mcVersion;
      protocol = mcProtocol;
      runner = ../../configs/macmini/minecraft/run.sh;
      env = {
        SERVER_JAR = "${fabricServer}";
        MODS = lib.concatStringsSep " " (map toString fabricMods);
      }
      // (extra.env or { });
    }
    // builtins.removeAttrs extra [ "env" ];

  minecraftServers = {
    # 友人と遊ぶ本館。
    vanilla = fabricInstance {
      dir = "/Users/mcsrv/vanilla";
      port = 25565;
    };
    # 自分ひとり用。本館と同じもので、入れる人と寝るまでの時間だけ違う。
    solo = fabricInstance {
      dir = "/Users/mcsrv/solo";
      port = 25566;
      sleepAfter = 3600;
      env.WHITELIST_SRC = "/etc/minecraft/whitelist-solo.json";
    };
  };

  # 無人のあいだサーバーを止めておくための前段。公開ポートは lazymc が持ち、本体は loopback の
  # 別ポートで動く。誰も居なければ本体はプロセスごと落ちているので CPU もメモリもゼロ、接続が
  # 来たら起こして繋ぐ(その間クライアントには「起動中」と見える)。playit の転送先も lazymc。
  #
  # コンテナ時代に試した ENABLE_AUTOPAUSE は knockd がゲストの eth0 に attach できず動かなかった。
  # lazymc はホスト側で port を持つだけなので、その問題が無い。
  lazymcConfig =
    name: inst:
    pkgs.writeText "lazymc-${name}.toml" ''
      [public]
      address = "0.0.0.0:${toString inst.port}"
      # 寝ている間の status 応答に使う版。実際の互換性とは関係が無いが、ずれていると
      # サーバー一覧に赤い×が出る。本体を上げたら表の version/protocol も合わせる。
      version = "${inst.version}"
      protocol = ${toString inst.protocol}

      [server]
      # +100 なのは、+10 だと本館の 25575 が rcon の既定ポートと重なるため。rcon を有効に
      # した日に「bind できない」で悩むことになる。
      address = "127.0.0.1:${toString (inst.port + 100)}"
      directory = "${inst.dir}"
      command = "${inst.runner}"
      # server.properties の server-port を lazymc が書き換える。手で合わせると必ずずれる。
      wake_on_start = false
      wake_on_crash = false
      # 既定は「止める」ではなく「凍らせる」(SIGSTOP)。復帰は速いが 1.2GB を握ったままなので、
      # 2本立てると待機だけで 2.4GB 持っていかれる——24GB を AI スタックと分け合う機械では損。
      # 起動は実測 4〜5 秒なので、素直に落とす。凍ったまま lazymc が死ぬと世界のロックを
      # 掴んだまま残る、という厄介な壊れ方も無くなる。
      freeze_process = false

      [time]
      # 10分無人で停止。起動は4秒弱なので、待たされる感覚はほぼ無い。
      sleep_after = ${toString (inst.sleepAfter or 600)}
      minimum_online_time = 60

      [motd]
      sleeping = "§7ねむっています §8(入れば起きます)"
      starting = "§e起動中… §8数秒お待ちください"
      stopping = "§c停止中…"

      [advanced]
      rewrite_server_properties = true
    '';
  # まなびはサービスなので、実体は gapul/manabi (private) にあり、この機械にはそのクローンが
  # 置いてある。ここが持つのは「この機械がまなびを動かす」という宣言だけで、中身は向こうの
  # 更新に追従する (dotfiles の rebuild は要らない)。private なので flake input にはできない
  # ——CI が fetch できない——から、パスで参照する。
  manabi = "/Users/Shared/manabi";
in
{
  # Headless AI/render worker (M4 Mac mini / 24GB). GUI casks are limited to software that
  # provides a server-side capability: browser automation, Blender rendering, and Adobe's
  # After Effects installer/runtime. Everyday interactive apps stay on the workstation.

  # sops at the system level, decrypting with this machine's own SSH host key.
  #
  # This host used to carry no sops at all, on the deliberate policy of not copying the human age
  # master key here — that one key opens every secret in the repo, and a headless box that nobody
  # watches is the worst place to leave it. The cost was that restic's password and the ntfy
  # credentials lived as hand-placed files outside the declaration.
  #
  # Host-key decryption removes the tradeoff: /etc/ssh/ssh_host_ed25519_key already exists here,
  # never leaves the machine, and its age recipient is in .sops.yaml for secrets/common.yaml only.
  # So the mini can open what it needs and nothing else, and no key had to be brought over.
  # This runs as root during activation, which is why it works here and not in home-manager
  # (that key is 0600 root:wheel).
  sops = {
    defaultSopsFile = ../../secrets/common.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets =
      let
        # The backup runs as the login user, not root, so hand ownership over explicitly.
        forUser = path: {
          inherit path;
          owner = user.username;
          mode = "0400";
        };
      in
      {
        # Was ~/.config/restic/password, placed by hand. restic-common.nix's default path is the
        # same location, so the module below keeps reading it without knowing it moved.
        "restic_password" = forUser "/Users/${user.username}/.config/restic/password";
        # For headless Claude Code. There is no interactive login on this machine and
        # the keychain cannot be opened over SSH, so the OAuth token minted by
        # `claude setup-token` is handed over as a file. claude-agent
        # (nix/home/macmini-claude-agent.nix) reads it as CLAUDE_CODE_OAUTH_TOKEN.
        "claude_code_oauth_token" = forUser "/Users/${user.username}/.config/claude/oauth-token";
        # マイクラの参加者一覧。名前と UUID は本人たちのもので、公開リポジトリに平文で置く
        # ものではないので暗号化したまま持つ。置き場所は 1 か所で、起動時に run.sh が各
        # インスタンスへ配る (サーバーは自分でこのファイルを書き換えるため、宣言側を毎回勝たせる)。
        "minecraft/whitelist" = {
          path = "/etc/minecraft/whitelist.json";
          owner = "mcsrv";
          mode = "0444";
        };
        # 個人用だけ別の一覧にする。ひとり用の世界に友人まで入れる必要は無い。
        "minecraft/whitelist_solo" = {
          path = "/etc/minecraft/whitelist-solo.json";
          owner = "mcsrv";
          mode = "0444";
        };
        # Floodgate の鍵 (16 byte の AES 鍵を base64 で)。Bedrock の人は Java の認証を通らず、
        # この鍵で署名された Geyser からの接続だけが通る。漏れると誰でも任意の名前で入れる。
        # サーバー側 (run.sh) と Geyser 側 (下の daemon) の両方が起動時にここから置き直す。
        "minecraft/floodgate_key" = {
          path = "/etc/minecraft/floodgate-key.b64";
          owner = "mcsrv";
          mode = "0400";
        };
        "minecraft/ops" = {
          path = "/etc/minecraft/ops.json";
          owner = "mcsrv";
          mode = "0444";
        };
        "unified_calendar/ntfy_url" = forUser "/Users/${user.username}/.config/ntfy/url";
        "unified_calendar/ntfy_token" = forUser "/Users/${user.username}/.config/ntfy/token";
      };
  };
  imports = [
    ./darwin-common.nix
    ../modules/authorized-keys.nix
    ./macmini-ci-runner.nix
    ./macmini-dns.nix
    ./macmini-homeserver-monitor.nix
    ./macmini-presenta.nix
    sopsNix.darwinModules.sops
    # マイクラのサーバーは上の表から生やす。別モジュールにしてあるのは、nix が同じ attrset の
    # 中で `launchd.daemons = {...}` と `launchd.daemons.foo = ...` を混ぜられないため。
    # サーバーを増やすときに触るのは minecraftServers だけで、ここは触らなくていい。
    {
      launchd.daemons = lib.mapAttrs' (
        name: inst:
        lib.nameValuePair "minecraft-${name}" {
          # `command` (not ProgramArguments) makes nix-darwin prepend `wait4path /nix/store`. Since
          # macOS 27 /nix mounts after launchd starts daemons; a missing store binary exits 78
          # (EX_CONFIG) and never retries on its own — only bootout/bootstrap brought it back.
          # 常駐するのは lazymc。サーバー本体は接続が来たときに lazymc が起こす。
          # lazymc は起こす前に <dir>/whitelist.json を自分で読んで弾く (wake_whitelist)。
          # そのファイルを正 (/etc/minecraft) に揃えるのは run.sh だが、run.sh は本体の起動時
          # にしか走らない。つまり一覧を直しても、本体が一度も起きないと古い一覧で弾かれ続ける
          # (2026-09-23、綴りを直したのに翌日も入れなかった)。lazymc が読む前にここでも揃える。
          command = lib.escapeShellArgs [
            "${pkgs.writeShellScript "lazymc-${name}" ''
              wl="''${WHITELIST_SRC:-/etc/minecraft/whitelist.json}"
              [ -f "$wl" ] && /bin/cp -f "$wl" "${inst.dir}/whitelist.json"
              exec ${pkgs.lazymc}/bin/lazymc -c ${lazymcConfig name inst} start
            ''}"
          ];
          serviceConfig = {
            EnvironmentVariables = {
              SERVER_DIR = inst.dir;
              SERVER_MEM = inst.memory;
              JAVA_BIN = "${inst.java}/bin/java";
            }
            // inst.env;
            UserName = "mcsrv";
            WorkingDirectory = inst.dir;
            # Tier 1: tick latency is the thing players feel.
            ProcessType = "Interactive";
            RunAtLoad = true;
            KeepAlive = true;
            StandardOutPath = "${inst.dir}/logs/launchd.log";
            StandardErrorPath = "${inst.dir}/logs/launchd.log";
          };
        }
      ) minecraftServers;
    }
  ];

  networking = {
    hostName = "macmini";
    computerName = "macmini";
    localHostName = "macmini";
  };

  # Headless operation, so brew stays limited to daemons and server-side GUI runtimes.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall"; # undeclared brews are auto-uninstalled
      upgrade = false;
    };
    taps = [
      "stablyai/orca" # Orca ADE Remote Server and bundled CLI
    ];
    # Same priority rule as hosts/darwin.nix: nix > homebrew > everything else, and each formula
    # states why brew owns it. (uv was dropped here — modules/home/packages.nix already installs it,
    # and brew winning the PATH meant the duplicate was invisible. ffmpeg and aria2 followed on
    # 2026-08-13, which also sweeps the twenty dependency formulae they had dragged in.)
    brews = [
      # The tailnet daemon. Stays on brew: the running daemon holds this node's identity, and
      # swapping the implementation under it buys nothing. Auth happened once via `sudo tailscale up`.
      "tailscale"
    ];
    casks = [
      {
        name = "stablyai/orca/orca";
        args = {
          # This is a signed and notarized build, but quarantine makes the headless CLI wait
          # indefinitely in dyld while syspolicyd's online check times out on this host.
          no_quarantine = true;
        };
      } # bundled CLI runs the persistent Remote Orca Server below
      # (RustDesk was here for remote GUI. It never got its unattended access or its Screen
      #  Recording grant, so it had never once been used, while macOS Screen Sharing on :5900
      #  already covers the same job over the tailnet with nothing to install.)
      # Helium for agent-driven browsing, replacing google-chrome (2026-09-11). Both reasons
      # the Chrome line used to give had expired: the resident Playwright MCP was deleted in
      # #561, and login fills moved to the Safari native helper. What actually kept Chrome in
      # service was Orca's bundled agent-browser, which resolves a browser by walking
      # /Applications on its own, and Google's build happens to sit first in that order.
      #
      # Helium is the ungoogled-chromium build the workstation already treats as its Chromium
      # of record, so both hosts now drive the same browser. agent-browser's search list only
      # knows Chrome, Chrome Canary, Chromium and Brave, so it cannot find Helium on its own —
      # the pin lives in AGENT_BROWSER_EXECUTABLE_PATH on the Orca agent (home/macmini.nix),
      # which is also where that ordering stops mattering.
      #
      # No no_quarantine, unlike Orca above: it is notarized (Developer ID: imput LLC), spctl
      # accepts it, and it launched headlessly on this host with the quarantine attribute still
      # attached. The cask is auto_updates, so the app owns its own updates.
      "helium-browser"
      # Creative Cloud is the supported installer and license runtime for After Effects. Adobe
      # manages AE itself after this bootstrap, but declaring the CC installer keeps brew's
      # cleanup=uninstall from removing it on a later rebuild. Login secrets are filled through
      # the allowlisted ask MCP native helper; only adobe.com credentials can reach this bundle.
      "adobe-creative-cloud"
      # Blender。nix ではなく brew なのは、あちらだとソースから建てることになるため。
      # 依存の manifold が macmini (macOS 26.5.2) でテスト中に SIGTRAP で落ちるうえ
      # (GetNormalLegacyContract, exit 133)、aarch64-darwin のキャッシュも無いので
      # blender ごと入らない。テストを外して建てる手も試したが 10 分で終わらなかった。
      #
      # 署名済みバイナリを運ぶだけのものは brew でよい、という [[nix-vs-brew-signing-rule]]
      # のとおりの事例。CLI は .app の中にあり、画面なしで焼ける:
      #   /Applications/Blender.app/Contents/MacOS/Blender -b scene.blend -a
      "blender"
    ];
  };

  # cachix: CI runner のため。GitHub の hosted runner は毎回入れ直すしかないが、この機械は
  # 常設なので宣言しておく。入れ直しに 30 秒以上かかっていて、それが setup-nix を
  # 実際のビルドより長くしていた (56s の準備に対し 18s のビルド、2026-09-10 実測)。
  #
  # nodejs: runtime for Playwright MCP (pnpm dlx) and claude-login-broker (inject-creds.js).
  # bitwarden-cli: after approval the broker pulls credentials via bw get. BW_SESSION is unlocked manually.
  # cloudflared: publishes the study agent's OpenAI-compatible API (127.0.0.1:8791) so the
  # dashboard on Cloudflare Pages can reach it. Only the tunnel egresses; nothing is exposed
  # on the LAN. The tunnel credentials can't be declared, so create them once with
  # `cloudflared tunnel login && cloudflared tunnel create manabi` (see launchd.daemons below).
  # ffmpeg / aria2 moved off homebrew (2026-08-13). They were kept there because nobody could
  # verify the AI stack still came up on this headless machine after a swap; that check has now
  # been done. systemPackages rather than home.packages on purpose: ai-stack.sh builds its own
  # PATH from /opt/homebrew and /run/current-system/sw, and the per-user profile is not on it.
  environment.systemPackages = [
    pkgs.cachix
    pkgs.nodejs_22
    fastPkgs.bitwarden-cli
    pkgs.cloudflared
    pkgs.ffmpeg
    pkgs.aria2
    # marp: popo's setup wizard shells out to `npm install -g @marp-team/marp-cli` when it cannot
    # find marp on PATH. Declaring it here means that step never runs — and npm stays what it is
    # on this machine, a thing that comes along with node rather than a package manager anyone uses.
    pkgs.marp-cli
  ];

  # (An ollama serve LaunchAgent was here, holding ~47G of GGUF weights in ollama's own blob
  #  store. Dropped 2026-08-28: this machine's inference is MLX (faster than llama.cpp for the
  #  same model on Apple Silicon) plus claude-bridge for the agent work, so ollama was carrying
  #  a duplicate copy of the model library for a path nothing routed through any more.)

  # (The auto-fix pipeline's monitor lived here. System-level launchd.agents start in a
  #  root context on a machine with no GUI login, and claude refuses
  #  --dangerously-skip-permissions under root, so it woke up every hour and achieved
  #  nothing. Its successor, claude-agent, is a home-manager agent instead — see
  #  nix/home/macmini-claude-agent.nix.)

  # Minecraft, run straight on macOS as its own user rather than in a container.
  #
  # It used to be an Apple container, which bought the itzg image's conveniences and cost far more:
  # published ports never actually forwarded (the host side accepts then resets, TCP included, so
  # nobody could ever join), ENABLE_AUTOPAUSE could not start knockd on the guest interface, and the
  # guest kernel meant ~3.2G resident no matter how small the JVM heap was. Native, the same world
  # sits at ~1.2G and binds the port itself. With this the mini has no containers left at all.
  #
  # The server jar and mods come from nix by content hash (pkgs/fabric-server.nix,
  # pkgs/fabric-mods.nix), and the hourly update-custom-packages job moves those pins to the newest
  # game version every mod supports. The client here is Prism, which starts the newest release, so
  # the server follows it — but through a reviewed, revertible commit rather than by re-downloading
  # LATEST behind our backs at some restart.
  #
  # Following costs one thing: a world conversion can arrive on its own schedule, and conversion is
  # one-way. run.sh snapshots the world first whenever the jar's version differs from the last run.
  #
  # History: 26.1.2 -> 26.2 on 2026-08-15 before opening to friends (launchers start the newest
  # release, so lagging would have made every guest hunt for an old profile); Paper -> Fabric on
  # 2026-09-26 (see the minecraftServers comment).

  # --- Hermes, brought under nix -------------------------------------------------------------
  #
  # These six were hand-written plists in /Library/LaunchDaemons, i.e. daemons nothing declared.
  # Migrating them is also the chance to give this machine a scheduling policy, because until now
  # everything ran at the same priority: a long agent turn competed with Minecraft ticks and with
  # inference somebody was waiting on.
  #
  # The tiers are: Interactive for what a human is waiting on (the game server, sunshine),
  # Standard for the cheap supervisors, Background for the agents and every batch job. Background
  # on Apple Silicon means the E cores, which is right for these: they spend their time waiting on
  # the network, not on the CPU.
  #
  # The labels change (net.gapul.* -> org.nixos.*), so the old plists are booted out below.
  #
  # The runner scripts come from the store too (configs/macmini/hermes/). They used to sit loose in
  # /Users/hermes/.hermes/bin and /usr/local/libexec, which is how the watchdog ended up still
  # polling claude-bridge on :9180 four hours after that daemon was deleted — its state file said
  # `down: bridge` and it had paged once. Reading it to move it is what found that.

  # Hermes proper — the Discord side. Talks to Claude through the claude-acp adapter.
  launchd.daemons.hermes-gateway = {
    command = "${../../configs/macmini/hermes/hermes-gateway-run.sh}";
    serviceConfig = {
      UserName = "hermes";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/Users/hermes/.hermes/logs/gateway.log";
      StandardErrorPath = "/Users/hermes/.hermes/logs/gateway.log";
    };
  };

  # The second instance ("まなび"), which runs out of its own HOME so it can hold its own
  # api_server port. Same binary, different profile.
  #
  # It used to be called imouto everywhere on this side while the outside world — the Telegram
  # bot, the dashboard, the other daemons — called it manabi. One name now, and the outward one
  # won. Session keys are unaffected: this instance has its own HOME, so its keys are
  # `agent:main:discord:...` and never carried the old name.
  launchd.daemons.hermes-gateway-manabi = {
    serviceConfig = {
      ProgramArguments = [ "${manabi}/bin/manabi-gateway-run.sh" ];
      UserName = "hermes";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/Users/hermes/manabi-home/gateway.log";
      StandardErrorPath = "/Users/hermes/manabi-home/gateway.log";
    };
  };

  launchd.daemons.hermes-watchdog = {
    command = "${../../configs/macmini/hermes/hermes-watchdog.sh}";
    serviceConfig = {
      StartInterval = 300;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "/var/log/hermes-watchdog.log";
      StandardErrorPath = "/var/log/hermes-watchdog.log";
    };
  };

  launchd.daemons.hermes-logrotate = {
    command = "${../../configs/macmini/hermes/hermes-logrotate.sh}";
    serviceConfig = {
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 15;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/var/log/hermes-logrotate.log";
      StandardErrorPath = "/var/log/hermes-logrotate.log";
    };
  };

  launchd.daemons.hermes-brain-backup = {
    command = "${../../configs/macmini/hermes/hermes-brain-backup.sh}";
    serviceConfig = {
      UserName = "hermes";
      StartCalendarInterval = [
        {
          Hour = 3;
          Minute = 30;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/Users/hermes/.hermes/logs/brain-backup.log";
      StandardErrorPath = "/Users/hermes/.hermes/logs/brain-backup.log";
    };
  };

  # The nightly study review. Its old plist still pointed at ~/ai/manabi-dashboard, which the
  # 2026-08-12 cleanup moved to Developer/projects — so it had been failing at 22:30 with nothing
  # to say so. Declaring it is what surfaced that.
  launchd.daemons.manabi-daily-review = {
    serviceConfig = {
      ProgramArguments = [ "${manabi}/dashboard/daily_review.sh" ];
      UserName = user.username;
      StartCalendarInterval = [
        {
          Hour = 22;
          Minute = 30;
        }
      ];
      ProcessType = "Background";
      Nice = 10;
      # launchd creates the parent of these paths at every start, whether or not the program runs.
      # That is what kept resurrecting ~/ai/manabi-dashboard (the old hand-written plist pointed
      # there long after ~/ai was retired) and then ~/Developer/projects/manabi-dashboard, which
      # this unit recreated the same night the service moved to /Users/Shared/manabi. Logs live in
      # XDG state now, next to the dashboard refresh log, so nothing is resurrected anywhere.
      StandardOutPath = "/Users/${user.username}/.local/state/manabi/daily_review.log";
      StandardErrorPath = "/Users/${user.username}/.local/state/manabi/daily_review.log";
    };
  };

  # Bedrock (スマホ / Switch / Win10 版) の入口。Geyser が BE の通信を Java に翻訳し、Floodgate
  # (サーバー側 mod) が Java アカウント無しの人を Xbox アカウントで通す。standalone にしてある
  # のは lazymc のため: サーバー内の mod として動かすと、サーバーが寝ている間は Geyser も居ない
  # ので BE から起こせない。前段に常駐させ、Java クライアントとして lazymc を叩かせる。
  # 待機コストは JVM 1 つ分 (300〜500MB)。無人時ゼロだった構成で唯一の常駐増。
  # 本館だけ。solo に BE から入る日が来たら port を変えてもう 1 つ生やす。
  launchd.daemons.geyser = {
    command = "${pkgs.writeShellScript "geyser" ''
      set -u
      dir=/Users/mcsrv/geyser
      /bin/mkdir -p "$dir/logs"
      cd "$dir"
      # 設定は宣言が正。Geyser は起動時に config.yml を書き換える (欠けたキーを補う) ので、
      # 毎回 store から置き直す。
      /bin/cp -f ${../../configs/macmini/minecraft/geyser-config.yml} config.yml
      /bin/chmod 644 config.yml
      /usr/bin/base64 -d < /etc/minecraft/floodgate-key.b64 > key.pem
      /bin/chmod 600 key.pem
      exec ${pkgs.temurin-bin-25}/bin/java -Xms128M -Xmx512M -jar ${geyser} --nogui
    ''}";
    serviceConfig = {
      UserName = "mcsrv";
      WorkingDirectory = "/Users/mcsrv";
      ProcessType = "Interactive";
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/mcsrv/geyser/logs/launchd.log";
      StandardErrorPath = "/Users/mcsrv/geyser/logs/launchd.log";
    };
  };

  # ワールドの日次バックアップ。Realms から移ってくる以上、「壊しても戻せる」は要る。
  # 対象は上の表から作るので、サーバーを増やせばバックアップも自動で増える。
  # restic(5:00)より前に走らせて、その晩のうちに Google Drive まで乗せる。
  launchd.daemons.minecraft-backup = {
    command = "${../../configs/macmini/minecraft/backup.sh}";
    serviceConfig = {
      EnvironmentVariables = {
        BACKUP_TARGETS = lib.concatStringsSep " " (
          lib.mapAttrsToList (name: inst: "${name}:${inst.dir}") minecraftServers
        );
      };
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 40;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/Users/Shared/minecraft-backups/backup.log";
      StandardErrorPath = "/Users/Shared/minecraft-backups/backup.log";
    };
  };

  # Hermes の状態を restic が読める場所へ固める。専用ユーザーのホームは gapul から
  # 読めないので、マイクラと同じくここで tar にしてから拾わせる。restic(5:00)より前に走らせる。
  launchd.daemons.hermes-backup = {
    command = "${../../configs/macmini/hermes/backup.sh}";
    serviceConfig = {
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 50;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/Users/Shared/hermes-backups/backup.log";
      StandardErrorPath = "/Users/Shared/hermes-backups/backup.log";
    };
  };

  # popo — the Slack agent for the company workspace, run as its own user.
  #
  # It reaches the control plane at api.popo.sh with a bootstrap key (config/.env, outside nix) and
  # takes its Slack traffic from there, so no Slack token lives on this machine. The runtime is
  # installed imperatively (`uv tool install` from a build of the repo's main branch, because the
  # published release is months behind); what is declared here is only that this machine runs it.
  #
  # Tier: Background. Like hermes, it spends its time waiting on the network, and it must not
  # compete with the game server's ticks or with inference somebody is watching.
  launchd.daemons.popo = {
    serviceConfig = {
      ProgramArguments = [
        "/Users/popo/.local/bin/popo"
        "run"
        "--home"
        "/Users/popo/popo-home"
      ];
      UserName = "popo";
      WorkingDirectory = "/Users/popo/popo-home";
      EnvironmentVariables = {
        POPO_HOME = "/Users/popo/popo-home";
        PATH = "/Users/popo/.local/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        HOME = "/Users/popo";
      };
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/Users/popo/popo-home/logs/popo.stdout.log";
      StandardErrorPath = "/Users/popo/popo-home/logs/popo.stderr.log";
    };
  };

  # Keep the tunnel up as a daemon (root) so it survives logout. Reads /usr/local/etc/manabi-tunnel.env for TUNNEL_TOKEN, which
  # is issued per-tunnel in the Cloudflare dashboard and can't live in the nix store.
  launchd.daemons.manabi-tunnel = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          . /usr/local/etc/manabi-tunnel.env 2>/dev/null || exit 0
          exec ${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/manabi-tunnel.log";
      StandardErrorPath = "/var/log/manabi-tunnel.log";
    };
  };

  # Prep for headless operation (nix-darwin has no typed option, so an idempotent script).
  # postActivation is used by darwin-common, so put this in preActivation to avoid a collision.
  system.activationScripts.preActivation.text = ''
    # Prevent sleep: don't let it sleep so it can serve inference unattended.
    /usr/bin/pmset -a sleep 0          >/dev/null 2>&1 || true
    /usr/bin/pmset -a disablesleep 1   >/dev/null 2>&1 || true
    # Enable Remote Login (SSH). Key auth reuses the existing setup (Bitwarden agent etc.) as-is.
    /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1 || true
    # Power Nap wakes the machine for background work it does not need to do; this one never
    # sleeps in the first place.
    /usr/bin/pmset -a powernap 0 >/dev/null 2>&1 || true
    # 画面を消させない。ここは省電力の話ではなく、遠隔操作の前提。ディスプレイが寝ると
    # スクリーンセーバ経由でロック画面に戻り、そこから先はパスワードを打てる人間が要る。
    # (キャプチャは HDMI に繋いだ側で見ているので、消えると何も見えなくもなる)
    /usr/bin/pmset -a displaysleep 0 >/dev/null 2>&1 || true
    /usr/bin/sudo -u ${user.username} /usr/bin/defaults -currentHost write com.apple.screensaver idleTime -int 0 >/dev/null 2>&1 || true
    # ロックそのものの有効/無効は sysadminctl -screenLock にあり、変更にアカウントの
    # パスワードが要るので宣言できない。無効にしてあるが、OS の更新で戻ったら手で戻す:
    #   ssh -t macmini 'sysadminctl -screenLock off -password -'
    # 同じ理由で TCC の許可 (sshd-keygen-wrapper のアクセシビリティと画面収録) も
    # ここには書けない。docs/macmini-remote.md を参照。
    # Wi-Fi off. The mini is wired (en0 is the default route) and was sitting on both networks at
    # once, which buys nothing and keeps the radio, its driver extension and wifianalyticsd busy.
    # If the cable ever dies this machine needs hands anyway — it is three metres away.
    /usr/sbin/networksetup -setairportpower en1 off >/dev/null 2>&1 || true
    # Application Firewall は許可をバイナリごとに覚えるので、store path が変わる更新のたびに
    # 新しい lazymc は「未知のアプリ」になり、外からの接続が黙って落ちる (loopback は通るので
    # 気付きにくい)。java は前から登録済みだったが、公開ポートを持つのは lazymc に変わった。
    /usr/libexec/ApplicationFirewall/socketfilterfw --add ${pkgs.lazymc}/bin/lazymc >/dev/null 2>&1 || true
    /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp ${pkgs.lazymc}/bin/lazymc >/dev/null 2>&1 || true
    # Geyser は java そのものが UDP 19132 を持つ (lazymc を介さない)。宣言した JDK の java を許可する。
    /usr/libexec/ApplicationFirewall/socketfilterfw --add ${pkgs.temurin-bin-25}/bin/java >/dev/null 2>&1 || true
    /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp ${pkgs.temurin-bin-25}/bin/java >/dev/null 2>&1 || true
    # AivisSpeech is served to workstation clients over Tailscale.  Like lazymc,
    # every Nix update can give its executable a new store path, so keep the
    # incoming-connection permission tied to the declared package.
    /usr/libexec/ApplicationFirewall/socketfilterfw --add ${aivisSpeechEngine}/libexec/aivisspeech-engine/run >/dev/null 2>&1 || true
    /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp ${aivisSpeechEngine}/libexec/aivisspeech-engine/run >/dev/null 2>&1 || true
    # The hand-written plists the daemons above replace. nix-darwin names its units org.nixos.*,
    # so without this both copies would be loaded and Hermes would come up twice.
    for label in net.gapul.hermes-gateway net.gapul.hermes-gateway-imouto net.gapul.hermes-watchdog \
                 net.gapul.hermes-logrotate net.gapul.hermes-brain-backup net.gapul.manabi-daily-review \
                 org.nixos.hermes-gateway-imouto; do
      if [ -f "/Library/LaunchDaemons/$label.plist" ]; then
        /bin/launchctl bootout "system/$label" >/dev/null 2>&1 || true
        /bin/rm -f "/Library/LaunchDaemons/$label.plist" || true
      fi
    done
    # /opt/ai/bin, the pre-XDG copies of the AI wrappers. Root-owned, dated 2026-07-16, and put on
    # the system PATH by /etc/paths.d/ai — so they shadowed the declared ~/.local/bin ones in every
    # interactive shell. They still pointed at ~/models and ~/sbv2-venv, paths the XDG move retired,
    # which is why `transcribe` answered "モデル未導入" while the AI panel (which builds its own PATH)
    # worked fine. The declaration was right; something older was winning.
    /bin/rm -f /etc/paths.d/ai || true
    /bin/rm -rf /opt/ai || true
    # Google's updater, removed. Chrome here is an automation target that gets upgraded by hand
    # with the rest of the declaration, so a resident agent waking up to check for versions is
    # noise. Chrome re-installs Keystone whenever it is launched, so this runs every activation
    # rather than once; checkInterval 0 keeps it quiet in between.
    guiuid=$(/usr/bin/id -u ${user.username})
    /usr/bin/sudo -u ${user.username} /usr/bin/defaults write com.google.Keystone.Agent checkInterval 0 >/dev/null 2>&1 || true
    for label in com.google.GoogleUpdater.wake com.google.keystone.agent com.google.keystone.xpcservice; do
      /bin/launchctl bootout "gui/$guiuid/$label" >/dev/null 2>&1 || true
      /bin/rm -f "/Users/${user.username}/Library/LaunchAgents/$label.plist" || true
    done
    /bin/rm -rf "/Users/${user.username}/Library/Google" \
      "/Users/${user.username}/Library/Application Support/Google/GoogleUpdater" || true
    # No Spotlight on a machine nobody searches from. mds_stores alone held ~100M and the indexer
    # keeps walking the disk; the agents here search with grep/ripgrep, not mdfind.
    /usr/bin/mdutil -a -i off >/dev/null 2>&1 || true
    # The desktop still needs a login session (Metal wants one), but not a moving picture in it:
    # the default aerial wallpaper burned ~17% CPU between the extension, its video decoder and
    # WindowServer, on a screen no one looks at. Nothing declarative sets this — it is done once
    # with NSWorkspace.setDesktopImageURL as the logged-in user and persists.
    # The Hermes agent's inference adapter (see configs/macmini/hermes/README.md). It lives in
    # another user's home, which home-manager can't reach, and hermes never rewrites it — so the
    # declaration is the source of truth and gets laid down on every activation.
    if [ -d /Users/hermes ]; then
      /usr/bin/install -d -o hermes -g staff -m 755 /Users/hermes/.local/bin
      /usr/bin/install -o hermes -g staff -m 755 \
        ${claudeAcp}/bin/claude-acp /Users/hermes/.local/bin/claude-acp
    fi
  '';
}
