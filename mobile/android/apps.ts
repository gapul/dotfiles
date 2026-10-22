#!/usr/bin/env bun
// apps.tsv に宣言したアプリと実機を突き合わせる。windows/winget/status.ps1 と同じ役割。
//
//   ./apps.ts status      # 宣言 vs 実機の差分。MISSING があれば exit 1 (既定)
//   ./apps.ts install     # F-Droid / IzzyOnDroid のものを fdroidcl 経由で adb install
//   ./apps.ts verify      # 宣言した packageId が配布元に実在するか (4 経路すべて)
//   ./apps.ts obtainium   # 端末の Obtainium に貼る URL リストを出す
//   ./apps.ts adopt       # 端末に在って宣言に無いものを、経路を判定して tsv 行で出す
//   ./apps.ts aurora      # play 行を Aurora Store の Favourites 用 JSON にする
//
// 母艦から入れられるのは F-Droid 系だけ。GitHub 配布は端末の Obtainium が、
// Play は Aurora Store が担う。ここが持つのは「何を入れるか」の宣言と差分の判定で、
// 入れる仕事は経路ごとの道具に任せている。
//
// 外の道具 (adb / fdroidcl / gh / curl) はコマンドとして呼ぶ。test.sh が偽物を PATH に
// 置いて実機もネットワークも無しに回すので、fetch に置き換えるとそこが素通りになる。
import { mkdirSync, readFileSync, writeSync } from "node:fs";
import { homedir } from "node:os";

process.chdir(import.meta.dir);

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

// 宣言に無いリポジトリを見に行かせないため、fdroidcl の設定は母艦の ~/.config
// ではなくこのスクリプト専用の場所に置く。母艦で fdroidcl を手で使っていても
// 干渉しないし、この repo だけがリポジトリ構成の SSOT になる。
//
// XDG_CONFIG_HOME はプロセス全体には差し替えない。fdroidcl の設定を退けるつもりで
// gh の認証情報 ($XDG_CONFIG_HOME/gh/hosts.yml) まで見失わせ、verify の GitHub 照会が
// 黙って全部 UNKNOWN になる。差し替えるのは fdroidcl を呼ぶ瞬間だけにする。
const fdroidclConfig = `${process.env.XDG_CACHE_HOME || `${process.env.HOME ?? homedir()}/.cache`}/dotfiles-mobile/fdroidcl`;
mkdirSync(fdroidclConfig, { recursive: true });

// F-Droid 公式は fdroidcl の既定で入っている。追加で見るリポジトリだけ宣言する。
const extraRepos: { name: string; url: string }[] = [{ name: "izzy", url: "https://apt.izzysoft.de/fdroid/repo" }];

type Stdio = "inherit" | "ignore" | "pipe" | number;
interface Opts {
  stdin?: "inherit" | "ignore";
  stdout?: Stdio;
  stderr?: Stdio;
  env?: Record<string, string>;
}

// コマンドを走らせて終了コードと stdout を返す。無いコマンドは bash と同じく 127。
function run(cmd: string[], opts: Opts = {}): { code: number; stdout: string } {
  if (!Bun.which(cmd[0])) {
    if (opts.stderr !== "ignore") err(`${cmd[0]}: command not found`);
    return { code: 127, stdout: "" };
  }
  const p = Bun.spawnSync(cmd, {
    stdin: opts.stdin ?? "inherit",
    stdout: opts.stdout ?? "inherit",
    stderr: opts.stderr ?? "inherit",
    env: opts.env ? { ...process.env, ...opts.env } : undefined,
  });
  return { code: p.exitCode ?? 1, stdout: p.stdout?.toString() ?? "" };
}

const fdroidcl = (args: string[], opts: Opts = {}) =>
  run(["fdroidcl", ...args], { ...opts, env: { XDG_CONFIG_HOME: fdroidclConfig } });

// set -e と同じく、失敗したらその終了コードで抜ける
function orExit(r: { code: number; stdout: string }): string {
  if (r.code !== 0) process.exit(r.code);
  return r.stdout;
}

function need(cmd: string, pkg: string): void {
  if (Bun.which(cmd)) return;
  err(`${cmd} が無い: nix shell nixpkgs#${pkg} で入れて再実行 (just android-apps なら自動)`);
  process.exit(1);
}

// $(...) と <<< の組み合わせと同じ行の取り方: 末尾の改行を落としてから行に割る
// (空なら空行が 1 つ)
const lines = (s: string): string[] => s.replace(/\n+$/, "").split("\n");
const byteSort = (xs: string[]): string[] => [...xs].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

// IFS=$'\t' read -r a b c と同じ割り方。タブは空白扱いなので連続は 1 つに潰れ、
// 最後の変数が残り全部を受ける。
function readFields(line: string, n: number): string[] {
  let rest = line.replace(/^\t+/, "").replace(/\t+$/, "");
  const fields: string[] = [];
  for (let i = 0; i < n - 1; i++) {
    const m = /^([^\t]*)\t+/.exec(rest);
    if (!m) {
      fields.push(rest);
      rest = "";
      continue;
    }
    fields.push(m[1]);
    rest = rest.slice(m[0].length);
  }
  fields.push(rest);
  return fields;
}

interface Declared {
  line: string;
  pkg: string;
  source: string;
  ref: string;
}

// packageId / source / ref の 3 列。コメントと空行を落とす。
function declared(): Declared[] {
  return readFileSync("apps.tsv", "utf8")
    .split("\n")
    .filter((l) => !/^\s*(#|$)/.test(l))
    .map((line) => {
      const [pkg, source, ref] = readFields(line, 3);
      return { line, pkg, source, ref };
    });
}

// cut -f1 相当 (こちらはタブを潰さない)
const declaredIds = (): string[] => byteSort(declared().map((d) => d.line.split("\t")[0]));

// fdroidcl で入れられるもの (= F-Droid 系) の packageId
const fdroidIds = (): string[] =>
  declared()
    .map((d) => d.line.split("\t"))
    .filter((f) => f[1] === "fdroid" || f[1] === "izzy")
    .map((f) => f[0].trim());

function ensureRepos(): void {
  for (const { name, url } of extraRepos) {
    // すでに在れば repo add はエラーになる。宣言済みという意味なので黙って流す。
    fdroidcl(["repo", "add", name, url], { stdout: "ignore", stderr: "ignore" });
  }
}

// 端末に入っているサードパーティのアプリ。adb の stdin は閉じる (宣言を読み尽くさせない)。
function installedOnDevice(): string[] {
  need("adb", "android-tools");
  const raw = orExit(run(["adb", "shell", "pm", "list", "packages", "-3", "--user", "0"], { stdin: "ignore", stdout: "pipe" }));
  const body = raw.replaceAll("\r", "");
  const pkgs = body === "" ? [] : body.replace(/\n$/, "").split("\n");
  return lines(byteSort(pkgs.map((l) => l.replace(/^package:/, ""))).join("\n"));
}

function cmdStatus(): number {
  const installed = installedOnDevice();
  const installedSet = new Set(installed);
  let missing = 0;
  let extra = 0;

  out("━━━ 宣言したが端末に無い ━━━");
  for (const { pkg, source } of declared()) {
    if (!installedSet.has(pkg)) {
      out(`  MISSING  ${pkg} (${source})`);
      missing++;
    }
  }
  if (missing === 0) out("  なし");

  out("━━━ 端末に在るが宣言に無い ━━━");
  const ids = new Set(declaredIds());
  for (const raw of installed) {
    const pkg = raw.trim();
    if (!ids.has(pkg)) {
      out(`  EXTRA    ${pkg}`);
      extra++;
    }
  }
  if (extra === 0) out("  なし");

  // EXTRA では落とさない。端末で試しに入れたものが必ず在るし、消すかどうかは
  // 人が決めること。宣言を満たしていないこと (MISSING) だけを失敗として扱う。
  if (missing > 0) {
    err(`宣言 ${missing} 件が未インストール。./apps.ts install で入る分を入れる`);
    return 1;
  }
  return 0;
}

function cmdInstall(): number {
  need("fdroidcl", "fdroidcl");
  const installed = new Set(installedOnDevice());
  ensureRepos();
  orExit(fdroidcl(["update"]));

  const targets = fdroidIds().filter((pkg) => !installed.has(pkg));
  if (targets.length > 0) {
    orExit(fdroidcl(["install", ...targets]));
  } else {
    out("fdroidcl で入れるものは無い");
  }

  // 残りは端末側の道具の仕事。母艦から入れる手段が無いので報告だけする。
  for (const { pkg, source } of declared()) {
    if (installed.has(pkg)) continue;
    if (source === "github") out(`端末の Obtainium で入れる: ${pkg}`);
    else if (source === "play") out(`端末の Aurora Store で入れる: ${pkg}`);
  }
  return 0;
}

const playUrl = (pkg: string): string => `https://play.google.com/store/apps/details?id=${pkg}&gl=us`;

function cmdVerify(): number {
  let unknown = 0;
  let reposUpdated = false;
  for (const { pkg, source, ref } of declared()) {
    let ok = true;
    switch (source) {
      case "fdroid":
      case "izzy":
        need("fdroidcl", "fdroidcl");
        // 索引の取得は 1 回だけ。行ごとに update すると毎回 13MB 引きに行く。
        if (!reposUpdated) {
          ensureRepos();
          orExit(fdroidcl(["update"]));
          reposUpdated = true;
        }
        ok = fdroidcl(["show", pkg], { stdout: "ignore", stderr: "ignore" }).code === 0;
        break;
      case "github": {
        // リリースに APK が付いていなければ Obtainium が追えない。存在だけでなく
        // 「取れる形で配られているか」まで見る。
        //
        // gh があればそちらを使う。未認証の GitHub API は 60 回/時で、宣言が
        // 増えると verify が rate limit で落ちる (認証済みなら 5000 回/時)。
        // curl 側に -L が要るのは、repo が改名されると API が 301 を返すため
        // (実際 Catfriend1/syncthing-android は researchxxl/ に移っていた)。
        const assets = Bun.which("gh")
          ? run(["gh", "api", `repos/${ref}/releases/latest`, "--jq", "[.assets[].name]"], {
              stdout: "pipe",
              stderr: "ignore",
            }).stdout
          : run(["curl", "-fsSL", `https://api.github.com/repos/${ref}/releases/latest`], { stdout: "pipe" }).stdout;
        ok = assets.includes(".apk");
        break;
      }
      case "play":
        ok = run(["curl", "-fsS", "-o", "/dev/null", playUrl(pkg)]).code === 0;
        break;
      default:
        out(`  BAD      ${pkg} — source 列が不正: ${source}`);
        unknown++;
        continue;
    }
    if (!ok) {
      out(`  UNKNOWN  ${pkg} — ${source} に見つからない (packageId か ref が違う)`);
      unknown++;
    }
  }

  if (unknown > 0) {
    err(`${unknown} 件が配布元に解決できない`);
    return 1;
  }
  out("宣言したアプリはすべて配布元に在る");
  return 0;
}

function cmdObtainium(): number {
  // 端末側の自動更新は Obtainium に任せる。URL は packageId / ref から機械的に
  // 決まるので、ここで導出する (URL 一覧を別に持つと二重管理になる)。
  for (const { pkg, source, ref } of declared()) {
    switch (source) {
      case "fdroid":
        out(`https://f-droid.org/packages/${pkg}`);
        break;
      case "izzy":
        out(`https://apt.izzysoft.de/fdroid/index/apk/${pkg}`);
        break;
      case "github":
        out(`https://github.com/${ref}`);
        break;
      case "play":
        err(`Aurora Store の担当なので Obtainium では追えない: ${pkg}`);
        break;
    }
  }
  return 0;
}

// 端末に在って宣言に無いものを apps.tsv の行として出す。Aurora Store で入れたものを
// 手で書き写すのは packageId を目で追う作業になるので、経路の判定ごと機械にやらせる。
//
//   ./apps.ts adopt >>apps.tsv   # 追記してから中身を見て整える
function cmdAdopt(): number {
  const installed = installedOnDevice();
  const ids = new Set(declaredIds());
  const extra = installed.filter((pkg) => !ids.has(pkg));

  if (extra.join("\n") === "") {
    err("# 宣言に無いアプリは端末に無い");
    return 0;
  }

  ensureRepos();
  // 失敗しても続ける (索引が古くても show は引ける)。stdout は tsv 行専用なので stderr へ。
  fdroidcl(["update"], { stdout: 2 });

  for (const raw of extra) {
    const pkg = raw.trim();
    if (pkg === "") continue;
    // F-Droid 系に在ればそちらが一次。無ければ Play を見る。どちらでも引けなければ
    // play にしておく (Aurora Store で入れた覚えのあるもの) が、判定できていない
    // ことは行末に残す。GitHub 配布があるなら github に寄せた方が Obtainium が追える。
    if (fdroidcl(["show", pkg], { stdout: "ignore", stderr: "ignore" }).code === 0) {
      out(`${pkg}\tfdroid\t-`);
    } else if (run(["curl", "-fsS", "-o", "/dev/null", playUrl(pkg)]).code === 0) {
      out(`${pkg}\tplay\t-`);
    } else {
      out(`${pkg}\tplay\t-\t# 配布元を特定できず`);
    }
  }
  return 0;
}

// play 行を Aurora Store の Favourites に import できる JSON にする。
// Aurora 4.6 以降は Favourites の import/export と一括インストールを持っているので、
// Play しか配布元が無いものも「ファイルを渡して端末側で入れる」に寄せられる。
// 形式は AuroraStore の data/room/favourite/{ImportExport,Favourite}.kt に合わせた。
//
//   ./apps.ts aurora >aurora-favourites.json
//   adb push aurora-favourites.json /sdcard/Download/
//   端末で Aurora Store → Favourites → Import → 一括インストール
function cmdAurora(): number {
  // displayName は packageId をそのまま置く。表示用のラベルでしかなく、
  // 正しい名前を取るには Play を 1 件ずつ引く必要があって割に合わない。
  // added は 0 固定 (実行のたびに変えるとファイルが毎回差分になる)。
  const favourites = declared()
    .map((d) => d.line.split("\t"))
    .filter((f) => f[1] === "play")
    .flatMap((f) => f[0].split(/\s+/).filter(Boolean))
    .map((pkg) => ({ packageName: pkg, displayName: pkg, iconURL: "", added: 0, mode: "IMPORT" }));
  out(JSON.stringify({ favourites }, null, 2));
  return 0;
}

const commands: Record<string, () => number> = {
  status: cmdStatus,
  install: cmdInstall,
  verify: cmdVerify,
  obtainium: cmdObtainium,
  adopt: cmdAdopt,
  aurora: cmdAurora,
};

const cmd = Bun.argv[2] || "status";
const handler = Object.hasOwn(commands, cmd) ? commands[cmd] : undefined;
if (!handler) {
  err("usage: ./apps.ts [status|install|verify|obtainium|adopt|aurora]");
  process.exit(2);
}
process.exit(handler());
