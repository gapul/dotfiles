"""
[[https://activitywatch.net][ActivityWatch]] — window / afk / browser tab tracking.

HPI 本体にこのモジュールは無い (近いのは arbtt と rescuetime だけ)。ActivityWatch は
この環境で一番量のあるローカルデータなので、自前で書いて `my` 名前空間に足す。
`~/.config/my` は HPI が sys.path の先頭に差し込む (my/core/init.py) ので、
implicit namespace package として `my.activitywatch` で読める。

REST API ではなく SQLite を直接読む。API だと aw-server が起動している必要があり、
「過去のデータを後から集計する」という HPI の使い方に合わないため。
"""

from __future__ import annotations

import json
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from my.core import Json, Paths, Stats, get_files, stat
from my.core.sqlite import sqlite_copy_and_open


def inputs() -> Sequence[Path]:
    from my.config import activitywatch as user_config

    return get_files(user_config.export_path)


@dataclass
class Event:
    dt: datetime
    duration: timedelta
    bucket: str
    hostname: str
    type: str
    client: str
    data: Json

    @property
    def app(self) -> str | None:
        """currentwindow なら実行中のアプリ名。"""
        return self.data.get("app")

    @property
    def title(self) -> str | None:
        """ウィンドウのタイトル、またはブラウザのページタイトル。"""
        return self.data.get("title")

    @property
    def url(self) -> str | None:
        """web.tab.current のときだけ入る。"""
        return self.data.get("url")


def _normalise_hostname(hostname: str) -> str:
    """`MacBook-Mini.local` と `MacBook-Mini` を同じ端末として扱う。

    ActivityWatch はバケット ID にホスト名を埋め込むが、ネイティブの watcher と
    ブラウザ拡張とで参照する名前が違うことがあり、同じ Mac が2つの端末として
    記録される。実際この環境では 2026-08-09 を境に window と afk が `.local` 無しに
    切り替わり、ブラウザ側だけ `.local` のまま残った。

    DB を書き換えて統合する手もあるが、8ヶ月ぶんの再取得不可能なデータに対して
    破壊的な操作をする理由がない。読むときに寄せれば済む。
    """
    return hostname.removesuffix(".local")


def _parse_ts(raw: str) -> datetime:
    # sqlite には '2026-08-21 02:59:15.142000+00:00' の形で入っている。
    dt = datetime.fromisoformat(raw)
    if dt.tzinfo is None:
        # 念のため。aw-server は UTC で書くので、素の値も UTC とみなす。
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def events() -> Iterator[Event]:
    """全バケットのイベントを時系列で返す。"""
    for db_path in inputs():
        # 稼働中の aw-server が WAL を持っているので、コピーしてから開く。
        # immutable=1 で直接開くと WAL 内の新しいイベントを取りこぼす。
        with sqlite_copy_and_open(db_path) as conn:
            buckets = {
                key: (bid, btype, client, _normalise_hostname(hostname))
                for key, bid, btype, client, hostname in conn.execute(
                    "select key, id, type, client, hostname from bucketmodel"
                )
            }
            for bucket_key, ts, duration, datastr in conn.execute(
                "select bucket_id, timestamp, duration, datastr"
                " from eventmodel order by timestamp"
            ):
                meta = buckets.get(bucket_key)
                if meta is None:
                    # バケットが消えたのにイベントが残っている場合。実データでは
                    # 見ていないが、外部キーは張られているだけで強制はされない。
                    continue
                bid, btype, client, hostname = meta
                yield Event(
                    dt=_parse_ts(ts),
                    duration=timedelta(seconds=float(duration)),
                    bucket=bid,
                    hostname=hostname,
                    type=btype,
                    client=client,
                    data=json.loads(datastr),
                )


def _of_type(wanted: str) -> Iterator[Event]:
    for e in events():
        if e.type == wanted:
            yield e


def window() -> Iterator[Event]:
    """アクティブなウィンドウ。app と title が入る。"""
    return _of_type("currentwindow")


def afk() -> Iterator[Event]:
    """離席の有無。data['status'] が 'afk' か 'not-afk'。"""
    return _of_type("afkstatus")


def browser() -> Iterator[Event]:
    """ブラウザのタブ。url と title が入る。視聴履歴と検索履歴はここから拾える。"""
    return _of_type("web.tab.current")


def stats() -> Stats:
    return {
        **stat(events),
        **stat(window),
        **stat(browser),
    }
