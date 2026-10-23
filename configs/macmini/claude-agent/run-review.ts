#!/usr/bin/env bun
// Read a pull request and leave a review.
//
//   run-review.ts <owner/repo> <pr number>
//
// Other people's pull requests are in scope, which is why this is the one place
// claude runs read-only. Once a fork's code is on the machine, building or testing
// it is the same thing as executing it; reading it is harmless whatever it contains.
//
// Intervention stops at comments and suggestions. Nothing is pushed to someone
// else's branch, and neither REQUEST_CHANGES nor APPROVE is ever submitted — a bot
// should not be able to block a person's pull request.
//
// The review text itself stays Japanese: it is prose for the people reading it.
//
// Ported from run-review.sh. The REVIEW_JSON handling that was jq follows jq's rules
// (null is the identity for +, type errors make the whole result empty) so a strange
// answer from claude ends up where it did before.
import { copyFileSync, readFileSync, statSync, writeFileSync, writeSync } from "node:fs";
import {
  MARK,
  STATE_DIR,
  acquireLock,
  capture,
  captureOr,
  cat,
  compactStamp,
  dry,
  ensureParent,
  init,
  isTrue,
  jqRaw,
  log,
  markSeen,
  notify,
  ok,
  paused,
  policy,
  prepareRepo,
  repoAllowed,
  runClaude,
  runToFile,
  seen,
  seenPath,
  setupGhToken,
} from "./lib.ts";

// --- the few jq semantics the review output relies on ---------------------
class JqError extends Error {}

const jqType = (v: unknown): string =>
  v === null || v === undefined ? "null" : Array.isArray(v) ? "array" : typeof v === "object" ? "object" : typeof v;

// jq's +: null is the identity; strings concatenate, numbers add.
function jqAdd(a: unknown, b: unknown): unknown {
  if (a === null || a === undefined) return b ?? null;
  if (b === null || b === undefined) return a;
  if (typeof a === "string" && typeof b === "string") return a + b;
  if (typeof a === "number" && typeof b === "number") return a + b;
  throw new JqError(`${jqType(a)} and ${jqType(b)} cannot be added`);
}
const add = (...xs: unknown[]): unknown => xs.reduce((acc, x) => jqAdd(acc, x));

// .field on an object or null
function idx(v: unknown, k: string): unknown {
  if (v === null || v === undefined) return null;
  if (typeof v === "object" && !Array.isArray(v)) return (v as Record<string, unknown>)[k] ?? null;
  throw new JqError(`cannot index ${jqType(v)}`);
}

// a // b
const alt = (a: unknown, b: unknown): unknown => (a === null || a === undefined || a === false ? b : a);

function toNumber(v: unknown): number {
  if (typeof v === "number") return v;
  if (typeof v === "string" && /^\s*-?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\s*$/.test(v)) return Number(v);
  throw new JqError("cannot be parsed as a number");
}

const toStr = (v: unknown): string => (typeof v === "string" ? v : JSON.stringify(v ?? null));

function length(v: unknown): number {
  if (v === null || v === undefined) return 0;
  if (typeof v === "number") return Math.abs(v);
  if (typeof v === "string") return [...v].length;
  if (Array.isArray(v)) return v.length;
  if (typeof v === "object") return Object.keys(v).length;
  throw new JqError("boolean has no length");
}

// .[] over an array or object
function iter(v: unknown): unknown[] {
  if (Array.isArray(v)) return v;
  if (v !== null && typeof v === "object") return Object.values(v);
  throw new JqError(`cannot iterate over ${jqType(v)}`);
}

// Evaluate like `jq ...` inside $(...): the text, or "" if jq stopped on an error.
function jq(f: () => string): string {
  try {
    return f().replace(/\n+$/, "");
  } catch (e) {
    if (e instanceof JqError) return "";
    throw e;
  }
}

// jq -c output: like JSON.stringify, but DEL is escaped too.
const compact = (v: unknown): string => JSON.stringify(v).replaceAll("\x7f", "\\u007f");

const suggestionBlock = (c: unknown): unknown =>
  alt(idx(c, "suggestion"), "") === "" ? "" : add("\n\n```suggestion\n", idx(c, "suggestion"), "\n```");

// The last <<<REVIEW_JSON ... REVIEW_JSON block of claude's output.
function extractReview(path: string): string {
  const lines = readFileSync(path, "utf8").split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  let flag = false;
  let buf = "";
  let last = "";
  for (const l of lines) {
    if (l === "<<<REVIEW_JSON") {
      flag = true;
      buf = "";
      continue;
    }
    if (l === "REVIEW_JSON") {
      flag = false;
      last = buf;
      continue;
    }
    if (flag) buf += `${l}\n`;
  }
  return last.replace(/\n+$/, "");
}

export async function main(args: string[]): Promise<number> {
  init();
  // ${1:?usage} and ${2:?usage}
  if (!args[0] || !args[1]) {
    writeSync(2, `run-review.ts: ${args[0] ? 2 : 1}: usage: run-review.ts <owner/repo> <pr>\n`);
    return 1;
  }
  const REPO = args[0];
  const PR = args[1];

  if (paused()) return 0;
  if (!repoAllowed(REPO)) {
    log(`not in repos.json, doing nothing: ${REPO}`);
    return 0;
  }
  if (!isTrue(policy(REPO, "review", "true"))) {
    log(`review=false: ${REPO}`);
    return 0;
  }
  await setupGhToken();

  const ME = await captureOr(["gh", "api", "user", "-q", ".login"], "gapul");

  const meta = await capture([
    "gh",
    "pr",
    "view",
    PR,
    "--repo",
    REPO,
    "--json",
    "number,title,body,state,isDraft,author,headRefName,headRefOid,labels,additions,deletions,changedFiles",
  ]);
  if (meta === "") {
    log(`cannot read PR #${PR}: ${REPO}`);
    return 1;
  }

  let m: unknown = undefined;
  let parsed = true;
  try {
    m = JSON.parse(meta);
  } catch {
    parsed = false;
  }
  // jq -r <field> <<<"$meta"
  const field = (f: () => string): string => (parsed ? jq(f) : "");
  const state = field(() => jqRaw(idx(m, "state")));
  const draft = field(() => jqRaw(idx(m, "isDraft")));
  const author = field(() => jqRaw(idx(idx(m, "author"), "login")));
  const title = field(() => jqRaw(idx(m, "title")));
  const body = field(() => jqRaw(idx(m, "body")));
  const sha = field(() => jqRaw(idx(m, "headRefOid")));
  const labels = field(() =>
    iter(idx(m, "labels"))
      .map((l) => {
        const n = idx(l, "name");
        return n === null ? "" : toStr(n);
      })
      .join(","),
  );
  let changed = field(() => jqRaw(idx(m, "changedFiles")));

  if (state !== "OPEN") {
    log(`PR #${PR} is not open`);
    return 0;
  }
  if (isTrue(draft)) {
    log(`draft, skipping: PR #${PR}`);
    return 0;
  }
  if (`,${labels},`.includes(",no-claude,")) {
    log(`labelled no-claude: PR #${PR}`);
    return 0;
  }

  // Never review a pull request the bot itself opened, or it spends its time filing
  // complaints about its own work.
  if (author.startsWith("claude-macmini") || author.endsWith("[bot]") || author === "github-actions") {
    log(`bot-authored, skipping: ${author}`);
    return 0;
  }
  if (`,${labels},`.includes(",claude-done,")) {
    log(`opened by claude, skipping: #${PR}`);
    return 0;
  }

  if (author !== ME) {
    if (!isTrue(policy(REPO, "review_others", "true"))) {
      log(`review_others=false, skipping: ${author}`);
      return 0;
    }
  }

  // Key on the head SHA, so a new push gets reviewed again and the same commit does not.
  if (seen(`${REPO}/pr-${PR}/${sha}`)) {
    log(`already reviewed: PR #${PR} (${sha})`);
    return 0;
  }

  // Very large pull requests cannot be read properly, and half a review is worse than
  // none, so leave them alone.
  if (!/^[0-9]+$/.test(changed)) changed = "0";
  if (Number(changed) > 60) {
    log(`too many changed files (${changed}), skipping: PR #${PR}`);
    markSeen(`${REPO}/pr-${PR}/${sha}`);
    return 0;
  }

  if (dry()) {
    log(`DRY-RUN: would review PR #${PR} (${title}, by ${author}, ${changed} files)`);
    markSeen(`${REPO}/pr-${PR}/${sha}`);
    return 0;
  }

  if (!acquireLock("claude", 60)) {
    log(`another claude is running, deferring: review ${REPO} #${PR}`);
    return 0;
  }

  const diffFile = `${STATE_DIR}/logs/pr-${PR}.diff`;
  ensureParent(diffFile);
  await runToFile(["gh", "pr", "diff", PR, "--repo", REPO], diffFile, { stderr: "ignore" });
  if (statSync(diffFile).size === 0) {
    log(`cannot fetch the diff: PR #${PR}`);
    return 1;
  }

  // Put the code under review on disk. pull/N/head works even for fork pull requests.
  // The diff alone is enough to review from, so carry on if this fails.
  if (await prepareRepo(REPO, `origin/${policy(REPO, "base", "main")}`)) {
    if (
      await ok(["git", "fetch", "--quiet", "origin", `pull/${PR}/head:refs/remotes/pr/${PR}`], { stderr: "ignore" }) &&
      await ok(["git", "checkout", "--quiet", "--detach", `refs/remotes/pr/${PR}`], { stderr: "ignore" })
    ) {
      log(`checked PR #${PR} out into the working tree`);
    }
  }

  const out = `${STATE_DIR}/logs/review-${PR}.log`;
  const diff = readFileSync(diffFile, "utf8").replace(/\n+$/, "");
  const prompt = `あなたは ${REPO} のコードレビュアーです。PR #${PR} をレビューしてください。

タイトル: ${title}
作成者: ${author}

本文:
${body || "（本文なし）"}

差分:
\`\`\`diff
${diff}
\`\`\`

作業ディレクトリにはこの PR の内容がチェックアウトされているので、周辺のコードを読んで判断してよい。ただしファイルの読み取りと検索しかできない (ビルドもテストも実行できない)。

見るところ:
- 正しさ。この変更で壊れる入力・状態・境界条件はないか。
- 要件との食い違い。PR の本文や関連 issue が言っていることと、実際の差分がずれていないか。
- 既にあるものの再実装。このリポジトリに同じことをする関数やユーティリティが既にないか。
- 見落としやすい抜け。エラー処理、後始末、並行実行、非互換な変更。

やらないこと:
- 好みの問題 (命名の趣味、フォーマット、コメントの多寡) は指摘しない。
- 「〜かもしれません」で終わる曖昧な指摘は書かない。実際に壊れる筋道を示せないなら黙る。
- 指摘が無いなら無いと言う。数を揃えようとしない。

出力は、最後に次の形式のブロックを1つだけ出すこと。前後に説明を書いてよいが、投稿されるのはこのブロックだけ。

<<<REVIEW_JSON
{
  "summary": "全体の所見を2〜4文。指摘が無い場合もここに理由を書く。",
  "comments": [
    {
      "path": "差分に出てくるファイルパス",
      "line": 差分で追加された行の、新しいファイルでの行番号 (整数),
      "severity": "blocker" または "suggestion",
      "body": "何がどう壊れるかを1〜3文で",
      "suggestion": "その行を置き換えるコード。示せない場合はこのキーごと省略する"
    }
  ]
}
REVIEW_JSON

line は必ず、差分の中で + が付いている行 (追加された行) の新ファイル側の行番号にすること。文脈行や削除行を指すと投稿が拒否される。指摘が無いときは comments を空配列にする。`;

  log(`claude 実行: review ${REPO} PR #${PR}`);
  const rc = await runClaude(prompt, out, "--allowedTools", "Read,Grep,Glob", "--max-turns", "40");
  if (rc === 90) return 1;

  // Pull out the last REVIEW_JSON block.
  const json = extractReview(out);
  let review: unknown;
  let valid = false;
  try {
    review = JSON.parse(json);
    valid = review !== null && review !== false;
  } catch {}
  if (!valid) {
    // A single bad answer is usually a one-off and the next poll retries it, so
    // only a repeat on the same head SHA is worth a notification. Keep each bad
    // output aside: the retry overwrites $out, which used to destroy the evidence.
    // After the third miss on one SHA, stop retrying (#853 notified 50 times).
    const bad = `${out.replace(/\.log$/, "")}.malformed-${compactStamp()}.log`;
    copyFileSync(out, bad);
    const failsFile = `${seenPath(`${REPO}/pr-${PR}/${sha}`)}.malformed`;
    const fails = (Number.parseInt(cat(failsFile) || "0", 10) || 0) + 1;
    writeFileSync(failsFile, `${fails}\n`);
    log(`could not extract REVIEW_JSON (attempt ${fails}): ${bad}`);
    if (fails >= 2) {
      await notify("claude-agent: malformed review output", `${REPO} #${PR}, ${fails} times on the same commit. Log: ${bad}`);
    }
    if (fails >= 3) {
      log(`giving up on this commit: ${REPO} #${PR} (${sha})`);
      markSeen(`${REPO}/pr-${PR}/${sha}`);
    }
    return 1;
  }

  const summary = jq(() => jqRaw(alt(idx(review, "summary"), "")));
  const count = jq(() => String(length(alt(idx(review, "comments"), []))));

  if (count === "0") {
    log(`nothing to report: ${REPO} #${PR}`);
    markSeen(`${REPO}/pr-${PR}/${sha}`);
    return 0;
  }

  // Build the inline comments. A suggestion becomes the fenced block that GitHub
  // renders with a "Commit suggestion" button.
  const payload = jq(() =>
    compact({
      event: "COMMENT",
      body: add("🤖 Claude Code (macmini) によるレビューです。\n\n", summary, "\n\n", MARK),
      comments: iter(idx(review, "comments")).map((c) => ({
        path: idx(c, "path"),
        line: toNumber(idx(c, "line")),
        side: "RIGHT",
        body: add(
          add(idx(c, "severity") === "blocker" ? "**要修正**: " : "", idx(c, "body")),
          suggestionBlock(c),
        ),
      })),
    }),
  );

  if (await ok(["gh", "api", `repos/${REPO}/pulls/${PR}/reviews`, "--input", "-"], { stdin: payload, stdout: "ignore", stderr: "ignore" })) {
    log(`posted the review: ${REPO} #${PR} (${count} comments)`);
  } else {
    // The API rejects a line that is not part of the diff. Rather than lose the
    // review, put the whole thing in the body.
    log(`inline comments were rejected, posting as a single comment: ${REPO} #${PR}`);
    const fallback = jq(() =>
      toStrOrThrow(
        add(
          "🤖 Claude Code (macmini) によるレビューです。\n\n",
          alt(idx(review, "summary"), ""),
          "\n\n",
          iter(idx(review, "comments"))
            .map((c) =>
              toStrOrThrow(
                add("- `", idx(c, "path"), ":", toStr(idx(c, "line")), "` ", idx(c, "body"), suggestionBlock(c)),
              ),
            )
            .join("\n"),
          "\n\n(行コメントとして投稿できなかったため本文にまとめています)\n",
          MARK,
        ),
      ),
    );
    if (
      !(await ok(["gh", "pr", "comment", PR, "--repo", REPO, "--body", fallback], { stdout: "ignore", stderr: "ignore" }))
    ) {
      log(`posting the comment failed as well: ${REPO} #${PR}`);
      return 1;
    }
  }

  markSeen(`${REPO}/pr-${PR}/${sha}`);
  return 0;
}

// join() needs strings
function toStrOrThrow(v: unknown): string {
  if (typeof v === "string") return v;
  if (v === null) return "";
  throw new JqError("cannot join a non-string");
}

if (import.meta.main) process.exit(await main(process.argv.slice(2)));
