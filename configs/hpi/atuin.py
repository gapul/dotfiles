"""
[[https://atuin.sh][Atuin]] — 端末で打ったコマンドの履歴。

activitywatch.py と同じ理由で自前。HPI 本体に atuin のモジュールは無い。

ActivityWatch は「Ghostty が前面にあった」までしか分からないので、そこで実際に
何を打ったかはここにしかない。逆に atuin は端末の中しか見ないので、両方あって
初めて「何時に何をしていたか」が繋がる。

atuin は既定でローカルの SQLite に書くだけで、同期はオプトイン。つまり
記録そのものは最初から自前になっている。
"""

from __future__ import annotations

from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from my.core import Stats, get_files, stat
from my.core.sqlite import sqlite_copy_and_open


def inputs() -> Sequence[Path]:
    from my.config import atuin as user_config

    return get_files(user_config.export_path)


@dataclass
class Command:
    dt: datetime
    command: str
    cwd: str
    exit_code: int
    duration: timedelta
    hostname: str
    user: str
    session: str

    @property
    def succeeded(self) -> bool:
        return self.exit_code == 0

    @property
    def finished(self) -> bool:
        """終了コードが記録されているか。

        atuin は打った時点で行を作り、終わったときに exit と duration を埋める。
        埋まる前に端末ごと消えると -1 のまま残る。実データでは 1313/3915 が
        これで、全体の3分の1が「終わりを見ていない」。多くは長時間の対話
        セッション (claude や ssh) を閉じたケース。
        """
        return self.exit_code != -1


def _split_host(raw: str) -> tuple[str, str]:
    """atuin の hostname は `MacBook-Mini:gapul` の形で user がくっついている。"""
    host, _, user = raw.partition(":")
    return host, user


def commands() -> Iterator[Command]:
    for db_path in inputs():
        # 稼働中の atuin が WAL を持つので、コピーしてから開く
        # (activitywatch.py と同じ理由)。
        with sqlite_copy_and_open(db_path) as conn:
            for ts, duration, exit_code, command, cwd, session, hostname in conn.execute(
                "select timestamp, duration, exit, command, cwd, session, hostname"
                " from history where deleted_at is null order by timestamp"
            ):
                host, user = _split_host(hostname)
                yield Command(
                    # timestamp も duration もナノ秒。
                    dt=datetime.fromtimestamp(ts / 1_000_000_000, tz=timezone.utc),
                    command=command,
                    cwd=cwd,
                    exit_code=exit_code,
                    duration=timedelta(microseconds=max(duration, 0) / 1000),
                    hostname=host,
                    user=user,
                    session=session,
                )


def failed() -> Iterator[Command]:
    """終了コードが 0 でないもの。-1 (終わりを見ていない) は除く。"""
    for c in commands():
        if c.finished and not c.succeeded:
            yield c


def stats() -> Stats:
    return {
        **stat(commands),
        **stat(failed),
    }
