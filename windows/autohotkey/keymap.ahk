; Windows 組合せキー remap (AutoHotkey v2)
; 物理キー単体の remap は windows/sharpkeys/ で完結。
; AHK は Emacs ショートカット等の「組合せ remap (SharpKeys 不可)」に専念する。
;
; 配置: bootstrap.ps1 が Startup フォルダに symlink → ログイン時自動起動
; リロード: `just win-keymap` (sharpkeys 反映と AHK reload を両方実行)
;
; 関連: configs/wm/karabiner/ (macOS 側)
#Requires AutoHotkey v2.0
#SingleInstance Force

; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
; Copilot キー → 右 Ctrl (scancode 単独で remap 不可な場合の保険)
; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
; SharpKeys (scancode map) で remap できれば不要だが、Win11 24H2 OEM は
; 「Win + Shift + F23」を送るケースがあり scancode 単独 remap 不可。
; 実機の挙動を AHK Key History で確認した結果を反映する。
;
; 候補 (実機検証で当たるものを 1 つだけ有効化):
F23::RControl
; +#F23::RControl       ; Win11 OEM 標準 (LShift + LWin + F23)
; vk89::RControl        ; HP の一部機種
; sc15D::RControl       ; Lenovo 等

; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
; Emacs ショートカット復活 (macOS の Cocoa text field 標準と同じ)
; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
; macOS では全テキストフィールドで Ctrl+A/E/B/F/P/N/K/H/D が効く。
; Windows ではデフォルトで効かないので AHK で emulate する。
;
; ターミナル / エディタ系は除外 — それぞれの shortcut (Ctrl+A=全選択等) を尊重。
; 一般 Win32 GUI / Office / ブラウザ / メモ帳等で有効。

EmacsExcludeClasses := [
    "ConsoleWindowClass",            ; cmd.exe / 旧 PowerShell host
    "CASCADIA_HOSTING_WINDOW_CLASS", ; Windows Terminal (ConPTY host)
    "PseudoConsoleWindow",           ; ConPTY pseudo-console
    "org.wezfurlong.wezterm",        ; WezTerm
    "mintty",                        ; Git Bash / Cygwin
    "Vim",                           ; gVim
    "TMobyMain"                      ; Tera Term
]

; プロセス名 (regex) — Electron / Tauri 系 (Chrome_WidgetWin_1) は class で判別不可なので process で
EmacsExcludeProcesses := "i)^(WezTerm|wt|alacritty|kitty|Code|Cursor|nvim|gvim|Hyper)\.exe$"

IsEmacsExcluded() {
    try {
        cls := WinGetClass("A")
        for excluded in EmacsExcludeClasses
            if (cls = excluded)
                return true
        proc := WinGetProcessName("A")
        return RegExMatch(proc, EmacsExcludeProcesses) > 0
    } catch {
        return false
    }
}

#HotIf !IsEmacsExcluded()
^a::Send "{Home}"           ; 行頭へ
^e::Send "{End}"            ; 行末へ
^b::Send "{Left}"           ; 1 文字左
^f::Send "{Right}"          ; 1 文字右
^p::Send "{Up}"             ; 1 行上
^n::Send "{Down}"           ; 1 行下
^h::Send "{BackSpace}"      ; 1 文字削除 (前)
^d::Send "{Delete}"         ; 1 文字削除 (後)
^k::Send "+{End}{Delete}"   ; 行末まで kill
#HotIf

; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
; Karabiner Mac 設定 → Windows 移植
; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
; Space dual-role: 単押し=Space / 長押し=Hyper (LWin+LCtrl+LAlt)
; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
; Karabiner の rule "スペースキーを単押しでスペース、長押しで Cmd+Ctrl+Opt"
; を Windows で再現。GlazeWM の Hyper bindings (Win+Ctrl+Alt+H 等) を
; 親指の Space 長押しだけで担う = 3 キー同時押しの腱鞘炎回避。
;
; 動作:
;   - Space を tap (200ms 未満で release) → " " を送る
;   - Space を hold (200ms 以上) → LWin+LCtrl+LAlt として動作、release で解除
;   - Space hold 中に他キーを押す → 即 Hyper 確定 (短押し検知から除外)
;   - Alt 押下中の Space は素通り (Alt+Space = Flow Launcher 等の OS hotkey 用)
;     $ prefix で Send が hook を re-trigger しないように防御。
$*Space::{
    ; Alt+Space は Flow Launcher (ランチャ) を呼ぶため素通り。
    ; {Blind} で Alt 修飾を維持したまま Space を送り Alt+Space を成立させる。
    if GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P") {
        Send "{Blind}{Space}"
        return
    }
    static held := false
    held := false
    if !KeyWait("Space", "T0.2") {
        ; 200ms 経過しても Space hold 中 = Hyper モードに入る
        held := true
        Send "{Blind}{LWin Down}{LCtrl Down}{LAlt Down}"
        KeyWait("Space")
        Send "{Blind}{LWin Up}{LCtrl Up}{LAlt Up}"
    } else {
        ; 短押し: 通常の Space
        Send "{Space}"
    }
}

; Hyper + O → Obsidian 起動 (Mac: cmd-ctrl-alt-O で Obsidian Add Log)
; Add Log の URL は vault 名に依存するため、ここでは Obsidian を起動するだけ。
; vault が複数あれば Obsidian は最後に開いた vault を立ち上げる。
#^!o::Run "obsidian://"

; Hyper + Enter → WezTerm 起動 (GlazeWM 経由でも動くが AHK 経由が確実)
; GlazeWM の bindings と被るが先勝ち。GlazeWM 未起動でも開ける保険。
#^!Enter::Run "wezterm-gui.exe"
