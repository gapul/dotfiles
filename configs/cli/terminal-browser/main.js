// Surfingkeys 代替のメインプロセス側。`--main-script` で terminal-browser の Electron
// メインプロセスに `createRequire(file)(file)` として読み込まれるので、素の CommonJS。
// ページ側 (vimkeys.js) が ipcRenderer で投げてくる命令のうち、ページから手が届かない
// ものだけをここで実行する。Surfingkeys の background script にあたる。
//
// terminal-browser のタブ模型は内部クラスが持っていて公開されていない。触れるのは
// Electron の webContents と、自分自身の CLI。タブを増やす/選ぶ系は CLI に投げるのが
// 唯一の公開経路なので、そうしている (同じデーモンに socket 越しで届く)。

const { ipcMain, webContents } = require("electron");
const { execFile } = require("node:child_process");
const path = require("node:path");

// 自分自身の CLI。このファイルは ~/.config に置かれるので __dirname からは辿れない。
// bin ラッパー (pkgs/terminal-browser.nix) が実体パスを環境変数で渡す。無い場合は
// Electron の実行ファイルから遡る:
//   <root>/electron/terminal-browser.app/Contents/MacOS/terminal-browser → <root>/bin/…
const CLI =
  process.env.TERMINAL_BROWSER_CLI ||
  path.join(path.dirname(process.execPath), "..", "..", "..", "..", "bin", "terminal-browser");

const closed = []; // X (restore closed tab) 用の履歴

const cli = (args) =>
  new Promise((resolve) => {
    execFile(CLI, args, { timeout: 10000 }, (err, stdout) => resolve(err ? null : stdout));
  });

// 送り主のタブ。terminal-browser の内部 id は取れないので webContents で扱う。
const senderOf = (event) => webContents.fromId(event.sender.id);

const reply = (event, toast) => {
  try {
    event.sender.send("vimkeys:reply", { toast });
  } catch {
    /* タブが既に閉じていることがある */
  }
};

ipcMain.on("vimkeys", async (event, msg) => {
  if (!msg || typeof msg.cmd !== "string") return;
  const { cmd, arg } = msg;
  const wc = senderOf(event);

  switch (cmd) {
    case "newTab":
      if (arg) await cli(["new-tab", arg]);
      break;

    case "newTabBackground":
      // 背景で開く口は CLI に無いので、開いてから元のタブへ戻す。
      if (arg) {
        await cli(["new-tab", arg]);
        if (wc && !wc.isDestroyed()) wc.focus();
      }
      break;

    case "closeTab":
      if (wc && !wc.isDestroyed()) {
        closed.push(wc.getURL());
        wc.close();
      }
      break;

    case "restoreTab": {
      const url = closed.pop();
      if (url) await cli(["new-tab", url]);
      else reply(event, "no closed tab");
      break;
    }

    case "closeOthers":
    case "closeLeft":
    case "closeRight": {
      // terminal-browser の内部順序は取れないので、webContents の並びで代用する。
      const all = webContents.getAllWebContents().filter((w) => w.getType() === "webview" || w.getType() === "browserView");
      const idx = all.findIndex((w) => wc && w.id === wc.id);
      if (idx < 0) {
        reply(event, "tab order unavailable");
        break;
      }
      const victims =
        cmd === "closeOthers" ? all.filter((_, i) => i !== idx)
        : cmd === "closeLeft" ? all.slice(0, idx)
        : all.slice(idx + 1);
      for (const v of victims) {
        closed.push(v.getURL());
        if (!v.isDestroyed()) v.close();
      }
      reply(event, `closed ${victims.length}`);
      break;
    }

    // タブの選択と並べ替えは terminal-browser 自身のキー割り当てが持っている
    // (パレット / タブストリップ)。外から順序を動かす公開経路が無いので、
    // ここで嘘の実装を置かずに、その旨だけ返す。
    case "nextTab":
    case "prevTab":
    case "moveTabLeft":
    case "moveTabRight":
    case "chooseTab":
      reply(event, `${cmd}: use terminal-browser's own tab keys`);
      break;

    default:
      break;
  }
});
