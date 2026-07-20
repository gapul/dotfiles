import re

# rmpc 等の新しめの MPD クライアントは接続時に `binarylimit <size>` を送るが、
# mopidy-mpd 3.3.0 は未実装で "unknown command" を返し接続が切れる。
# no-op コマンドとして登録し OK を返す (albumart のバイナリ分割サイズ指定なので無視で問題ない)。
p = "mopidy_mpd/protocol/connection.py"
s = open(p).read()
if "binarylimit" not in s:
    s += (
        '\n\n@protocol.commands.add("binarylimit")\n'
        "def binarylimit(context, limit):\n"
        "    # patched: rmpc 等が送る binarylimit を no-op で受けて OK を返す\n"
        "    pass\n"
    )
    open(p, "w").write(s)
    print("patched connection.py: binarylimit no-op を追加")
else:
    print("binarylimit already present, skip")
