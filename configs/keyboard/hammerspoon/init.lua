-- Keyboard mouse mode, inspired by the Keyball39 scroll layer.
--
-- Hyper+G: enter/leave
-- H/J/K/L: move pointer
-- Shift+H/J/K/L: move pointer faster
-- Hold S + H/J/K/L: scroll
-- U/I/O: left/middle/right click
-- Hold D: drag
-- 1/2/3/4: move to a screen corner
-- C: move to the focused window center
-- Tab: move to the next display
-- Escape/Return: leave

local hyper = { "cmd", "ctrl", "alt" }
local hyperShift = { "cmd", "ctrl", "alt", "shift" }
local mouseMode = hs.hotkey.modal.new(hyper, "g")
local activeTimers = {}
local scrolling = false
local dragging = false
local modeAlert = nil
local helpChooser = nil

local pointerStep = 4
local fastPointerStep = 14
local scrollStep = 2
local tickSeconds = 0.016

local directions = {
	h = { x = -1, y = 0 },
	j = { x = 0, y = 1 },
	k = { x = 0, y = -1 },
	l = { x = 1, y = 0 },
}

local function stopDirection(key)
	if activeTimers[key] then
		activeTimers[key].timer:stop()
		activeTimers[key] = nil
	end
end

local function stopAllDirections()
	for key, _ in pairs(activeTimers) do
		stopDirection(key)
	end
end

local function acceleration(startedAt)
	local heldFor = hs.timer.secondsSinceEpoch() - startedAt
	return 1 + math.min(math.max((heldFor - 0.35) * 2.5, 0), 2)
end

local function movePointer(position)
	if dragging then
		hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDragged, position):post()
	else
		hs.mouse.absolutePosition(position)
	end
end

local function applyDirection(direction, fast, startedAt)
	local scale = acceleration(startedAt)
	if scrolling then
		hs.eventtap.scrollWheel({ direction.x * -scrollStep * scale, direction.y * -scrollStep * scale }, {}, "pixel")
		return
	end

	local step = (fast and fastPointerStep or pointerStep) * scale
	local position = hs.mouse.absolutePosition()
	movePointer({
		x = position.x + direction.x * step,
		y = position.y + direction.y * step,
	})
end

local function startDirection(key, fast)
	stopDirection(key)
	local direction = directions[key]
	local startedAt = hs.timer.secondsSinceEpoch()
	applyDirection(direction, fast, startedAt)
	activeTimers[key] = {
		timer = hs.timer.doEvery(tickSeconds, function()
			applyDirection(direction, fast, startedAt)
		end),
	}
end

local function bindDirection(key)
	mouseMode:bind({}, key, function()
		startDirection(key, false)
	end, function()
		stopDirection(key)
	end)

	mouseMode:bind({ "shift" }, key, function()
		startDirection(key, true)
	end, function()
		stopDirection(key)
	end)
end

local function click(button)
	local position = hs.mouse.absolutePosition()
	if button == "left" then
		hs.eventtap.leftClick(position)
	elseif button == "middle" then
		hs.eventtap.middleClick(position)
	else
		hs.eventtap.rightClick(position)
	end
end

local function setDragging(enabled)
	if dragging == enabled then
		return
	end

	dragging = enabled
	local eventType = enabled and hs.eventtap.event.types.leftMouseDown or hs.eventtap.event.types.leftMouseUp
	hs.eventtap.event.newMouseEvent(eventType, hs.mouse.absolutePosition()):post()
end

local function currentScreen()
	return hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
end

local function frameCenter(frame)
	return {
		x = frame.x + frame.w / 2,
		y = frame.y + frame.h / 2,
	}
end

local function moveToCorner(corner)
	local frame = currentScreen():frame()
	local padding = 24
	local positions = {
		["1"] = { x = frame.x + padding, y = frame.y + padding },
		["2"] = { x = frame.x + frame.w - padding, y = frame.y + padding },
		["3"] = { x = frame.x + padding, y = frame.y + frame.h - padding },
		["4"] = { x = frame.x + frame.w - padding, y = frame.y + frame.h - padding },
	}
	movePointer(positions[corner])
end

local function moveToFocusedWindow()
	local window = hs.window.focusedWindow()
	if window then
		movePointer(frameCenter(window:frame()))
	end
end

local function moveToNextScreen()
	local screens = hs.screen.allScreens()
	if #screens < 2 then
		return
	end

	local current = currentScreen()
	for index, screen in ipairs(screens) do
		if screen:id() == current:id() then
			local nextScreen = screens[(index % #screens) + 1]
			movePointer(frameCenter(nextScreen:frame()))
			return
		end
	end
end

for key, _ in pairs(directions) do
	bindDirection(key)
end

mouseMode:bind({}, "s", function()
	scrolling = true
end, function()
	scrolling = false
end)

mouseMode:bind({}, "u", function()
	click("left")
end)
mouseMode:bind({}, "i", function()
	click("middle")
end)
mouseMode:bind({}, "o", function()
	click("right")
end)
mouseMode:bind({}, "d", function()
	setDragging(true)
end, function()
	setDragging(false)
end)

for _, key in ipairs({ "1", "2", "3", "4" }) do
	local corner = key
	mouseMode:bind({}, key, function()
		moveToCorner(corner)
	end)
end

mouseMode:bind({}, "c", moveToFocusedWindow)
mouseMode:bind({}, "tab", moveToNextScreen)

local function leaveMouseMode()
	mouseMode:exit()
end

mouseMode:bind({}, "escape", leaveMouseMode)
mouseMode:bind({}, "return", leaveMouseMode)
mouseMode:bind(hyper, "g", leaveMouseMode)

function mouseMode:entered()
	scrolling = false
	modeAlert = hs.alert.show(
		"Mouse: HJKL move · S scroll · D drag · U/I/O click · Esc exit",
		hs.alert.defaultStyle,
		hs.screen.mainScreen(),
		86400
	)
end

function mouseMode:exited()
	scrolling = false
	stopAllDirections()
	setDragging(false)
	if modeAlert then
		hs.alert.closeSpecific(modeAlert)
		modeAlert = nil
	end
end

local function displayKey(binding)
	local key = binding:gsub("^cmd%-ctrl%-alt%-", "")
	key = key:gsub("^shift%-", "⇧")
	local names = {
		backslash = "\\",
		comma = ",",
		enter = "Return",
		equal = "=",
		minus = "-",
		semicolon = ";",
		slash = "/",
		tab = "Tab",
	}
	key = names[key] or key
	return key:upper()
end

local function describeAeroSpaceAction(key, action)
	local special = {
		enter = "Open a new Ghostty window",
		r = "Open Raycast",
		["shift-semicolon"] = "Enter service mode",
		["shift-r"] = "Enter resize mode",
	}
	if special[key] then
		return special[key]
	end

	local descriptions = {
		{ "^focus (.+)", "Focus %s" },
		{ "^move (.+)", "Move window %s" },
		{ "^workspace ([%w]+)", "Switch to workspace %s" },
		{ "^move%-node%-to%-workspace ([%w]+)", "Move window to workspace %s" },
		{ "^focus%-monitor .+ (left)$", "Focus previous monitor" },
		{ "^focus%-monitor .+ (right)$", "Focus next monitor" },
		{ "^move%-workspace%-to%-monitor .+ (prev)$", "Move workspace to previous monitor" },
		{ "^move%-workspace%-to%-monitor .+ (next)$", "Move workspace to next monitor" },
		{ "^resize smart ([%+%-]?%d+)", "Resize by %s" },
	}
	for _, rule in ipairs(descriptions) do
		local value = action:match(rule[1])
		if value then
			return string.format(rule[2], value)
		end
	end

	if action == "close" then
		return "Close window"
	elseif action == "close --quit-if-last-window" then
		return "Close window and quit empty app"
	elseif action == "fullscreen" then
		return "Toggle fullscreen"
	elseif action == "workspace-back-and-forth" then
		return "Switch to previous workspace"
	elseif action == "layout floating tiling" then
		return "Toggle floating layout"
	elseif action:match("^layout") then
		return "Change layout"
	end

	return action
end

local function aerospaceHelpItems()
	local path = os.getenv("HOME") .. "/.config/aerospace/aerospace.toml"
	local file = io.open(path, "r")
	if not file then
		return {}
	end

	local items = {}
	local inMainBindings = false
	for line in file:lines() do
		if line:match("^%[mode%.main%.binding%]") then
			inMainBindings = true
		elseif inMainBindings and line:match("^%[") then
			break
		elseif inMainBindings then
			local binding, rhs = line:match("^%s*([%w%-]+)%s*=%s*(.+)")
			if binding and binding:match("^cmd%-ctrl%-alt%-") then
				local key = binding:gsub("^cmd%-ctrl%-alt%-", "")
				local action = rhs:match("%[%s*'([^']+)'") or rhs:match('%[%s*"([^"]+)"') or "AeroSpace action"
				table.insert(items, {
					text = displayKey(binding),
					subText = describeAeroSpaceAction(key, action),
					source = "AeroSpace",
				})
			end
		end
	end
	file:close()
	return items
end

local function hammerspoonHelpItems()
	local bindings = {
		{ "G", "Enter mouse mode" },
		{ "?", "Open this key binding help" },
		{ "Mouse · H/J/K/L", "Move pointer; hold Shift for faster movement" },
		{ "Mouse · S + H/J/K/L", "Scroll" },
		{ "Mouse · U/I/O", "Left, middle, and right click" },
		{ "Mouse · D", "Hold to drag" },
		{ "Mouse · 1/2/3/4", "Move to a screen corner" },
		{ "Mouse · C", "Move to the focused window center" },
		{ "Mouse · Tab", "Move to the next display" },
		{ "Mouse · Esc/Return", "Exit mouse mode" },
	}
	local items = {}
	for _, binding in ipairs(bindings) do
		table.insert(items, {
			text = binding[1],
			subText = binding[2],
			source = "Hammerspoon",
		})
	end
	return items
end

local function showKeyBindingHelp()
	if helpChooser and helpChooser:isVisible() then
		helpChooser:hide()
		return
	end

	local choices = aerospaceHelpItems()
	for _, item in ipairs(hammerspoonHelpItems()) do
		table.insert(choices, item)
	end
	table.sort(choices, function(a, b)
		if a.source == b.source then
			return a.text < b.text
		end
		return a.source < b.source
	end)

	if not helpChooser then
		helpChooser = hs.chooser.new(function() end)
		helpChooser:placeholderText("Search key bindings")
		helpChooser:rows(18)
		helpChooser:width(34)
	end
	helpChooser:choices(choices)
	helpChooser:show()
end

hs.hotkey.bind(hyperShift, "/", showKeyBindingHelp)

-- AeroSpace 時代の cmd-ctrl-alt-q / -shift-q を移植。OmniWM にはウィンドウを閉じる
-- アクションが無いので Hammerspoon の AX クローズで代替する。
-- Hyper+Q: フォーカスウィンドウを閉じる (AeroSpace の close 相当)。
hs.hotkey.bind(hyper, "q", function()
	local w = hs.window.focusedWindow()
	if w then
		w:close()
	end
end)
-- Hyper+Shift+Q: 閉じて、それがアプリ最後の 1 枚なら終了 (close --quit-if-last-window 相当)。
hs.hotkey.bind(hyperShift, "q", function()
	local w = hs.window.focusedWindow()
	if not w then
		return
	end
	local app = w:application()
	w:close()
	if app and #app:allWindows() == 0 then
		app:kill()
	end
end)

-- Hyper+Return: 新規 Ghostty ウィンドウを開く (AeroSpace の cmd-ctrl-alt-enter 相当)。
-- Ghostty は initial-window=false で背面常駐なので、起動済みなら単なる activate では
-- ウィンドウが出ない。File > New Window を選んで確実に 1 枚開く。
-- 未起動のときは launch 自体がウィンドウを 1 枚開くので、そこで New Window も押すと
-- 二重になる。起動を投げたあと実際に開いたかを見て、開かなかったときだけ押す。
hs.hotkey.bind(hyper, "return", function()
	local bundleID = "com.mitchellh.ghostty"
	local newWindow = function(app)
		app:activate()
		app:selectMenuItem({ "File", "New Window" })
	end

	local app = hs.application.get(bundleID)
	if app then
		newWindow(app)
		return
	end

	hs.application.launchOrFocusByBundleID(bundleID)
	hs.timer.doAfter(1.5, function()
		local launched = hs.application.get(bundleID)
		if launched and #launched:allWindows() == 0 then
			newWindow(launched)
		end
	end)
end)

-- Hyper+Shift+Tab: 今のワークスペースを隣のモニタへ (AeroSpace の cmd-ctrl-alt-shift-tab 相当)。
-- 同じ動作は OmniWM 側で Hyper+M/N にも割り当ててあるが、1 つの id には 1 バインドしか
-- 持てないので Tab のマッスルメモリはこちらで足す。
hs.hotkey.bind(hyperShift, "tab", function()
	hs.task.new("/opt/homebrew/bin/omniwmctl", nil, { "command", "swap-workspace-with-monitor", "right" }):start()
end)

-- AeroSpace が奪っていた macOS ネイティブ操作を殺す (automatically-unhide-macos-hidden-apps=false
-- + cmd-m/cmd-h/cmd-alt-h を mode main に潰していたのと同じ意図)。minimize と hide は
-- ウィンドウを Dock に送ってタイル管理から消すので、押しても何も起きないようにする。
for _, spec in ipairs({
	{ { "cmd" }, "m" }, -- minimize
	{ { "cmd" }, "h" }, -- hide app
	{ { "cmd", "alt" }, "h" }, -- hide others
}) do
	hs.hotkey.bind(spec[1], spec[2], function() end)
end

local reloadTimer = nil
_G.configWatcher = hs.pathwatcher.new(hs.configdir, function(paths)
	for _, path in ipairs(paths) do
		if path:match("%.lua$") then
			if reloadTimer then
				reloadTimer:stop()
			end
			reloadTimer = hs.timer.doAfter(0.4, hs.reload)
			return
		end
	end
end)
_G.configWatcher:start()

-- メニューバーの Hammerspoon アイコンは出さない。制御はホットキーで足りる。
hs.menuIcon(false)

-- 画面ミラーリングをホットキーで開く。SketchyBar に専用アイコンを置かずに済むよう、
-- 公式の「画面ミラーリング」メニューバー項目 (com.apple.menuextra.screen-mirroring) を
-- 直接クリックしてメニューを開く。Hyper+P。
local function openScreenMirroring()
	hs.osascript.applescript([[
tell application "System Events"
  tell process "ControlCenter"
    set targetItem to missing value
    repeat with candidate in menu bar items of menu bar 1
      try
        if (value of attribute "AXIdentifier" of candidate) as text is "com.apple.menuextra.screen-mirroring" then
          set targetItem to candidate
          exit repeat
        end if
      end try
    end repeat
    if targetItem is not missing value then click targetItem
  end tell
end tell
]])
end
hs.hotkey.bind(hyper, "p", openScreenMirroring)

-- Hammerspoon itself owns login startup after its first launch.
hs.autoLaunch(true)
