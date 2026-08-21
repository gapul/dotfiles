# 個人の記録を端末ごとのディレクトリへ書き出して Syncthing に載せる。
#
# --- なぜ「端末ごと」なのか ---
#
# 記録の実体は2種類に分かれる。
#
#   1. 1ファイル1書き手     … Claude Code の projects/<uuid>.jsonl。セッションごとに
#                            別ファイルで、書くのはそのセッションを走らせた端末だけ。
#                            追記のみ。そのまま同期しても衝突しない。
#   2. 1ファイル複数書き手   … Claude Code の history.jsonl、nvim の keystrokes.jsonl。
#                            どの端末も同じパスに追記する。**そのまま同期すると必ず
#                            衝突する** (Syncthing なら sync-conflict-* が生える)。
#
# 2 を素直に同期する方法は無い。なので、同期するのは元ファイルではなく
# `<共有>/personal-history/<ホスト名>/` 以下の写しにする。各端末は自分の名前の
# ディレクトリしか書かないので、構造として衝突が起きない。ActivityWatch の aw-sync が
# 採っているのと同じ考え方。
#
# 読む側 (HPI) は `personal-history/*/claude/history.jsonl` のようにグロブで拾えば、
# 全端末ぶんが1つの列として出てくる。get_files がグロブを受けるのでそのまま書ける。
#
# atuin だけはここに入れない。あちらは本体に同期機構があり (homelab/atuin.nix)、
# レコード単位・暗号化つきなので、ファイルの写しを配るより筋がいい。
{
  config,
  pkgs,
  lib,
  ...
}:

let
  home = config.home.homeDirectory;
  # ~/Sync/syncthing は Syncthing の共有そのもの。restic の対象にも入っているので、
  # ここへ書き出したものは同期と同時にバックアップにも乗る。Claude の history.jsonl が
  # どこにもバックアップされていなかった問題も、これで片付く。
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

    aw="$HOME/Library/Application Support/activitywatch/aw-server/peewee-sqlite.v2.db"
    if [ -r "$aw" ]; then
      mkdir -p "$out/activitywatch"
      ${pkgs.sqlite}/bin/sqlite3 "$aw" ".backup $out/activitywatch/peewee-sqlite.v2.db"
    fi
  '';
in
{
  # 1日1回で足りる。どれも「後から集計する」ための記録で、分単位の鮮度は要らない。
  # 端末が寝ていて発火しなかった日は、次に起きたときの回で追いつく (元が追記型なので
  # 取りこぼしにならない)。
  launchd.agents.personal-history-snapshot = import ../lib/launchd-agent.nix {
    program = "${snapshot}";
    schedule = {
      Hour = 4;
      Minute = 20;
    };
  };

  home.packages = lib.mkAfter [ ];
}
