#!/usr/bin/env bun
// The fixing half of claude-agent. Handles both issue-driven work and failed
// GitHub Actions runs.
//
//   run-autofix.ts <owner/repo> issue:<number>
//   run-autofix.ts <owner/repo> run:<run id>
//
// The poller and the per-repository caller workflow (running on the self-hosted
// runner on this same machine) both come through here. This script always owns its
// working tree, so callers do not need to check anything out.
//
// Text posted to GitHub stays Japanese: it is prose addressed to the people reading
// those issues and pull requests.
//
// Ported from run-autofix.sh.
import { readFileSync, rmSync, statSync, writeFileSync, writeSync } from "node:fs";
import {
  MARK,
  STATE_DIR,
  acquireLock,
  capture,
  captureMerged,
  captureOr,
  cat,
  dry,
  ensureParent,
  captureStdout,
  init,
  isTrue,
  lastTagged,
  log,
  markSeen,
  notify,
  ok,
  olderThan,
  paused,
  policy,
  prepareRepo,
  repoAllowed,
  repoEntry,
  run,
  runClaude,
  runToFile,
  seen,
  seenPath,
  setupGhToken,
  tailLines,
  trustedAssociation,
} from "./lib.ts";

let REPO = "";
let ID = "";
let BASE = "";

// Attempt cap, counted over 24 hours. Hammering at something unfixable forever is
// the worst failure mode available, so give up quietly instead.
function attemptsOk(key: string, cap: number): boolean {
  const f = seenPath(`attempts/${key}`);
  ensureParent(f);
  // forget counts older than a day
  if (olderThan(f, 1, 86400)) rmSync(f, { force: true });
  const raw = cat(f) ?? "0";
  const n = /^[0-9]+$/.test(raw) ? Number(raw) : 0;
  if (n >= cap) {
    log(`attempt cap reached (${cap} per 24h): ${key}`);
    return false;
  }
  writeFileSync(f, `${n + 1}\n`);
  return true;
}

// The parts of `gh ... --json` output the shell version read with `jq -r`. Output
// that is not JSON reads as empty strings, as the failed jq calls did.
function jqFields(meta: string, pick: (j: Record<string, unknown>) => Record<string, unknown>): Record<string, string> {
  let j: unknown;
  try {
    j = JSON.parse(meta);
  } catch {
    return {};
  }
  if (j === null || typeof j !== "object" || Array.isArray(j)) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(pick(j as Record<string, unknown>))) {
    if (v === undefined) continue;
    out[k] = (typeof v === "string" ? v : v === null ? "null" : JSON.stringify(v, null, 2)).replace(/\n+$/, "");
  }
  return out;
}

// (.ignore_workflows // []) | join("\n"), read back line by line with `IFS= read -r`
// (so nothing is trimmed). join turns null into "" and numbers/booleans into text;
// anything else is a jq error, which left the list empty.
function ignoredWorkflows(v: unknown): string {
  if (v === undefined || v === null || v === false) return "";
  const items = Array.isArray(v) ? v : typeof v === "object" ? Object.values(v) : undefined;
  if (items === undefined) return "";
  const parts: string[] = [];
  for (const x of items) {
    if (x === null) parts.push("");
    else if (typeof x === "string") parts.push(x);
    else if (typeof x === "number" || typeof x === "boolean") parts.push(String(x));
    else return "";
  }
  return parts.join("\n");
}

// [.labels[].name] | join(",")
function labelNames(labels: unknown): string | undefined {
  if (!Array.isArray(labels)) return undefined;
  return labels.map((l) => (l && typeof l === "object" ? ((l as { name?: unknown }).name ?? "") : "")).join(",");
}

// ---------------------------------------------------------------- issues
async function runIssue(): Promise<number> {
  const n = ID;
  if (!isTrue(policy(REPO, "autofix_issues", "true"))) {
    log(`autofix_issues=false: ${REPO}`);
    return 0;
  }

  const meta = await capture(["gh", "issue", "view", n, "--repo", REPO, "--json", "number,title,body,state,updatedAt,labels"]);
  if (meta === "") {
    log(`cannot read issue #${n}: ${REPO}`);
    return 1;
  }

  const f = jqFields(meta, (j) => ({
    state: j.state,
    labels: labelNames(j.labels),
    title: j.title,
    body: j.body,
    updated: j.updatedAt,
  }));
  const state = f.state ?? "";
  const labels = f.labels ?? "";
  const title = f.title ?? "";
  const body = f.body ?? "";
  const updated = f.updated ?? "";

  if (state !== "OPEN") {
    log(`issue #${n} is not open`);
    return 0;
  }
  if (`,${labels},`.includes(",no-claude,")) {
    log(`labelled no-claude: #${n}`);
    return 0;
  }
  if (seen(`${REPO}/issue-${n}/${updated}`)) {
    log(`already handled: #${n} (${updated})`);
    return 0;
  }

  // A stranger's issue is never handed to claude, not even when labelled claude-fix:
  // the body is still their text. Restate it in an issue of your own instead.
  const assoc = await capture(["gh", "api", `repos/${REPO}/issues/${n}`, "-q", ".author_association"]);
  if (!trustedAssociation(assoc)) {
    log(`issue #${n} is by an outside author (${assoc || "unknown"}), leaving it alone`);
    markSeen(`${REPO}/issue-${n}/${updated}`);
    return 0;
  }
  if (!attemptsOk(`${REPO}/issue-${n}`, 3)) return 0;

  const note = async (text: string): Promise<void> =>
    void await run(["gh", "issue", "comment", n, "--repo", REPO, "--body", `${text}\n${MARK}`], { stdout: "ignore", stderr: "ignore" });
  const label = async (...args: string[]): Promise<void> =>
    void await run(["gh", "issue", "edit", n, "--repo", REPO, ...args], { stdout: "ignore", stderr: "ignore" });
  const updatedNow = async (): Promise<string> => await capture(["gh", "issue", "view", n, "--repo", REPO, "--json", "updatedAt", "-q", ".updatedAt"]);

  if (dry()) {
    log(`DRY-RUN: would fix issue #${n} (${title})`);
    markSeen(`${REPO}/issue-${n}/${updated}`);
    return 0;
  }

  await label("--add-label", "claude-in-progress");
  await label("--remove-label", "claude-needs-info");

  if (!(await prepareRepo(REPO, `origin/${BASE}`))) {
    await label("--remove-label", "claude-in-progress", "--add-label", "claude-failed");
    return 1;
  }
  const branch = `claude/issue-${n}`;
  if (!(await ok(["git", "checkout", "--quiet", "-B", branch]))) return 1;

  // Feed the thread back in as context (answers to earlier questions and so on),
  // minus the bot's own comments and anything from outside authors.
  const raw = (await run(
    [
      "gh",
      "api",
      "--paginate",
      `repos/${REPO}/issues/${n}/comments`,
      "-q",
      `.[] | select(.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))
          | "--- " + .user.login + ":\\n" + .body`,
    ],
    { stdout: "pipe", stderr: "ignore" },
  )).stdout;
  const rawLines = raw.split("\n");
  if (rawLines[rawLines.length - 1] === "") rawLines.pop();
  // grep -v "$MARK" drops single lines, not whole comments
  const thread = rawLines
    .filter((l) => !l.includes(MARK))
    .join("\n")
    .replace(/\n+$/, "");

  const logFile = `${STATE_DIR}/logs/issue-${n}.log`;
  ensureParent(logFile);
  const prompt = `あなたは GitHub issue を自動修正するエンジニアです。リポジトリ ${REPO} で issue #${n} を実装してください。

タイトル: ${title}

本文:
${body}

これまでのコメント (人からの追加指示・質問への回答を含む):
${thread || "（コメントなし）"}

要件:
- まず、要望された機能・修正がコードベースに既に存在しないか調べること。利用者は仕様を知らないことが多い。既に同等の機能がある場合はコードを変更せず、出力の最後の行に「EXISTS: <既にある機能の説明を2〜3文で。どこにあるか含める>」と書いて終了する。
- 一部だけ足りない場合は、既にある部分は触らず、本当に必要な差分だけ実装する。
- 変更は最小限で、既存のコードスタイルに合わせる。
- 検証: ${policy(REPO, "verify_hint", "関連するビルド・テストがあればローカルで実行して通すこと。")}
- コミットはしないでよい (このスクリプトが行う)。
- 情報が足りず実装できない場合は、コードを一切変更せず、出力の最後の行に「QUESTION: <確認したい具体的な質問>」の形式で1行だけ書いて終了すること。推測で危険な実装をするより質問を優先する。
(EXISTS と QUESTION を同時に出さないこと。既にあるなら EXISTS を優先。)`;

  log(`running claude: ${REPO} issue #${n}`);
  const rc = await runClaude(prompt, logFile, "--dangerously-skip-permissions", "--max-turns", "60");
  if (rc === 90) {
    await label("--remove-label", "claude-in-progress", "--add-label", "claude-failed");
    return 1;
  }

  if (await captureStdout(["git", "status", "--porcelain"]) === "") {
    // No code changed. Prefer EXISTS (it already exists) over QUESTION (needs
    // information) over outright failure.
    const ex = lastTagged(logFile, "EXISTS:");
    const q = lastTagged(logFile, "QUESTION:");
    if (ex) {
      await note(`🤖 これはすでにある機能かもしれません。

${ex}

これのことでしょうか。違っていれば、この issue に返信いただければ実装します。`);
      await label("--remove-label", "claude-in-progress", "--add-label", "claude-needs-info");
    } else if (q) {
      await note(`🤖 実装する前に確認させてください。

${q}

この issue に返信いただければ続きを進めます。`);
      await label("--remove-label", "claude-in-progress", "--add-label", "claude-needs-info");
    } else {
      await note(
        "🤖 確認しましたが、コード変更は生成されませんでした。指示を具体化して `claude-fix` ラベルを付け直すと再実行します。",
      );
      await label("--remove-label", "claude-in-progress", "--add-label", "claude-failed");
    }
    markSeen(`${REPO}/issue-${n}/${updated}`);
    markSeen(`${REPO}/issue-${n}/${await updatedNow()}`);
    return 0;
  }

  await run(["git", "add", "-A"]);
  await run([
    "git",
    "commit",
    "-q",
    "-m",
    `fix: #${n} ${title}

Closes #${n}

🤖 auto-fixed by Claude Code on macmini`,
  ]);
  if (!(await ok(["git", "push", "-f", "origin", branch]))) {
    await label("--remove-label", "claude-in-progress", "--add-label", "claude-failed");
    return 1;
  }

  const prUrl = await openOrCreatePr(
    branch,
    `fix: #${n} ${title}`,
    `Closes #${n}

🤖 Claude Code (macmini) による自動修正。
${MARK}`,
  );
  if (prUrl === "") {
    await note(
      `🤖 修正は push しましたが (ブランチ \`${branch}\`)、PR の URL が取得できませんでした。手動で PR を作るか、\`claude-fix\` ラベルを付け直すと再実行します。`,
    );
    await label("--remove-label", "claude-in-progress", "--add-label", "claude-failed");
    return 1;
  }
  await label("--remove-label", "claude-in-progress", "--add-label", "claude-done");
  await note(`🤖 修正して PR を作成しました: ${prUrl}`);
  markSeen(`${REPO}/issue-${n}/${updated}`);
  markSeen(`${REPO}/issue-${n}/${await updatedNow()}`);
  log(`done: ${prUrl}`);
  return 0;
}

// Open the pull request. gh occasionally fails transiently without returning a URL,
// so retry a few times and pick up an existing PR if there is one. Only the URL is
// returned; the log lines go to stderr as before.
async function openOrCreatePr(branch: string, title: string, body: string): Promise<string> {
  for (let attempt = 1; attempt <= 3; attempt++) {
    let url = await capture(["gh", "pr", "list", "--repo", REPO, "--head", branch, "--json", "url", "-q", ".[0].url"]);
    if (url !== "") return url;
    const { out } = await captureMerged([
      "gh",
      "pr",
      "create",
      "--repo",
      REPO,
      "--base",
      BASE,
      "--head",
      branch,
      "--title",
      title,
      "--body",
      body,
    ]);
    // To stderr: callers use the return value as the URL, and an empty one is how they see failure.
    log(`gh pr create (attempt ${attempt}): ${out}`, 2);
    const hits = `${out}\n`
      .split("\n")
      .flatMap((l) => l.match(/https:\/\/github.com\/[^\s]*\/pull\/[0-9][0-9]*/g) ?? []);
    url = hits[hits.length - 1] ?? "";
    if (url !== "") return url;
    await Bun.sleep(5000);
  }
  return "";
}

// ------------------------------------------------- failed Actions runs
// Infrastructure failures are separated out: no code change fixes a dead runner, a
// broken network, a rate limit, a full disk, or a job that ran out of time.
function infraFailure(path: string): boolean {
  return /lost communication with the server|has not been able to communicate|Waiting for a runner|no space left on device|Could not resolve host|429 Too Many Requests|You have exceeded a secondary rate limit|The operation was canceled|exceeded the maximum execution time|The runner has received a shutdown signal/.test(
    readFileSync(path, "latin1"),
  );
}

async function runCi(): Promise<number> {
  const id = ID;
  if (!isTrue(policy(REPO, "autofix_ci", "true"))) {
    log(`autofix_ci=false: ${REPO}`);
    return 0;
  }

  const meta = await capture([
    "gh",
    "run",
    "view",
    id,
    "--repo",
    REPO,
    "--json",
    "databaseId,workflowName,headBranch,headSha,conclusion,event,createdAt",
  ]);
  if (meta === "") {
    log(`cannot read run ${id}: ${REPO}`);
    return 1;
  }

  const f = jqFields(meta, (j) => ({ wf: j.workflowName, branch: j.headBranch, sha: j.headSha, conclusion: j.conclusion }));
  const wf = f.wf ?? "";
  const branch = f.branch ?? "";
  const sha = f.sha ?? "";
  const conclusion = f.conclusion ?? "";

  if (conclusion !== "failure") {
    log(`run ${id} did not fail (${conclusion})`);
    return 0;
  }

  // A run for a fork's pull request: its log is output the fork's code chose to print,
  // so it does not go into a prompt. A fork PR whose branch happens to be named like
  // the base would otherwise even get past the "not on origin" check further down.
  const headRepo = await capture(["gh", "api", `repos/${REPO}/actions/runs/${id}`, "-q", ".head_repository.full_name"]);
  if (headRepo !== REPO) {
    log(`run ${id} is from ${headRepo || "an unknown repository"}, not ${REPO}; leaving it alone`);
    markSeen(`${REPO}/run-${id}`);
    return 0;
  }

  // Never react to claude-agent's own workflows. This is where the loop of trying to
  // fix its own failure forever gets cut.
  const entry = repoEntry(REPO);
  for (const w of ignoredWorkflows(entry?.ignore_workflows).split("\n")) {
    if (w !== "" && w === wf) {
      log(`own workflow, ignoring: ${wf}`);
      return 0;
    }
  }

  if (seen(`${REPO}/run-${id}`)) {
    log(`already handled: run ${id}`);
    return 0;
  }

  // If the same workflow on the same branch has succeeded since, it is already
  // fixed. A flaky run that passed on retry drops out here too.
  const newerRaw = await captureOr(
    [
      "gh",
      "run",
      "list",
      "--repo",
      REPO,
      "--workflow",
      wf,
      "--branch",
      branch,
      "--limit",
      "10",
      "--json",
      "databaseId,conclusion,createdAt",
      "-q",
      `[.[] | select(.databaseId > ${id} and .conclusion == "success")] | length`,
    ],
    "0",
  );
  const newerOk = /^[0-9]+$/.test(newerRaw) ? Number(newerRaw) : 0;
  if (newerOk > 0) {
    log(`a later run succeeded, nothing to do (flaky or already fixed): ${wf} / ${branch}`);
    markSeen(`${REPO}/run-${id}`);
    return 0;
  }

  if (!attemptsOk(`${REPO}/ci/${wf}/${branch}`, 2)) {
    markSeen(`${REPO}/run-${id}`);
    return 0;
  }

  const logRaw = `${STATE_DIR}/logs/run-${id}.txt`;
  ensureParent(logRaw);
  await runToFile(["gh", "run", "view", id, "--repo", REPO, "--log-failed"], logRaw, { stderr: "ignore" });
  if (statSync(logRaw).size === 0) {
    log(`no failure log for run ${id}; the job probably never started, treating as infrastructure`);
    await notify("claude-agent: CI failed with no log", `${REPO} / ${wf} / ${branch} run ${id} died without leaving a failure log.`, "high");
    markSeen(`${REPO}/run-${id}`);
    return 0;
  }
  if (infraFailure(logRaw)) {
    log(`infrastructure failure, leaving the code alone: ${wf} / ${branch}`);
    await notify(
      "claude-agent: CI failed on infrastructure",
      `${REPO} / ${wf} / ${branch} (run ${id}). Runner, network or rate limit. Log: ${logRaw}`,
      "high",
    );
    markSeen(`${REPO}/run-${id}`);
    return 0;
  }

  if (dry()) {
    log(`DRY-RUN: would fix ${wf} in ${REPO} (${branch}, run ${id})`);
    markSeen(`${REPO}/run-${id}`);
    return 0;
  }

  // Decide where the fix lands. A failure on a pull request branch gets a commit on
  // that branch so the PR moves forward; a failure on the base branch gets its own
  // branch and a new PR.
  let workBranch: string;
  let newBranch = false;
  if (branch === BASE || branch === "") {
    workBranch = `claude/ci-${id}`;
    newBranch = true;
    if (!(await prepareRepo(REPO, sha))) return 1;
    if (!(await ok(["git", "checkout", "--quiet", "-B", workBranch]))) return 1;
  } else {
    workBranch = branch;
    if (!(await prepareRepo(REPO, `origin/${BASE}`))) return 1;
    if (!(await ok(["git", "checkout", "--quiet", "-B", workBranch, `origin/${workBranch}`]))) {
      log(`branch ${workBranch} is not on origin (looks like a fork PR), leaving it alone`);
      markSeen(`${REPO}/run-${id}`);
      return 0;
    }
  }

  const logFile = `${STATE_DIR}/logs/ci-${id}.log`;
  const failed = tailLines(readFileSync(logRaw, "utf8"), 400).join("\n").replace(/\n+$/, "");
  const prompt = `あなたは壊れた CI を直すエンジニアです。リポジトリ ${REPO} のワークフロー「${wf}」が、ブランチ ${branch} (commit ${sha}) で失敗しました。

以下は失敗したジョブのログです (末尾 400 行)。

${failed}

要件:
- 失敗の根本原因を直すこと。
- テストを削る、skip する、アサーションを緩める、continue-on-error を足す、といった「通すためだけの変更」は禁止。それをしたくなったら、代わりに何もせず最後の行に「UNCLEAR: <理由>」と書いて終了すること。
- 変更は失敗の原因に関係する範囲だけに絞る。ついでの整理はしない。
- 検証: ${policy(REPO, "verify_hint", "直したら、落ちていたのと同じコマンドをローカルで実行して通ることを確かめること。")}
- コミットはしないでよい (このスクリプトが行う)。
- 原因が特定できない場合も、コードを変更せず最後の行に「UNCLEAR: <調べたことと、分からなかった点>」と1行で書いて終了すること。`;

  log(`running claude: ${REPO} CI ${wf} (run ${id})`);
  const rc = await runClaude(prompt, logFile, "--dangerously-skip-permissions", "--max-turns", "60");
  if (rc === 90) return 1;

  if (await captureStdout(["git", "status", "--porcelain"]) === "") {
    const unclear = lastTagged(logFile, "UNCLEAR:");
    await notify(
      "claude-agent: could not fix CI",
      `${REPO} / ${wf} / ${branch} (run ${id})\n${unclear || "no code change was produced"}`,
      "high",
    );
    markSeen(`${REPO}/run-${id}`);
    return 0;
  }

  await run(["git", "add", "-A"]);
  await run([
    "git",
    "commit",
    "-q",
    "-m",
    `fix(ci): repair the failing ${wf} run

Failed run: https://github.com/${REPO}/actions/runs/${id}

🤖 auto-fixed by Claude Code on macmini`,
  ]);
  if (!(await ok(["git", "push", "origin", workBranch]))) {
    log(`push failed: ${workBranch}`);
    return 1;
  }

  if (newBranch) {
    const prUrl = await openOrCreatePr(
      workBranch,
      `fix(ci): repair the failing ${wf} run`,
      `${BASE} で「${wf}」が失敗していたので直しました。

失敗した run: https://github.com/${REPO}/actions/runs/${id}

🤖 Claude Code (macmini) による自動修正。
${MARK}`,
    );
    if (prUrl === "") {
      // Nothing points at this branch, so it would stay on origin forever. It has happened with
      // "No commits between main and claude/ci-*" (the fix was already on main), leaving a
      // dozen of them behind by 2026-10-18.
      log(`no PR for ${workBranch}, deleting the branch`);
      if (!(await ok(["git", "push", "--quiet", "origin", "--delete", workBranch]))) log(`could not delete ${workBranch}`);
    } else {
      log(`done: ${prUrl}`);
    }
  } else {
    log(`done: pushed a fix to ${workBranch} (the existing PR reruns CI)`);
  }
  markSeen(`${REPO}/run-${id}`);
  return 0;
}

const USAGE = "usage: run-autofix.ts <owner/repo> issue:<n>|run:<id>";

export async function main(args: string[]): Promise<number> {
  init();
  // ${1:?usage} and ${2:?usage}
  if (!args[0] || !args[1]) {
    writeSync(2, `run-autofix.ts: ${args[0] ? 2 : 1}: ${USAGE}\n`);
    return 1;
  }
  REPO = args[0];
  const target = args[1];
  const colon = target.indexOf(":");
  const kind = colon < 0 ? target : target.slice(0, colon);
  ID = colon < 0 ? target : target.slice(colon + 1);

  if (paused()) return 0;
  if (!repoAllowed(REPO)) {
    log(`not in repos.json, doing nothing: ${REPO}`);
    return 0;
  }
  await setupGhToken();

  BASE = policy(REPO, "base", "main");

  if (!acquireLock("claude", 60)) {
    log(`another claude is running, deferring: ${REPO} ${target}`);
    return 0;
  }

  switch (kind) {
    case "issue":
      return await runIssue();
    case "run":
      return await runCi();
    default:
      log(`unknown target: ${target}`);
      return 2;
  }
}

if (import.meta.main) process.exit(await main(process.argv.slice(2)));
