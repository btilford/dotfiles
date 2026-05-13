-- Key bindings using the real Hyprland Lua API (hl.dsp.*)

-- Applications (single-string format works)
hl.bind("SUPER + o", hl.dsp.submap("open-cmd"))
hl.define_submap("open-cmd", function()
	hl.bind("b", hl.dsp.exec_cmd("/usr/bin/brave"))
	hl.bind("t", hl.dsp.exec_cmd("/usr/bin/ghostty"))
	hl.bind("c", hl.dsp.exec_cmd("/usr/bin/speedcrunch"))
	hl.bind("e", hl.dsp.exec_cmd("/usr/bin/smile"))

	hl.bind("z", hl.dsp.exec_cmd("missioncenter"))
	hl.bind("escape", hl.dsp.submap("reset"))
end)
-- Window management
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + Q", hl.dsp.exec_cmd("sh -c \"hyprctl activewindow | grep pid | tr -d 'pid:' | xargs kill\""))
hl.bind("SUPER + S", hl.dsp.layout("togglesplit"))
hl.bind("SUPER + G", hl.dsp.exec_cmd("hyprctl dispatch togglegroup"))

-- Focus movement
hl.bind("SUPER + h", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + l", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + k", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + j", hl.dsp.focus({ direction = "down" }))

-- Mouse drag/resize
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Move active window to workspace
hl.bind("SUPER + ALT + h", hl.dsp.window.move({ workspace = -1 }))
hl.bind("SUPER + ALT + j", hl.dsp.window.move({ workspace = 2 }))
hl.bind("SUPER + ALT + k", hl.dsp.window.move({ workspace = 1 }))
hl.bind("SUPER + ALT + l", hl.dsp.window.move({ workspace = "+1" }))

hl.bind("SUPER + d", hl.dsp.submap("workspace-cmd"))
hl.define_submap("workspace-cmd", function()
	hl.bind("TAB", hl.dsp.workspace.move({ workspace = "+1", monitor = "current" }))
	hl.bind("SHIFT + TAB", hl.dsp.workspace.move({ workspace = "-1", monitor = "current" }))
	hl.bind("CTRL + TAB", hl.dsp.window.move({ workspace = "next_per_monitor", follow = true }))
	hl.bind("CTRL + SHIFT + TAB", hl.dsp.window.move({ workspace = "previous_per_monitor", follow = true }))

	-- Move window to workspace by number
	hl.bind("CTRL + x", hl.dsp.window.move({ workspace = "1", follow = true }))
	hl.bind("CTRL + c", hl.dsp.window.move({ workspace = "2", follow = true }))
	hl.bind("CTRL + v", hl.dsp.window.move({ workspace = "3", follow = true }))
	hl.bind("CTRL + s", hl.dsp.window.move({ workspace = "4", follow = true }))
	hl.bind("CTRL + d", hl.dsp.window.move({ workspace = "5", follow = true }))
	hl.bind("CTRL + f", hl.dsp.window.move({ workspace = "6", follow = true }))
	hl.bind("CTRL + w", hl.dsp.window.move({ workspace = "7", follow = true }))
	hl.bind("CTRL + e", hl.dsp.window.move({ workspace = "8", follow = true }))
	hl.bind("CTRL + r", hl.dsp.window.move({ workspace = "9", follow = true }))
	hl.bind("CTRL + b", hl.dsp.window.move({ workspace = "0", follow = true }))

	-- Focus workspace by number
	hl.bind("1", hl.dsp.focus({ workspace = "1" }))
	hl.bind("2", hl.dsp.focus({ workspace = "2" }))
	hl.bind("3", hl.dsp.focus({ workspace = "3" }))
	hl.bind("4", hl.dsp.focus({ workspace = "4" }))
	hl.bind("5", hl.dsp.focus({ workspace = "5" }))
	hl.bind("6", hl.dsp.focus({ workspace = "6" }))
	hl.bind("7", hl.dsp.focus({ workspace = "7" }))
	hl.bind("8", hl.dsp.focus({ workspace = "8" }))
	hl.bind("9", hl.dsp.focus({ workspace = "9" }))
	hl.bind("0", hl.dsp.focus({ workspace = "10" }))
	hl.bind("escape", hl.dsp.submap("reset"))
end)

hl.define_submap("window-cmd", function()
	-- hl.bind("SHIFT + h", hl.dsp.resize({ x = 10, y = 0, relative = true }), { repeating = true })
	hl.bind("TAB", function()
		hl.dispatch(hl.dsp.window.cycle_next())
		hl.dispatch(hl.dsp.window.bring_to_top())
	end)

	hl.bind("q", hl.dsp.window.close())
	hl.bind("c", hl.dsp.window.center())
	hl.bind("f", hl.dsp.window.fullscreen())
	hl.bind("f", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
	hl.bind("m", hl.dsp.window.fullscreen({ mode = "maximized" }))
	hl.bind("t", hl.dsp.window.float())

	hl.bind("s", hl.dsp.submap("window-swap"))
	hl.define_submap("window-swap", function()
		hl.bind("h", hl.dsp.window.swap({ direction = "left" }))
		hl.bind("j", hl.dsp.window.swap({ direction = "down" }))
		hl.bind("k", hl.dsp.window.swap({ direction = "up" }))
		hl.bind("k", hl.dsp.window.swap({ direction = "up" }))
		hl.bind("l", hl.dsp.window.swap({ direction = "right" }))
		hl.bind("escape", hl.dsp.submap("window-cmd"))
	end)
	-- hl.bind("SHIFT + t", hl.dsp.float())
	-- hl.bind("SHIFT + t", hl.dsp.float())
	-- hl.bind("b", focus browser)
	-- hl.bind("b", focus browser)
	-- hl.bind("g", focus terminal)
	-- hl.bind("g", focus terminal)

	hl.bind("CTRL + h", hl.dsp.window.move({ direction = "left" }))
	hl.bind("CTRL + h", hl.dsp.window.move({ direction = "left" }))
	hl.bind("CTRL + j", hl.dsp.window.move({ direction = "down" }))
	hl.bind("CTRL + k", hl.dsp.window.move({ direction = "up" }))
	hl.bind("CTRL + l", hl.dsp.window.move({ direction = "right" }))

	hl.bind("ALT + h", hl.dsp.window.move({ x = -10, y = 0, relative = true }))
	hl.bind("ALT + j", hl.dsp.window.move({ x = 0, y = 10, relative = true }))
	hl.bind("ALT + k", hl.dsp.window.move({ x = 10, y = -10, relative = true }))
	hl.bind("ALT + l", hl.dsp.window.move({ x = 10, y = 0, relative = true }))

	hl.bind("SHIFT + h", hl.dsp.window.resize({ x = -10, y = 0, relative = true }))
	hl.bind("SHIFT + j", hl.dsp.window.resize({ x = 0, y = 10, relative = true }))
	hl.bind("SHIFT + k", hl.dsp.window.resize({ x = 0, y = -10, relative = true }))
	hl.bind("SHIFT + l", hl.dsp.window.resize({ x = 10, y = 0, relative = true }))

	hl.bind("CTRL + SHIFT + h", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
	hl.bind("CTRL + SHIFT + j", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))
	hl.bind("CTRL + SHIFT + k", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
	hl.bind("CTRL + SHIFT + l", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))

	-- Focus movement within submap
	hl.bind("h", hl.dsp.focus({ direction = "left" }))
	hl.bind("j", hl.dsp.focus({ direction = "down" }))
	hl.bind("k", hl.dsp.focus({ direction = "up" }))
	hl.bind("l", hl.dsp.focus({ direction = "right" }))
	--
	-- Use `reset` to go back to the global submap
	hl.bind("escape", hl.dsp.submap("reset"))
end)

-- focus submap for focusing specific applications
hl.bind("SUPER + f", hl.dsp.submap("focus-cmd"))

hl.define_submap("focus-cmd", function()
	-- Focus terminal (ghostty)
	hl.bind("t", function()
		hl.dispatch(hl.dsp.focus({ window = "class:com.mitchellh.ghostty" }))
	end)
	hl.bind("b", function()
		hl.dispatch(hl.dsp.focus({ window = "class:brave-browser" }))
	end)
	hl.bind("l", hl.dsp.focus({ last = true }))

	-- Exit submap
	hl.bind("escape", hl.dsp.submap("reset"))
end)

-- Actions
hl.bind("SUPER + CTRL + RETURN", hl.dsp.exec_cmd('sh -c "pkill rofi || rofi -show drun -replace -i"'))
hl.bind("SUPER + r", hl.dsp.exec_cmd('sh -c "pkill rofi || rofi -show drun -replace -i"'))
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd('sh -c "$HOME/.config/waybar/launch.sh"'))
hl.bind("SUPER + Escape", function()
	os.execute("setsid -f wlogout --protocol layer-shell")
end)
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("loginctl lock-session"))

-- Workspace switching
hl.bind("SUPER + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind("SUPER + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind("SUPER + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind("SUPER + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind("SUPER + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind("SUPER + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind("SUPER + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind("SUPER + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind("SUPER + 0", hl.dsp.focus({ workspace = 10 }))

-- Move window to workspace
hl.bind("SUPER + ALT + x", hl.dsp.window.move({ workspace = 1 }))
hl.bind("SUPER + ALT + c", hl.dsp.window.move({ workspace = 2 }))
hl.bind("SUPER + ALT + v", hl.dsp.window.move({ workspace = 3 }))
hl.bind("SUPER + ALT + s", hl.dsp.window.move({ workspace = 4 }))
hl.bind("SUPER + ALT + d", hl.dsp.window.move({ workspace = 5 }))
hl.bind("SUPER + ALT + f", hl.dsp.window.move({ workspace = 6 }))
hl.bind("SUPER + ALT + w", hl.dsp.window.move({ workspace = 7 }))
hl.bind("SUPER + ALT + e", hl.dsp.window.move({ workspace = 8 }))
hl.bind("SUPER + ALT + r", hl.dsp.window.move({ workspace = 9 }))
hl.bind("SUPER + ALT + b", hl.dsp.window.move({ workspace = 10 }))

-- Workspace cycling
hl.bind("SUPER + Tab", hl.dsp.focus({ workspace = "m+1" }))
hl.bind("SUPER + SHIFT + Tab", hl.dsp.focus({ workspace = "m-1" }))
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + CTRL + down", hl.dsp.focus({ workspace = "empty" }))

-- Media keys (no modifier)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -q s +10%"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q s 10%-"), { locked = true, repeating = true })
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"),
	{ locked = true, repeating = true }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"), { locked = true })

-- Keyboard backlight
hl.bind("code:238", hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s +10"))
hl.bind("code:237", hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s 10-"))

-- Clipboard and file manager
hl.bind(
	"CTRL + ALT + V",
	hl.dsp.exec_cmd("ghostty --class=app.clipse --window-padding-x=10,10 --confirm-close-surface=false -e clipse")
)
hl.bind(
	"SUPER + E",
	hl.dsp.exec_cmd("ghostty --class=app.filemanager --window-padding-x=10,10 --confirm-close-surface=false -e yazi")
)
