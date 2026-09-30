# Export personal records into a per-machine directory and put them on Syncthing.
#
# --- Why "per machine" ---
#
# The records come in two kinds.
#
#   1. One writer per file      … Claude Code's projects/<uuid>.jsonl. A separate file per
#                                 session, written only by the machine that ran it.
#                                 Append-only. Syncing as is never conflicts.
#   2. Many writers per file    … Claude Code's history.jsonl, nvim's keystrokes.jsonl.
#                                 Every machine appends to the same path. **Syncing as is
#                                 always conflicts** (Syncthing sprouts sync-conflict-*).
#
# There's no clean way to sync kind 2 directly. So what gets synced is not the original file
# but a copy under `<share>/personal-history/<hostname>/`. Each machine writes only its own
# directory, so conflicts can't happen by construction. Same idea as ActivityWatch's aw-sync.
#
# The reader (HPI) globs something like `personal-history/*/claude/history.jsonl` and gets
# all machines as one stream. get_files accepts globs, so it can be written as is.
#
# atuin alone stays out. It has its own sync (homelab/atuin.nix), per record and encrypted,
# which beats handing around file copies.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  home = config.home.homeDirectory;
  # ~/Sync/syncthing is the Syncthing share itself. It's also covered by restic, so anything
  # exported here is backed up as well as synced. This also fixes Claude's history.jsonl not
  # being backed up anywhere.
  shareRoot = "${home}/Sync/syncthing/personal-history";

  snapshot = pkgs.writeShellScript "personal-history-snapshot" ''
        set -u
        host="$(${pkgs.nettools}/bin/hostname -s)"
        out="${shareRoot}/$host"
        mkdir -p "$out/claude" "$out/nvim"

        # --- 追記型の JSONL: そのままコピーでよい ---
        # 元は単調増加なので、途中で切れても次回に取り直せる。
        for src_dst in \
          "${config.xdg.configHome}/claude/history.jsonl:$out/claude/history.jsonl" \
          "${config.xdg.dataHome}/nvim/ai_keymap/keystrokes.jsonl:$out/nvim/keystrokes.jsonl"
        do
          src="''${src_dst%%:*}"; dst="''${src_dst##*:}"
          [ -r "$src" ] && cp -f "$src" "$dst"
        done

        # --- Claude のセッション本体 ---
        # UUID 名で1ファイル1書き手なので、本来はそのまま同期しても衝突しない。
        # それでも端末ごとに分けているのは、どの端末で走ったセッションかが
        # ディレクトリから分かるようにするため。追記のみなので rsync の差分は小さい
        # (初回だけ重い)。
        if [ -d "${config.xdg.configHome}/claude/projects" ]; then
          ${pkgs.rsync}/bin/rsync -a --delete-excluded \
            --include='*/' --include='*.jsonl' --exclude='*' \
            "${config.xdg.configHome}/claude/projects/" "$out/claude/projects/"
        fi

        # --- SQLite: 稼働中なのでファイルコピーは千切れうる ---
        # .backup はオンラインバックアップ API を使うので一貫した写しが取れる。
        # homelab/backup.nix が readeck に対してやっているのと同じ手口。
        ks="${config.xdg.dataHome}/keystats/keystats.db"
        if [ -r "$ks" ]; then
          mkdir -p "$out/keystats"
          ${pkgs.sqlite}/bin/sqlite3 "$ks" ".backup $out/keystats/keystats.db"
        fi

        # 0.14 (Tauri 版) から aw-server-rust の DB。旧 aw-server (Python) の
        # peewee-sqlite.v2.db は全件取り込み済みなので、古い写しは消して二重に読ませない。
        aw="$HOME/Library/Application Support/activitywatch/aw-server-rust/sqlite.db"
        if [ -r "$aw" ]; then
          mkdir -p "$out/activitywatch"
          ${pkgs.sqlite}/bin/sqlite3 "$aw" ".backup $out/activitywatch/sqlite.db"
          rm -f "$out/activitywatch/peewee-sqlite.v2.db"
        fi

        # Zen と Firefox の閲覧履歴とブックマーク (places.sqlite)。Firefox 系は起動中 DB を排他ロックで
        # 開くので直接 .backup すると locked で落ちる。本体と -wal をいったん写してから、その写しを
        # .backup で 1 ファイルに畳む (WAL の中身もここで本体に入る)。アプリ・プロファイルごとに分ける。
        # 2026-09-26 に Zen の履歴を Firefox (dev プロファイル) へ移したので、以後の増分は firefox/ 側。
        for places in "$HOME/Library/Application Support"/{zen,Firefox}/Profiles/*/places.sqlite; do
          [ -r "$places" ] || continue
          prof="$(basename "$(dirname "$places")")"
          app="$(basename "$(dirname "$(dirname "$(dirname "$places")")")")"
          dst="$out/''${app,,}/''${prof// /_}"
          tmp="$(mktemp -d)"
          cp "$places" "$tmp/places.sqlite"
          [ -f "$places-wal" ] && cp "$places-wal" "$tmp/places.sqlite-wal"
          mkdir -p "$dst"
          ${pkgs.sqlite}/bin/sqlite3 "$tmp/places.sqlite" ".backup '$dst/places.sqlite'"
          rm -rf "$tmp"
        done

        # ListenBrainz の再生履歴 (mopidy-listenbrainz が送っている先)。公開 API なのでトークン不要。
        # listens.jsonl に追記し、既にある最新の listened_at より新しいものだけ取る。
        # API は新しい順にしか返さないので、max_ts を今から遡ってページを辿る。
        lb="$out/listenbrainz"
        mkdir -p "$lb"
        ${pkgs.python3}/bin/python3 - "$lb/listens.jsonl" <<'PY' || true
    import json, os, sys, time, urllib.request
    path, user = sys.argv[1], "copy4711"
    last = 0
    if os.path.exists(path):
        with open(path) as fh:
            for line in fh:
                last = max(last, json.loads(line)["listened_at"])
    new, max_ts = [], int(time.time()) + 1
    while True:
        url = f"https://api.listenbrainz.org/1/user/{user}/listens?count=1000&max_ts={max_ts}"
        with urllib.request.urlopen(url, timeout=60) as r:
            page = json.load(r)["payload"]["listens"]
        fresh = [l for l in page if l["listened_at"] > last]
        new += fresh
        if not page or len(fresh) < len(page):
            break
        max_ts = page[-1]["listened_at"]
        time.sleep(1)
    with open(path, "a") as fh:
        for l in sorted(new, key=lambda l: l["listened_at"]):
            fh.write(json.dumps(l, ensure_ascii=False) + "\n")
    PY
  '';
in
{
  # Once a day is enough. These are all records for later aggregation; minute-level freshness
  # isn't needed. On days the machine slept and it didn't fire, the next run after wake
  # catches up (the sources are append-only, so nothing is lost).
  launchd.agents.personal-history-snapshot = import ../lib/launchd-agent.nix {
    program = "${snapshot}";
    schedule = {
      Hour = 4;
      Minute = 20;
    };
  };

  home.packages = lib.mkAfter [ ];
}
