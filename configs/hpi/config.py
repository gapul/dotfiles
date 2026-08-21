"""
HPI (Human Programming Interface) の設定。`~/.config/my/my/config.py` に置かれる。

HPI は「SaaS から引き出したエクスポートを、ローカルで横断的に引ける形にしておく」
ための枠組み。サービスを離れるときに Takeout なりアーカイブなりを取っておけば、
以後ずっと手元で検索・集計できる。

各モジュールが何を要求するかは `hpi doctor <module>` が教えてくれる。
"""

from pathlib import Path

HOME = Path.home()


class activitywatch:
    """画面・ウィンドウ・ブラウザタブ。自前モジュール (activitywatch.py) が読む。

    aw-server が書いている生の SQLite をそのまま指す。エクスポート不要で、
    常に最新が読める。
    """

    # 母艦の生 DB と、Syncthing 経由で集まった他端末ぶんの写しの両方を見る。
    # get_files がグロブを受けるので、端末が増えても書き換えは要らない。
    export_path = [
        HOME / "Library/Application Support/activitywatch/aw-server/peewee-sqlite.v2.db",
        HOME / "Sync/syncthing/personal-history/*/activitywatch/peewee-sqlite.v2.db",
    ]


class atuin:
    """端末で打ったコマンド。自前モジュール (atuin.py) が読む。

    atuin は既定でローカルの SQLite に書くだけなので、これもエクスポート不要。
    ActivityWatch が「Ghostty が前面にあった」までしか見ないのに対して、
    こちらは中で何を打ったかを持っている。
    """

    export_path = HOME / ".local/share/atuin/history.db"


# --- ここから下は、対応するデータを取ってきたら有効にする ---
#
# Google Takeout。"My Activity" に検索履歴と YouTube の視聴履歴が入っているので、
# Google を離れるときはこれを取っておくと過去ぶんが手元に残る。
# https://takeout.google.com で「マイ アクティビティ」と「YouTube」を選んで zip を落とし、
# 下のパスに置いて class のコメントを外す。
#
# class google:
#     takeout_path = HOME / "Documents/exports/takeout/*.zip"
#
# GitHub。ghexport (https://github.com/karlicoss/ghexport) で吐いた JSON を指す。
#
# class github:
#     export_path = HOME / "Documents/exports/github/*.json"
#
# ブラウザ履歴。browserexport (https://github.com/purarue/browserexport) を使う。
# ただし ActivityWatch のブラウザ拡張が既にタブ遷移を記録しているので、
# 素の履歴が別途要るかは用途次第。
#
# class browser:
#     class export:
#         export_path = HOME / "Documents/exports/browser/*.sqlite"
