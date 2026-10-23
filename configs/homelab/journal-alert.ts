#!/usr/bin/env bun
// journald を追いかけて、壊れたときの合図を ntfy に流す。
//
// 収集そのものは要らない。全コンテナが log-driver=journald なので、ログは既に
// 1 箇所に集まっている。足りないのは「誰も見に行かない」ことの方で、
// 2026-08-16 に見つかった 6 件はどれも何日もログに書かれ続けていた。
//
// 誤検知で鳴り続けると読まなくなるので、拾うのは「放置すると壊れたままになる」
// ものだけに絞る。単発の ERROR は拾わない。
//
// Ported from configs/homelab/journal-alert.sh. Patterns, thresholds, state files and message
// text are unchanged. journalctl and systemctl are still called as commands; the grep/sort/awk
// pipelines over the snapshot are done in-process, and ntfy is reached with fetch.
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";

const TOKEN_FILE = "/var/lib/secrets/ntfy-alerts.token";
const NTFY_URL = "http://127.0.0.1:8082/alerts";

// fetch refuses non-ASCII header values, and the titles here are Japanese. ntfy reads every
// publish parameter from the query string as well, so title/priority/tags go there instead of
// the Title/Priority/Tags headers curl used to send.
async function notify(title: string, body: string, prio = "default"): Promise<void> {
  let token = "";
  try {
    token = readFileSync(TOKEN_FILE, "utf8").replace(/\n+$/, "");
  } catch (e) {
    // Same complaint `$(cat "$TOKEN_FILE")` left in the journal; the request still goes out.
    const code = (e as NodeJS.ErrnoException).code;
    const reason = code === "ENOENT" ? "No such file or directory" : code === "EACCES" ? "Permission denied" : String(e);
    process.stderr.write(`cat: ${TOKEN_FILE}: ${reason}\n`);
  }
  const url = new URL(NTFY_URL);
  url.searchParams.set("title", title);
  url.searchParams.set("priority", prio);
  url.searchParams.set("tags", "warning");
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body,
      signal: AbortSignal.timeout(10_000),
    });
    await res.body?.cancel();
  } catch {
    // curl -s ... || true: a lost notification must not fail the check.
  }
}

// 直らないものを 15 分おきに鳴らし続けない。
//
// 2026-09-13 に nixos-upgrade.service が failed のまま残り、この 1 件で 7 時間に
// 28 通鳴った。次の upgrade が走るまで failed は消えないので、検知は正しいのに
// 通知としては壊れている。読まなくなれば、隣に並んだ本物も見えなくなる。
//
// 状態が変わったら即座に鳴らす。変わらないなら 6 時間に 1 回まで。
// 直ったら記録を消して、再発は待たずに鳴らす。
const STATE_DIR = process.env.STATE_DIRECTORY || "/var/lib/journal-alert";
const REPEAT_AFTER = 21600;

mkdirSync(STATE_DIR, { recursive: true });

async function notifyOnce(key: string, fingerprint: string, title: string, body: string, prio = "default"): Promise<void> {
  const file = `${STATE_DIR}/${key}`;
  const now = Math.floor(Date.now() / 1000);
  let prevAt = 0;
  let prevFp = "";
  try {
    // 1 行目の "<epoch>\t<fingerprint>"。
    const line = readFileSync(file, "utf8").split("\n")[0].replace(/^\t+|\t+$/g, "");
    const tab = line.indexOf("\t");
    prevAt = Number.parseInt(tab < 0 ? line : line.slice(0, tab), 10) || 0;
    prevFp = tab < 0 ? "" : line.slice(tab + 1).replace(/^\t+/, "");
  } catch {
    // 記録が無い = 初回
  }

  if (fingerprint === prevFp && now - prevAt < REPEAT_AFTER) return;

  writeFileSync(file, `${now}\t${fingerprint}\n`);
  await notify(title, body, prio);
}

// 合図が消えたことを記録する。次に出たときは 6 時間を待たずに鳴る。
const clearOnce = (key: string): void => rmSync(`${STATE_DIR}/${key}`, { force: true });

// 拾う合図。左が journald の検索語、右が通知の見出し。
// 固定文字列で見る (正規表現にすると誤爆が増える)。
const PATTERNS: [needle: string, label: string][] = [
  ["Activating recovery mode", "Home Assistant が recovery mode に落ちた"],
  ["stale sessions detected", "free-games-claimer のストアセッションが切れた"],
  ["refusing to access private network", "miniflux が自前 RSSHub を読めていない"],
  ["Failed to establish secure session", "Matter のペアリングに失敗している"],
  ["Discovery timed out", "Matter がデバイスを見つけられない"],
  ["permission denied", "権限まわりで拒否されている"],
  // 2026-08-24 に足した分。どれもこの日に実際に起きて、誰も気付かなかったもの。
  // podman は bind mount の元ディレクトリを作らないので、新しいスタックを足すと
  // ここで止まる。rebuild ごと exit 4 になるが、ログを見なければ分からない。
  ["no such file or directory", "コンテナの bind mount 先が無い"],
  // restart を繰り返して systemd が諦めた状態。ユニットは failed のままになる。
  // ただしこれは「諦めた」ときにしか出ない。諦めずに回り続ける方は下で別に見る。
  ["Start request repeated too quickly", "再起動を繰り返して止まった"],
  // tmpfiles が uid の食い違いで配下の作成を拒否する。移行の残骸で出る。
  ["unsafe path transition", "tmpfiles が所有者の食い違いで作成を拒否した"],
  // Lazy containers may exit 137 when Podman finishes an intentional stop with
  // SIGKILL. Systemd accepts that transition; a real memory kill is still
  // unambiguous in the kernel's journal and must remain visible.
  ["oom-kill", "メモリ不足でプロセスが強制終了された"],
];

const SINCE = Bun.argv[2] || "-15min";
const window = SINCE.replace(/^-/, "");

// Output lines of a command, as `cmd | while read` would see them. Missing or failing commands
// give no lines, like the `2>/dev/null` they were run with.
function lines(cmd: string[]): string[] {
  if (!Bun.which(cmd[0])) return [];
  const p = Bun.spawnSync(cmd, { stdin: "ignore", stdout: "pipe", stderr: "ignore" });
  const text = p.stdout.toString();
  if (text === "") return [];
  return text.replace(/\n$/, "").split("\n");
}

// `cut -c1-200`: GNU cut counts bytes. Stop short of a split character instead of sending a
// broken UTF-8 sequence.
function cut200(line: string): string {
  const bytes = Buffer.from(line, "utf8");
  if (bytes.length <= 200) return line;
  let end = 200;
  while (end > 0 && (bytes[end] & 0xc0) === 0x80) end--;
  return bytes.subarray(0, end).toString("utf8");
}

// journald は 1 回だけ読む。パターンごとに読み直すと、パターンを増やすたびに
// 走査回数が倍々に増える (9 個で 18 回。12 時間分だと数分かかった)。
const SNAP = lines(["journalctl", "--since", SINCE, "--no-pager"]);

for (const [needle, label] of PATTERNS) {
  // 状態キーは検索語から作る。見出しは日本語なのでファイル名に向かない。
  const key = `pattern-${needle.replace(/[^A-Za-z0-9]/g, "-")}`;
  const matching = SNAP.filter((l) => l.includes(needle));
  if (matching.length > 0) {
    const sample = cut200(matching[matching.length - 1]);
    // 件数は毎回変わるので指紋に入れない。入れると間引きが効かなくなる。
    await notifyOnce(key, needle, label, `直近 ${window} で ${matching.length} 件\n${sample}`, "high");
  } else {
    clearOnce(key);
  }
}

// 同じユニットが何度も失敗し続けている状態。
//
// これが無くて 2026-08-28 の romm-db を 2 日間見逃した。tc.log が壊れて MariaDB が
// 毎回 abort していたのに、Restart=always で回り続けたので systemd は諦めず、
// 上の "Start request repeated too quickly" も --failed も一度も引っかからなかった。
// journald には 5948 件の失敗が並んでいた。
//
// 諦めたものは failed になるので捕まる。捕まらないのは諦めずに壊れ続ける方で、
// 稼働中に見えるぶんこちらの方が長く放置される。
// 5 回。deploy で数回失敗するのは普通なので、そこは鳴らさない。
// 壊れて回り続けるものは桁が違う (romm-db は 28 分で 200 回だった)。
const LOOP_THRESHOLD = 5;
// podman が内部で作る 16 進名のユニット (64桁-16桁) は中身を指さないので飛ばす。
// glob だと attic-db.service のような普通の名前まで巻き込むので、桁数で見る。
const TRANSIENT = /^[0-9a-f]{64}-[0-9a-f]{16}\.service$/;

const failures = new Map<string, number>();
for (const line of SNAP) {
  for (const m of line.matchAll(/([A-Za-z0-9@_.-]+\.service): Failed with result/g)) {
    failures.set(m[1], (failures.get(m[1]) ?? 0) + 1);
  }
}
// sort | uniq -c | sort -rn: 回数の多い順、同数は名前の逆順。
const byCount = [...failures].sort(([ua, a], [ub, b]) => b - a || (ua < ub ? 1 : ua > ub ? -1 : 0));

// 今回暴れていたユニット。
const looping = new Set<string>();
for (const [unit, count] of byCount) {
  if (count < LOOP_THRESHOLD) continue;
  if (TRANSIENT.test(unit)) continue;
  const related = SNAP.filter((l) => l.includes(unit) && !l.toLowerCase().includes("failed with result"));
  const sample = related.length > 0 ? cut200(related[related.length - 1]) : "";
  looping.add(`loop-${unit}`);
  await notifyOnce(
    `loop-${unit}`,
    unit,
    `${unit} が失敗を繰り返している`,
    `直近 ${window} で ${count} 回失敗。稼働中に見えても中身は起動できていない。\n${sample}`,
    "high",
  );
}

// 収まったユニットの記録は消す。残したままだと、6 時間以内に暴れ直したときに
// 間引きに引っかかって黙る。これは 2026-08-28 の romm-db のような、
// 直ったように見えて再発する壊れ方をちょうど取りこぼす。
for (const state of readdirSync(STATE_DIR)) {
  if (state.startsWith("loop-") && !looping.has(state)) rmSync(`${STATE_DIR}/${state}`, { force: true });
}

// 落ちたユニット。systemd が知っているのに誰も見ていない典型。
//
// 2026-08-30 に 3 日で 26 回鳴っていて、しかも本文が "●" だけだった。原因が 2 つ:
//
//   1. --no-legend でも先頭の状態マーク "●" は消えないので、awk '{print $1}' が
//      ユニット名ではなくマークを拾っていた。名前が出ないので通知として無意味。
//   2. podman が healthcheck ごとに作る使い捨てユニット (64桁-16桁の 16 進名) が
//      DB の起動待ちなどで普通に失敗する。実害が無いのに毎回鳴るので、
//      本物が混ざっていても気付けなくなる。
//
// --plain でマークを外し、16 進の使い捨ては除く。再起動ループ検知と同じ判定。
// 各行の先頭の欄を空白区切りで並べる (末尾にも空白が付く。指紋はこの形のまま)。
const failed = lines(["systemctl", "--failed", "--no-legend", "--plain", "--no-pager"])
  .map((l) => l.trim().split(/[ \t]+/)[0])
  .filter((unit) => !TRANSIENT.test(unit))
  .map((unit) => `${unit} `)
  .join("");
if (failed.replaceAll(" ", "") !== "") {
  // 顔ぶれが変わったら鳴らす。同じままなら 6 時間に 1 回。
  await notifyOnce("failed-units", failed, "failed unit がある", failed, "high");
} else {
  clearOnce("failed-units");
}

// restic の鮮度。転送が黙って止まるのはこの構成で実績がある
// (rclone の Google Drive トークンが 1 週間で失効する)。
const resticFailed =
  Bun.which("systemctl") !== null &&
  Bun.spawnSync(["systemctl", "is-failed", "--quiet", "restic-backups-homeserver.service"], {
    stdin: "ignore",
    stdout: "ignore",
    stderr: "inherit",
  }).exitCode === 0;
if (resticFailed) {
  await notifyOnce("restic", "failed", "restic のバックアップが失敗している", "systemctl status restic-backups-homeserver", "high");
} else {
  clearOnce("restic");
}
