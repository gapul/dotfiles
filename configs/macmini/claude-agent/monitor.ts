#!/usr/bin/env bun
// Check once an hour that claude-agent itself is still alive.
//
// Deliberately not run through the thing it watches (GitHub Actions). Monitoring
// built on top of the broken system goes quiet exactly when the system breaks, so
// this runs from launchd on the mac mini instead.
//
// Calling claude on every pass would be waste, so a cheap pass looks for the
// failures that are visible without it. When nothing is wrong it writes a heartbeat
// and stops; claude only gets involved when something is.
//
// The prompt stays Japanese: what it produces is read by a person.
//
// Ported from monitor.sh.
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import {
  LOG_FILE,
  STATE_DIR,
  acquireLock,
  ageSec,
  captureOr,
  dry,
  ensureParent,
  init,
  isDir,
  lastTagged,
  log,
  notify,
  nowSec,
  ok,
  olderThan,
  repoList,
  runClaude,
  setupGhToken,
  tailLines,
  words,
} from "./lib.ts";

// $(... || echo 0), then anything that is not a plain number counts as 0
const count = (s: string): number => (/^[0-9]+$/.test(s) ? Number(s) : 0);

export async function main(): Promise<number> {
  init();
  await setupGhToken();
  const HEARTBEAT = `${STATE_DIR}/monitor.heartbeat`;
  const NOW = nowSec();
  writeFileSync(HEARTBEAT, `${nowSec()}\n`);

  let ANOMALY = "";
  let DETAIL = "";
  const add = (s: string): void => {
    ANOMALY = `${ANOMALY}${s}; `;
    DETAIL = `${DETAIL}\n- ${s}`;
  };

  // --- machine-wide -------------------------------------------------------
  // Is the poller running at all? When launchd drops it, nothing happens and nothing
  // says so.
  if (existsSync(LOG_FILE)) {
    const age = ageSec(LOG_FILE) ?? NOW;
    if (age > 1800) {
      add("the poller has not written a log line in over 30 minutes (launchd may have stopped it)");
    }
  } else {
    add("there is no log file; the agent has never run");
  }

  // An expired login turns the whole thing into a system that quietly does nothing.
  // Match only the line runClaude writes. A bare 'not authenticated' also hits this
  // monitor's own anomaly/NOTIFY lines (e.g. "gh is not authenticated"), so one blip
  // kept re-raising itself every hour.
  if (existsSync(LOG_FILE)) {
    let text = "";
    try {
      text = readFileSync(LOG_FILE, "utf8");
    } catch {}
    if (tailLines(text, 500).some((l) => /NOTIFY\[[a-z]*\] claude-agent: not authenticated:/.test(l))) {
      add("Claude Code is not authenticated (claude setup-token needs redoing)");
    }
  }
  if (!(await ok(["gh", "auth", "status"], { stdout: "ignore", stderr: "ignore" }))) {
    add("gh is not authenticated");
  }

  // A kill switch left on and forgotten about
  if (existsSync(`${STATE_DIR}/PAUSE`)) {
    const age = ageSec(`${STATE_DIR}/PAUSE`) ?? 0;
    if (age > 86400) add("PAUSE has been in place for more than a day");
  }

  // A lock nobody released
  for (const name of readdirSync(STATE_DIR)
    .filter((f) => f.endsWith(".lock") && !f.startsWith("."))
    .sort()) {
    const l = `${STATE_DIR}/${name}`;
    if (!isDir(l)) continue;
    if (olderThan(l, 90, 60)) add(`a lock has been held for over 90 minutes: ${name}`);
  }

  // --- per repository -----------------------------------------------------
  for (const repo of words(repoList().map((l) => `${l}\n`).join(""))) {
    // For repositories that use self-hosted runners, check that one is online.
    const runners = await captureOr(
      ["gh", "api", `repos/${repo}/actions/runners`, "-q", '[.runners[] | select(.status=="online")] | length'],
      "",
    );
    const total = await captureOr(["gh", "api", `repos/${repo}/actions/runners`, "-q", ".runners | length"], "");
    if (total !== "" && total !== "0" && (runners || "0") === "0") {
      add(`${repo}: ${total} runners are registered but none are online`);
    }

    // Leftovers from a job that died
    const stale = count(
      await captureOr(
        [
          "gh",
          "issue",
          "list",
          "--repo",
          repo,
          "--label",
          "claude-in-progress",
          "--state",
          "open",
          "--json",
          "updatedAt",
          "-q",
          "[.[] | select((now - (.updatedAt|fromdateiso8601)) > 3600)] | length",
        ],
        "0",
      ),
    );
    if (stale > 0) add(`${repo}: ${stale} issues have been claude-in-progress for over an hour`);

    // Pull requests the agent opened that are stuck on a failing check
    const stuck = count(
      await captureOr(
        [
          "gh",
          "pr",
          "list",
          "--repo",
          repo,
          "--state",
          "open",
          "--limit",
          "30",
          "--json",
          "headRefName,statusCheckRollup",
          "-q",
          '[.[] | select(.headRefName | startswith("claude/")) | select([.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length > 0)] | length',
        ],
        "0",
      ),
    );
    if (stuck > 0) add(`${repo}: ${stuck} claude/* pull requests are stuck with failing checks`);
  }

  if (ANOMALY === "") {
    log("monitor: healthy (shell pass only, claude not called)");
    return 0;
  }

  log(`monitor: anomaly: ${ANOMALY}escalating to claude`);

  if (dry()) {
    log("DRY-RUN: would call claude to investigate here");
    return 0;
  }

  if (!acquireLock("claude", 60)) {
    log("another claude is running, investigating on the next pass");
    return 0;
  }

  const out = `${STATE_DIR}/logs/monitor.log`;
  ensureParent(out);
  const prompt = `あなたは macmini 上で動く自動修正・自動レビュー基盤 (claude-agent) の監視担当です。
シェルによる一次判定で次の異常が出ています。

${DETAIL}

対象リポジトリ: ${repoList()
    .map((l) => `${l} `)
    .join("")}
状態ディレクトリ: ${STATE_DIR} (agent.log にポーラーと修正の記録、logs/ に各実行の出力)

やること:
1. gh コマンドと ${STATE_DIR} のログを読んで、何が起きているかを特定する。
2. 自分で直せる範囲なら直す。具体的には次まで。
   - セルフホスト runner が落ちている場合の再起動 (sudo -n launchctl kickstart -k system/org.nixos.gh-runner。ログは ~/Library/Logs/gh-runner.log)
   - 90分以上残っている ${STATE_DIR} 配下のロックディレクトリの削除
   - 停滞している claude-in-progress ラベルの掛け直し (claude-failed へ)
3. リポジトリのコードには一切触らないこと。基盤の復旧だけが仕事で、コードの修正は run-autofix.ts の仕事。
4. 最後に、次の1行だけの形式で結果を書くこと。

REPORT: <何が起きていたか / 何をしたか / 人がやる必要が残っているか を1〜3文で>

人手が要るもの (認証の失効、GitHub 側の設定、ハードウェア) は自分で解決しようとせず、REPORT に書いて終わること。`;

  const rc = await runClaude(prompt, out, "--dangerously-skip-permissions", "--max-turns", "30");
  const report = lastTagged(out, "REPORT:");
  if (rc === 90) {
    // runClaude has already sent the not-authenticated notification
    return 1;
  }
  await notify(
    "claude-agent: anomaly detected",
    `${ANOMALY}\n${report || `(claude returned no REPORT line; see ${out})`}`,
    "high",
  );
  log(`monitor: ${report || "no REPORT line"}`);
  return 0;
}

if (import.meta.main) process.exit(await main());
