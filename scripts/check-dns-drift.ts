#!/usr/bin/env bun
// Cloudflare の DNS を repo の宣言と突き合わせる。2 つの面を見る:
//
//   tailnet 内向け  Caddy の vhost         -> A レコード (tailnet の homeserver を指す)
//   公開向け        cloudflared の ingress -> CNAME (トンネルを指す)
//   メール          Email Routing が要求する MX / SPF / DKIM
//
//   scripts/check-dns-drift.ts          # 差分を出す。足りなければ exit 1
//   scripts/check-dns-drift.ts --apply  # 足りないものを作り、宛先違いを直す
//   scripts/check-dns-drift.ts --json   # 機械向け
//
// hosts/homeserver.nix の sites 表は reverse proxy と死活監視の SSOT になっているのに、
// DNS だけ手作業で取り残されていた。サービスを足すたびに「A レコードを追加」を
// 手順書に書き足す運用で、1 件取りこぼすと「そのサービスだけ繋がらない」を後日踏む。
// vhost が在るなら A レコードも在るべき、という当たり前を機械に見せる。
//
// tailnet 側の宛先は homeserver。proxied=false で CF を通さない (tailnet の中でしか
// 届かないアドレスなので、通しても意味が無い)。
//
// 公開側を見るのは「homeserver は生きているのにトンネルだけ旧 IP を向いている」で
// Matrix の federation を一日落とした前科があるため (homelab/cloudflared.nix)。
// ingress は nix に宣言してあるので、CNAME がそれと食い違えば機械に言わせられる。
//
// 元は bash + jq + curl だった。出力・終了コードはそのまま、API は fetch で叩く。
// 並び順は bytewise (LC_ALL=C の sort と同じ)。
import { writeSync } from "node:fs";

const zoneName = "gapul.net";
const api = "https://api.cloudflare.com/client/v4";

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

function die(message: string, code = 1): never {
  err(message);
  process.exit(code);
}

interface RunResult {
  code: number;
  stdout: string;
}

// 子プロセスの stdout だけ受け取る。stderr は既定で端末にそのまま流す (nix の警告など)。
function run(cmd: string[], opts: { quietStderr?: boolean; cwd?: string } = {}): RunResult {
  if (!Bun.which(cmd[0])) return { code: 127, stdout: "" };
  const p = Bun.spawnSync(cmd, {
    cwd: opts.cwd,
    stdin: "ignore",
    stdout: "pipe",
    stderr: opts.quietStderr ? "ignore" : "inherit",
  });
  return { code: p.exitCode ?? 1, stdout: p.stdout.toString() };
}

// $(...) と同じく末尾の改行を落とす
const chomp = (s: string): string => s.replace(/\n+$/, "");
const byteSort = (xs: string[]): string[] => [...xs].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

// jq の文字列補間 "\(x)" と同じ表記にする
function interp(v: unknown): string {
  if (typeof v === "string") return v;
  return JSON.stringify(v ?? null);
}

// ── 引数 ────────────────────────────────────────────────────────────
let apply = false;
let json = false;
for (const arg of Bun.argv.slice(2)) {
  switch (arg) {
    case "--apply":
      apply = true;
      break;
    case "--json":
      json = true;
      break;
    default:
      die("usage: check-dns-drift.ts [--apply] [--json]", 2);
  }
}

const gitTop = Bun.spawnSync(["git", "-C", import.meta.dir, "rev-parse", "--show-toplevel"], {
  stdin: "ignore",
  stdout: "pipe",
  stderr: "inherit",
});
if (gitTop.exitCode !== 0) process.exit(gitTop.exitCode ?? 1);
const repo = chomp(gitTop.stdout.toString());
const flake = `${repo}/nix`;

if (!Bun.which("nix")) die("nix が無い");

// ── 宛先 ────────────────────────────────────────────────────────────
// 宛先は tailnet 上の homeserver。Tailscale が割り当てるので nix には書けない。
interface TailscaleStatus {
  Peer?: Record<string, { DNSName?: string; TailscaleIPs?: string[] }>;
}
function homeserverAddress(): string {
  const r = run(["tailscale", "status", "--json"], { quietStderr: true });
  try {
    const status = JSON.parse(r.stdout) as TailscaleStatus;
    for (const peer of Object.values(status.Peer ?? {})) {
      if (peer.DNSName?.startsWith("homeserver.")) return interp(peer.TailscaleIPs?.[0]);
    }
  } catch {
    // tailscale が居ない / 落ちている。下で「見えない」として扱う。
  }
  return "";
}
const target = homeserverAddress();
if (target === "") die("tailnet に homeserver が見えない (Tailscale に繋がっているか確認)");

// nix eval --json の結果 (文字列の配列) を受ける。失敗したら空 (元の mapfile < <(...) と同じ)。
function nixEvalList(attr: string, applyExpr: string): string[] {
  const r = run(["nix", "eval", "--json", `${flake}#${attr}`, "--apply", applyExpr]);
  if (r.code !== 0) return [];
  try {
    return (JSON.parse(r.stdout) as unknown[]).map(interp);
  } catch {
    return [];
  }
}

// 期待するレコード = Caddy が実際に建てる vhost。sites 表を直接読まずに
// 生成後の virtualHosts を見るのは、表の書き方が変わっても追従させるため。
const vhosts = byteSort(
  nixEvalList("nixosConfigurations.homeserver.config.services.caddy.virtualHosts", "builtins.attrNames"),
);

// 公開向けのホストはトンネルの CNAME で出る。A レコードが無いのが正しい状態なので、
// A の表からは外す。整合は下の「公開ホスト名 (トンネル)」で別に見ている。
// これを外していなかった間、この検査は毎回 4 件の MISSING を出しっぱなしで、
// 本物の欠落 (auth.gapul.net が 2026-09-11 まで A レコードごと無かった) が
// その中に埋もれていた。赤が常態だと誰も読まない。
const tunnelsAttr = "nixosConfigurations.homeserver.config.services.cloudflared.tunnels";
const published = new Set(
  nixEvalList(
    tunnelsAttr,
    "ts: builtins.concatLists (map (id: builtins.attrNames ts.${id}.ingress) (builtins.attrNames ts))",
  ),
);

// ":8102" のように port だけの vhost は名前を持たない。DNS の話ではない。
const expected = vhosts.filter((host) => host.includes(".") && !published.has(host));

// ── 秘密 ────────────────────────────────────────────────────────────
// 秘密は secrets/{common,darwin,homelab}.yaml に割れている。単一の secrets.yaml は
// もう無いので、そこを見ていた頃のこのスクリプトは token を空のまま先に進んでいた。
// `nix shell`, not `nix develop`: the devShell's shellHook prints to stdout (the pre-commit
// install), and that text ended up in front of the token in the Authorization header.
function sopsGet(key: string): string {
  const r = run(
    ["nix", "shell", "nixpkgs#sops", "-c", "sops", "-d", "--extract", `["cloudflare"]["${key}"]`, `${repo}/secrets/homelab.yaml`],
    { quietStderr: true },
  );
  return chomp(r.stdout);
}
const token = sopsGet("api_token");
if (token === "") die("sops から cloudflare.api_token を取れない (age 鍵がある環境で実行する)");
const accountId = sopsGet("account_id");

// ── Cloudflare API ──────────────────────────────────────────────────
// curl -fsS と同じく、HTTP エラーなら curl 風の 1 行を stderr に出して失敗させる。
class ApiError extends Error {
  constructor(
    message: string,
    readonly code: number,
  ) {
    super(message);
  }
}

interface CfResponse<T> {
  result: T;
}

async function cf<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<CfResponse<T>> {
  let res: Response;
  try {
    // トークンは引数に出さない。ps から見える。
    res = await fetch(`${api}${path}`, {
      method: init.method ?? "GET",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  } catch (e) {
    throw new ApiError(`curl: (7) ${(e as Error).message}`, 7);
  }
  if (res.status >= 400) {
    throw new ApiError(`curl: (22) The requested URL returned error: ${res.status}`, 22);
  }
  return (await res.json()) as CfResponse<T>;
}

// set -e で落ちていた箇所と同じく、API の失敗はそこで終了させる
async function cfOrExit<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<CfResponse<T>> {
  try {
    return await cf<T>(path, init);
  } catch (e) {
    if (e instanceof ApiError) die(e.message, e.code);
    throw e;
  }
}

interface DnsRecord {
  id: string;
  name: string;
  content: string;
  priority?: number;
}

const zones = await cfOrExit<{ id?: string }[]>(`/zones?name=${zoneName}`);
const zoneId = interp(zones.result?.[0]?.id);
if (zoneId === "" || zoneId === "null") die(`zone ${zoneName} が引けない (トークンに Zone:Read が要る)`);

// ── tailnet 面: vhost と A レコード ─────────────────────────────────
// 1 回だけ引いてループで使い回す。
const aRecords = (await cfOrExit<DnsRecord[]>(`/zones/${zoneId}/dns_records?type=A&per_page=500`)).result;
const firstByName = (records: DnsRecord[], name: string): DnsRecord | undefined =>
  records.find((r) => interp(r.name) === name);

const missing: string[] = [];
const wrong: { host: string; content: string }[] = [];
const ok: string[] = [];
for (const host of expected) {
  const rec = firstByName(aRecords, host);
  if (!rec) {
    missing.push(host);
  } else if (interp(rec.content) !== target) {
    wrong.push({ host, content: interp(rec.content) });
  } else {
    ok.push(host);
  }
}

// vhost に無い A レコードは報告だけ。apex や CF Pages 向けなど、Caddy を
// 通らない正当なレコードが同じ zone に同居している。
const expectedSet = new Set(expected);
const extra = aRecords.map((r) => interp(r.name)).filter((name) => name !== "" && !expectedSet.has(name));

if (json) {
  out(JSON.stringify({ target, missing, wrong: wrong.map((w) => w.host), extra }, null, 2));
  process.exit(0);
}

out(`宛先: ${target} (tailnet の homeserver)`);
out("━━━ vhost が在るのに A レコードが無い ━━━");
if (missing.length === 0) {
  out("  なし");
} else {
  for (const h of missing) {
    out(`  MISSING  ${h}`);
    if (apply) {
      await cfOrExit(`/zones/${zoneId}/dns_records`, {
        method: "POST",
        body: { type: "A", name: h, content: target, ttl: 60, proxied: false },
      });
      out("    作成した");
    }
  }
}

out("━━━ 宛先が違う ━━━");
if (wrong.length === 0) {
  out("  なし");
} else {
  for (const { host, content } of wrong) {
    out(`  WRONG    ${host}: ${content} -> ${target}`);
    if (apply) {
      const id = interp(firstByName(aRecords, host)?.id);
      await cfOrExit(`/zones/${zoneId}/dns_records/${id}`, { method: "PATCH", body: { content: target } });
      out("    直した");
    }
  }
}

out("━━━ vhost に無い A レコード (参考) ━━━");
if (extra.length === 0) {
  out("  なし");
} else {
  for (const name of extra) out(`  ${name}`);
}

out(`一致: ${ok.length} 件 / 宣言 ${expected.length} 件`);

// ── 公開面: cloudflared の ingress と CNAME ──────────────────────────
out("");
out("━━━ 公開ホスト名 (トンネル) ━━━");
const cnames = (await cfOrExit<DnsRecord[]>(`/zones/${zoneId}/dns_records?type=CNAME&per_page=500`)).result;

// 宣言側: ingress のホスト名 -> トンネル ID ("host\tid" の形で並べる)
const ingress = byteSort(
  nixEvalList(
    tunnelsAttr,
    'ts: builtins.concatLists (map (id: map (h: "${h}\\t${id}") (builtins.attrNames ts.${id}.ingress)) (builtins.attrNames ts))',
  ),
);

let cnameBad = 0;
const declaredHosts = new Set<string>();
for (const entry of ingress) {
  const [host, tunnel = ""] = entry.split("\t");
  declaredHosts.add(host);
  const want = `${tunnel}.cfargotunnel.com`;
  const rec = firstByName(cnames, host);
  const have = rec ? interp(rec.content) : "";
  if (have === "") {
    out(`  MISSING  ${host} -> ${want}`);
    cnameBad++;
    if (apply) {
      await cfOrExit(`/zones/${zoneId}/dns_records`, {
        method: "POST",
        body: { type: "CNAME", name: host, content: want, ttl: 1, proxied: true },
      });
      out("    作成した");
    }
  } else if (have !== want) {
    out(`  WRONG    ${host}: ${have} -> ${want}`);
    cnameBad++;
    if (apply) {
      await cfOrExit(`/zones/${zoneId}/dns_records/${interp(rec?.id)}`, { method: "PATCH", body: { content: want } });
      out("    直した");
    }
  } else {
    out(`  ok       ${host}`);
  }
}

// この repo が宣言していないトンネルを向く CNAME。別プロジェクトが正当に
// 使っていることがあるので落とさず、素性だけ出す。
for (const rec of cnames) {
  const name = interp(rec.name);
  const content = interp(rec.content);
  if (!content.endsWith(".cfargotunnel.com") || declaredHosts.has(name)) continue;
  out(
    `  別ホスト ${name} -> ${content.split(".")[0]} (homeserver の ingress に無い。macmini 側なら hosts/macmini*.nix)`,
  );
}

// ── メール: Email Routing が要求するレコード ────────────────────────
// 宣言側は Cloudflare 自身が持っている。/email/routing/dns が「この zone で
// メールを受けるのに必要なレコード」を返すので、それを期待値として使う。
// ここが欠けるとメールが静かに止まる (配送されないだけで何も言われない)。
out("");
out("━━━ メール (Email Routing) ━━━");
const routing = (await cfOrExit<{ enabled?: boolean; status?: string }>(`/zones/${zoneId}/email/routing`)).result;
out(`  Email Routing: ${interp(routing?.enabled)}/${interp(routing?.status)}`);

// 比較の前に均す。3 つずれる要素がある:
//   - 要求側は FQDN の末尾にドットが付き、実レコード側には無い
//   - TXT は囲みの引用符の有無が食い違う
//   - TXT は 1 文字列 255 バイト上限で分割されるので、実レコード側は
//     "前半" "後半" の形になる。DKIM がこれで、連結分の 3 文字だけずれて
//     「存在するのに MISSING」に見えていた
const norm = (s: string): string =>
  s
    .split("\n")
    .map((l) => l.replace(/\.$/, "").replaceAll('" "', "").replace(/^"/, "").replace(/"$/, ""))
    .join("\n");

interface RequiredRecord {
  type: string;
  name: string;
  priority?: number | null;
  content: string;
}

// 一覧が引けなければ何も比べない (元の done < <(...) と同じく失敗は流す)
let required: RequiredRecord[] = [];
try {
  required = (await cf<RequiredRecord[]>(`/zones/${zoneId}/email/routing/dns`)).result ?? [];
} catch (e) {
  if (!(e instanceof ApiError)) throw e;
  err(e.message);
}

let mailBad = 0;
for (const r of required) {
  const rtype = interp(r.type);
  const rname = interp(r.name);
  const rpri = r.priority === undefined || r.priority === null ? "null" : interp(r.priority);
  if (rtype === "") continue;
  const want = norm(interp(r.content));
  let haveContents: string[] = [];
  try {
    haveContents = (await cf<DnsRecord[]>(`/zones/${zoneId}/dns_records?type=${rtype}&name=${rname}`)).result
      .filter((rec) => rpri === "null" || interp(rec.priority) === rpri)
      .flatMap((rec) => norm(interp(rec.content)).split("\n"));
  } catch (e) {
    if (!(e instanceof ApiError)) throw e;
    err(e.message);
  }
  const label = `${rtype} ${rname}${rpri ? ` (pri=${rpri})` : ""}`;
  // SPF is one record per name, and it may authorise more senders than Cloudflare's suggestion
  // (the live one adds a:www3120.sakura.ne.jp for sakura-mail). Any SPF that includes every
  // mechanism Cloudflare asks for is enough. Creating Cloudflare's version beside it would leave
  // two SPF records, which receivers treat as a permerror.
  const spfTerms = (s: string): string[] => s.split(/\s+/).filter((t) => t !== "" && !/^[~?+-]?all$/.test(t));
  const wantSpf = rtype === "TXT" && want.startsWith("v=spf1 ");
  const spfOk =
    wantSpf &&
    haveContents.some((h) => h.startsWith("v=spf1 ") && spfTerms(want).every((t) => spfTerms(h).includes(t)));
  if (haveContents.includes(want) || spfOk) {
    out(`  ok       ${label}`);
  } else if (wantSpf && haveContents.some((h) => h.startsWith("v=spf1 "))) {
    // An SPF exists but lacks Cloudflare's include: --apply must not add a second one.
    out(`  WRONG    ${label} -> SPF に ${spfTerms(want).join(" ")} を足す (手で直す。--apply は二重 SPF を作るので触らない)`);
    mailBad++;
  } else {
    out(`  MISSING  ${label} -> ${Array.from(want).slice(0, 50).join("")}`);
    mailBad++;
    if (apply) {
      await cfOrExit(`/zones/${zoneId}/dns_records`, {
        method: "POST",
        body: { type: rtype, name: rname, content: want, ttl: 1, ...(rpri === "null" ? {} : { priority: Number(rpri) }) },
      });
      out("    作成した");
    }
  }
}

// ── アカウントのトンネル一覧 ────────────────────────────────────────
interface Tunnel {
  id: string;
  name: string;
  status: string;
  connections?: unknown[] | null;
}
if (accountId !== "") {
  out("");
  out("━━━ トンネル ━━━");
  const tunnels = (await cfOrExit<Tunnel[]>(`/accounts/${accountId}/cfd_tunnel?is_deleted=false`)).result;
  for (const t of tunnels) {
    const id = interp(t.id);
    const name = interp(t.name);
    let mark = "  ";
    if (!ingress.some((entry) => entry.includes(id))) {
      // 上の ingress は homeserver の services.cloudflared.tunnels だけを見ている。
      // macmini のトンネル (manabi と、presenta を載せている macmini) は launchd から
      // token 渡しで起動する形 (経路は Cloudflare
      // 側に持つ) なので、宣言は repo にあってもこの表には出てこない。名前で拾う。
      mark = name === "manabi" || name === "macmini" ? "* " : "? ";
    }
    out(`  ${mark}${name} (${id.slice(0, 8)}) status=${interp(t.status)} conns=${t.connections?.length ?? 0}`);
  }
  out("  * = macmini 側で宣言しているトンネル (hosts/macmini.nix, hosts/macmini-presenta.nix)");
  out("  ? = この repo に宣言が無いトンネル。使っていないなら消す");
}

// EXTRA では落とさない。apex や Pages 向けのレコードが正当に同居している。
if (!apply && (missing.length > 0 || wrong.length > 0 || cnameBad > 0 || mailBad > 0)) {
  die("DNS が宣言に追いついていない。--apply で寄せる");
}
