if (love.system.getOS() == 'OS X') and (jit.arch == 'arm64' or jit.arch == 'arm') then
    jit.off()
end
require "engine/object"
require "bit"
require "engine/string_packer"
require "engine/controller"
require "back"
require "tag"
require "engine/event"
require "engine/node"
require "engine/moveable"
require "engine/sprite"
require "engine/animatedsprite"
require "functions/misc_functions"
require "game"
require "globals"
require "engine/ui"
require "functions/UI_definitions"
require "functions/state_events"
require "functions/common_events"
require "functions/button_callbacks"
require "functions/misc_functions"
require "functions/test_functions"
require "card"
require "cardarea"
require "blind"
require "card_character"
require "engine/particles"
require "engine/text"
require "challenges"

math.randomseed(G.SEED)

function love.run()
    if love.load then
        love.load(love.arg.parseGameArguments(arg), arg)
    end

    -- We don't want the first frame's dt to include time taken by love.load.
    if love.timer then
        love.timer.step()
    end

    local dt = 0
    local dt_smooth = 1 / 100
    local run_time = 0

    print("Entering main loop")
    -- Main loop time.
    return function()
        run_time = love.timer.getTime()
        -- Process events.
        if love.event and G and G.CONTROLLER then
            love.event.pump()
            local _n, _a, _b, _c, _d, _e, _f, touched
            for name, a, b, c, d, e, f in love.event.poll() do
                if name == "quit" then
                    if not love.quit or not love.quit() then
                        return a or 0
                    end
                end
                if name == 'touchpressed' then
                    touched = true
                elseif name == 'mousepressed' then
                    _n, _a, _b, _c, _d, _e, _f = name, a, b, c, d, e, f
                else
                    love.handlers[name](a, b, c, d, e, f)
                end
            end
            if _n then
                love.handlers['mousepressed'](_a, _b, _c, touched)
            end
        end

        -- Update dt, as we'll be passing it to update
        if love.timer then
            dt = love.timer.step()
        end
        dt_smooth = math.min(0.8 * dt_smooth + 0.2 * dt, 0.1)
        -- Call update and draw
        if love.update then
            love.update(dt_smooth)
        end -- will pass 0 if love.timer is disabled

        if love.graphics and love.graphics.isActive() then
            if love.draw then
                love.draw()
            end
            love.graphics.present()
        end

        run_time = math.min(love.timer.getTime() - run_time, 0.1)
        G.FPS_CAP = G.FPS_CAP or 500
        if run_time < 1. / G.FPS_CAP then
            love.timer.sleep(1. / G.FPS_CAP - run_time)
        end
    end
end

function love.load()
    G:start_up()
    -- Steam integration
    --[[
	local os = love.system.getOS()
	if os == 'OS X' or os == 'Windows' then 
		local st = nil
		--To control when steam communication happens, make sure to send updates to steam as little as possible
		if os == 'OS X' then
			local dir = love.filesystem.getSourceBaseDirectory()
			local old_cpath = package.cpath
			package.cpath = package.cpath .. ';' .. dir .. '/?.so'
			st = require 'luasteam'
			package.cpath = old_cpath
		else
			st = require 'luasteam'
		end

		st.send_control = {
			last_sent_time = -200,
			last_sent_stage = -1,
			force = false,
		}
		if not (st.init and st:init()) then
			love.event.quit()
		end
		--Set up the render window and the stage for the splash screen, then enter the gameloop with :update
		G.STEAM = st
	else
	end
    ]]
    G.STEAM = {
        init = function()
            print("STEAM: init mocked")
            return true
        end,
        shutdown = function()
            print("STEAM: shutdown mocked")
        end,
        runCallbacks = function()
        end,
        getUserName = function()
            return "Player"
        end,
        send_control = {
            last_sent_time = -200,
            last_sent_stage = -1,
            force = false
        }
    }

    -- Set the mouse to invisible immediately, this visibility is handled in the G.CONTROLLER
    love.mouse.setVisible(false)
    print("love.load completed")
end

function love.quit()
    -- Steam integration
    if G.SOUND_MANAGER then
        G.SOUND_MANAGER.channel:push({
            type = 'stop'
        })
    end
    if G.STEAM then
        G.STEAM:shutdown()
    end
end

function love.update(dt)
    -- Perf monitoring checkpoint
    timer_checkpoint(nil, 'update', true)
    G:update(dt)
end

function love.draw()
    -- Perf monitoring checkpoint
    timer_checkpoint(nil, 'draw', true)
    G:draw()
end

function love.keypressed(key)
    if not _RELEASE_MODE and G.keybind_mapping[key] then
        love.gamepadpressed(G.CONTROLLER.keyboard_controller, G.keybind_mapping[key])
    else
        G.CONTROLLER:set_HID_flags('mouse')
        G.CONTROLLER:key_press(key)
    end
end

function love.keyreleased(key)
    if not _RELEASE_MODE and G.keybind_mapping[key] then
        love.gamepadreleased(G.CONTROLLER.keyboard_controller, G.keybind_mapping[key])
    else
        G.CONTROLLER:set_HID_flags('mouse')
        G.CONTROLLER:key_release(key)
    end
end

function love.gamepadpressed(joystick, button)
    button = G.button_mapping[button] or button
    G.CONTROLLER:set_gamepad(joystick)
    G.CONTROLLER:set_HID_flags('button', button)
    G.CONTROLLER:button_press(button)
end

function love.gamepadreleased(joystick, button)
    button = G.button_mapping[button] or button
    G.CONTROLLER:set_gamepad(joystick)
    G.CONTROLLER:set_HID_flags('button', button)
    G.CONTROLLER:button_release(button)
end

function love.mousepressed(x, y, button, touch)
    G.CONTROLLER:set_HID_flags(touch and 'touch' or 'mouse')
    if button == 1 then
        G.CONTROLLER:queue_L_cursor_press(x, y)
    end
    if button == 2 then
        G.CONTROLLER:queue_R_cursor_press(x, y)
    end
end

function love.mousereleased(x, y, button)
    if button == 1 then
        G.CONTROLLER:L_cursor_release(x, y)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    G.CONTROLLER.last_touch_time = G.CONTROLLER.last_touch_time or -1
    if next(love.touch.getTouches()) ~= nil then
        G.CONTROLLER.last_touch_time = G.TIMERS.UPTIME
    end
    G.CONTROLLER:set_HID_flags(G.CONTROLLER.last_touch_time > G.TIMERS.UPTIME - 0.2 and 'touch' or 'mouse')
end

function love.joystickaxis(joystick, axis, value)
    if math.abs(value) > 0.2 and joystick:isGamepad() then
        G.CONTROLLER:set_gamepad(joystick)
        G.CONTROLLER:set_HID_flags('axis')
    end
end

function love.errhand(msg)
    if G.F_NO_ERROR_HAND then
        return
    end
    msg = tostring(msg)

    if G.SETTINGS.crashreports and _RELEASE_MODE and G.F_CRASH_REPORTS then
        --[=[
		local http_thread = love.thread.newThread([[
			local https = require('https')
			CHANNEL = love.thread.getChannel("http_channel")

			while true do
				--Monitor the channel for any new requests
				local request = CHANNEL:demand()
				if request then
					https.request(request)
				end
			end
		]])
		local http_channel = love.thread.getChannel('http_channel')
		http_thread:start()
		local httpencode = function(str)
			local char_to_hex = function(c)
				return string.format("%%%02X", string.byte(c))
			end
			str = str:gsub("\n", "\r\n"):gsub("([^%w _%%%-%.~])", char_to_hex):gsub(" ", "+")
			return str
		end
		

		local error = msg
		local file = string.sub(msg, 0,  string.find(msg, ':'))
		local function_line = string.sub(msg, string.len(file)+1)
		function_line = string.sub(function_line, 0, string.find(function_line, ':')-1)
		file = string.sub(file, 0, string.len(file)-1)
		local trace = debug.traceback()
		local boot_found, func_found = false, false
		for l in string.gmatch(trace, "(.-)\n") do
			if string.match(l, "boot.lua") then
				boot_found = true
			elseif boot_found and not func_found then
				func_found = true
				trace = ''
				function_line = string.sub(l, string.find(l, 'in function')+12)..' line:'..function_line
			end

			if boot_found and func_found then 
				trace = trace..l..'\n'
			end
		end

		http_channel:push('https://958ha8ong3.execute-api.us-east-2.amazonaws.com/?error='..httpencode(error)..'&file='..httpencode(file)..'&function_line='..httpencode(function_line)..'&trace='..httpencode(trace)..'&version='..(G.VERSION))
        ]=]
    end

    if not love.window or not love.graphics or not love.event then
        return
    end

    if not love.graphics.isCreated() or not love.window.isOpen() then
        local success, status = pcall(love.window.setMode, 800, 600)
        if not success or not status then
            return
        end
    end

    -- Reset state.
    if love.mouse then
        love.mouse.setVisible(true)
        love.mouse.setGrabbed(false)
        love.mouse.setRelativeMode(false)
    end
    if love.joystick then
        -- Stop all joystick vibrations.
        for i, v in ipairs(love.joystick.getJoysticks()) do
            v:setVibration()
        end
    end
    if love.audio then
        love.audio.stop()
    end

    love.graphics.reset()
    local font = love.graphics.setNewFont(14)

    love.graphics.setColor(1, 1, 1)

    local trace = debug.traceback()

    love.graphics.origin()

    local sanitizedmsg = {}
    for char in msg:gmatch(utf8.charpattern) do
        table.insert(sanitizedmsg, char)
    end
    sanitizedmsg = table.concat(sanitizedmsg)

    local err = {}

    table.insert(err, "Error\n")
    table.insert(err, sanitizedmsg)

    if #sanitizedmsg ~= #msg then
        table.insert(err, "Invalid UTF-8 string in error message.")
    end

    table.insert(err, "\n")

    for l in string.gmatch(trace, "(.-)\n") do
        if not string.match(l, "boot.lua") then
            l = string.gsub(l, "stack traceback:", "Traceback\n")
            table.insert(err, l)
        end
    end

    local p = table.concat(err, "\n")

    p = string.gsub(p, "\t", "")
    p = string.gsub(p, "%[string \"(.-)\"%]", "%1")

    local function draw()
        if not love.graphics.isActive() then
            return
        end
        local pos = 70
        love.graphics.clear(89 / 255, 157 / 255, 220 / 255)
        love.graphics.printf(p, pos, pos, love.graphics.getWidth() - pos)
        love.graphics.present()
    end

    local full_error_text = p
    local function copyToClipboard()
        if not love.system then
            return
        end
        love.system.setClipboardText(full_error_text)
        p = p .. "\nCopied to clipboard!"
    end

    if love.system then
        p = p .. "\n\nPress Ctrl+C or tap to copy this error"
    end

    while true do
        love.event.pump()

        for name, a, b, c, d, e, f in love.event.poll() do
            if name == "quit" then
                return 1
            elseif name == "keypressed" and name == "escape" then
                return 1
            elseif name == "keypressed" and a == "c" and love.keyboard.isDown("lctrl", "rctrl") then
                copyToClipboard()
            elseif name == "touchpressed" then
                local name = love.window.getTitle()
                if #name == 0 or name == "Untitled" then
                    name = "Game"
                end
                local buttons = {"OK", "Cancel"}
                if love.system then
                    buttons[3] = "Copy to clipboard"
                end
                local pressed = love.window.showMessageBox("Quit " .. name .. "?", "", buttons)
                if pressed == 1 then
                    return 1
                elseif pressed == 3 then
                    copyToClipboard()
                end
            end
        end

        draw()

        if love.timer then
            love.timer.sleep(0.1)
        end
    end
end
