-- Keyboard mouse mode, inspired by the Keyball39 scroll layer.
--
-- Hyper+G: enter/leave
-- H/J/K/L: move pointer
-- Shift+H/J/K/L: move pointer faster
-- Hold S + H/J/K/L: scroll
-- U/I/O: left/middle/right click
-- Escape/Return: leave

local hyper = { "cmd", "ctrl", "alt" }
local mouseMode = hs.hotkey.modal.new(hyper, "g")
local activeTimers = {}
local scrolling = false
local modeAlert = nil

local pointerStep = 8
local fastPointerStep = 24
local scrollStep = 5
local tickSeconds = 0.016

local directions = {
	h = { x = -1, y = 0 },
	j = { x = 0, y = 1 },
	k = { x = 0, y = -1 },
	l = { x = 1, y = 0 },
}

local function stopDirection(key)
	if activeTimers[key] then
		activeTimers[key]:stop()
		activeTimers[key] = nil
	end
end

local function stopAllDirections()
	for key, _ in pairs(activeTimers) do
		stopDirection(key)
	end
end

local function applyDirection(direction, fast)
	if scrolling then
		-- scrollWheel uses positive Y for up and positive X for left.
		hs.eventtap.scrollWheel({ direction.x * -scrollStep, direction.y * -scrollStep }, {}, "pixel")
		return
	end

	local step = fast and fastPointerStep or pointerStep
	local position = hs.mouse.absolutePosition()
	hs.mouse.absolutePosition({
		x = position.x + direction.x * step,
		y = position.y + direction.y * step,
	})
end

local function startDirection(key, fast)
	stopDirection(key)
	local direction = directions[key]
	applyDirection(direction, fast)
	activeTimers[key] = hs.timer.doEvery(tickSeconds, function()
		applyDirection(direction, fast)
	end)
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

local function leaveMouseMode()
	mouseMode:exit()
end

mouseMode:bind({}, "escape", leaveMouseMode)
mouseMode:bind({}, "return", leaveMouseMode)
mouseMode:bind(hyper, "g", leaveMouseMode)

function mouseMode:entered()
	scrolling = false
	modeAlert = hs.alert.show(
		"Mouse: HJKL move · S+HJKL scroll · U/I/O click · Esc exit",
		hs.alert.defaultStyle,
		hs.screen.mainScreen(),
		86400
	)
end

function mouseMode:exited()
	scrolling = false
	stopAllDirections()
	if modeAlert then
		hs.alert.closeSpecific(modeAlert)
		modeAlert = nil
	end
end

-- Hammerspoon itself owns login startup after its first launch.
hs.autoLaunch(true)
