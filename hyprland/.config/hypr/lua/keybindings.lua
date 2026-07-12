-- Key bindings using the real Hyprland Lua API (hl.dsp.*)
-- Every bind carries a { description = ... } so `hyprctl binds` is readable.

-- Applications (single-string format works)
hl.bind("SUPER + o", hl.dsp.submap("open-cmd"), { description = "Open-app submap [open-cmd]" })
hl.define_submap("open-cmd", function()
	hl.bind("b", hl.dsp.exec_cmd("/usr/bin/brave"), { description = "Launch Brave" })
	hl.bind("t", hl.dsp.exec_cmd("/usr/bin/ghostty"), { description = "Launch Ghostty terminal" })
	hl.bind("c", hl.dsp.exec_cmd("/usr/bin/speedcrunch"), { description = "Launch SpeedCrunch calculator" })
	hl.bind(
		"e",
		hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh emoji"'),
		{ description = "Emoji picker (launcher emoji mode)" }
	)
	hl.bind(
		"u",
		hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh glyphs"'),
		{ description = "Glyph picker: unicode + nerd font (launcher glyphs mode)" }
	)
	hl.bind(
		"i",
		hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh icons"'),
		{ description = "Icon browser (launcher icons mode)" }
	)
	hl.bind(
		"v",
		hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh clip"'),
		{ description = "Clipboard history (launcher clip mode)" }
	)

	hl.bind("z", hl.dsp.exec_cmd("missioncenter"), { description = "Launch Mission Center" })
	hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
-- Window management
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close active window" })
hl.bind(
	"SUPER + SHIFT + Q",
	hl.dsp.exec_cmd("sh -c \"hyprctl activewindow | grep pid | tr -d 'pid:' | xargs kill\""),
	{ description = "Force-kill active window" }
)
hl.bind("SUPER + S", hl.dsp.layout("togglesplit"), { description = "Toggle split direction" })
local cycle_layouts = { "dwindle", "master", "scrolling" }
local cycle_layout_idx = 1

local function cycle_workspace_layout()
	local ws = hl.get_active_workspace()
	local current = ws and (ws.tiled_layout or ws.layout)
	local found = false

	if current then
		for i = 1, #cycle_layouts do
			if cycle_layouts[i] == current then
				cycle_layout_idx = i
				found = true
				break
			end
		end
	end

	if not found then
		cycle_layout_idx = 1
	end

	cycle_layout_idx = (cycle_layout_idx % #cycle_layouts) + 1
	local next_layout = cycle_layouts[cycle_layout_idx]

	hl.workspace_rule({
		workspace = tostring(ws.id),
		layout = next_layout,
	})
end

hl.bind("SUPER + SHIFT + L", cycle_workspace_layout, { description = "Cycle workspace layout (dwindle/master/scrolling)" })
hl.bind("SUPER + G", hl.dsp.exec_cmd("hyprctl dispatch togglegroup"), { description = "Toggle window group" })

-- Focus movement
hl.bind("SUPER + h", hl.dsp.focus({ direction = "left" }), { description = "Focus window left" })
hl.bind("SUPER + l", hl.dsp.focus({ direction = "right" }), { description = "Focus window right" })
hl.bind("SUPER + k", hl.dsp.focus({ direction = "up" }), { description = "Focus window up" })
hl.bind("SUPER + j", hl.dsp.focus({ direction = "down" }), { description = "Focus window down" })

-- Mouse drag/resize
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Drag-move window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Drag-resize window" })

-- Move active window to workspace
hl.bind("SUPER + ALT + h", hl.dsp.window.move({ workspace = -1 }), { description = "Move window to previous workspace" })
hl.bind("SUPER + ALT + j", hl.dsp.window.move({ workspace = 2 }), { description = "Move window to workspace 2" })
hl.bind("SUPER + ALT + k", hl.dsp.window.move({ workspace = 1 }), { description = "Move window to workspace 1" })
hl.bind("SUPER + ALT + l", hl.dsp.window.move({ workspace = "+1" }), { description = "Move window to next workspace" })

hl.bind("SUPER + d", hl.dsp.submap("workspace-cmd"), { description = "Workspace submap [workspace-cmd]" })
hl.define_submap("workspace-cmd", function()
	hl.bind("TAB", hl.dsp.workspace.move({ workspace = "+1", monitor = "current" }), { description = "Next workspace (this monitor)" })
	hl.bind("SHIFT + TAB", hl.dsp.workspace.move({ workspace = "-1", monitor = "current" }), { description = "Previous workspace (this monitor)" })
	hl.bind("CTRL + TAB", hl.dsp.window.move({ workspace = "next_per_monitor", follow = true }), { description = "Move window to next workspace (follow)" })
	hl.bind("CTRL + SHIFT + TAB", hl.dsp.window.move({ workspace = "previous_per_monitor", follow = true }), { description = "Move window to previous workspace (follow)" })

	-- Move window to workspace by number
	hl.bind("CTRL + x", hl.dsp.window.move({ workspace = "1", follow = true }), { description = "Move window to workspace 1 (follow)" })
	hl.bind("CTRL + c", hl.dsp.window.move({ workspace = "2", follow = true }), { description = "Move window to workspace 2 (follow)" })
	hl.bind("CTRL + v", hl.dsp.window.move({ workspace = "3", follow = true }), { description = "Move window to workspace 3 (follow)" })
	hl.bind("CTRL + s", hl.dsp.window.move({ workspace = "4", follow = true }), { description = "Move window to workspace 4 (follow)" })
	hl.bind("CTRL + d", hl.dsp.window.move({ workspace = "5", follow = true }), { description = "Move window to workspace 5 (follow)" })
	hl.bind("CTRL + f", hl.dsp.window.move({ workspace = "6", follow = true }), { description = "Move window to workspace 6 (follow)" })
	hl.bind("CTRL + w", hl.dsp.window.move({ workspace = "7", follow = true }), { description = "Move window to workspace 7 (follow)" })
	hl.bind("CTRL + e", hl.dsp.window.move({ workspace = "8", follow = true }), { description = "Move window to workspace 8 (follow)" })
	hl.bind("CTRL + r", hl.dsp.window.move({ workspace = "9", follow = true }), { description = "Move window to workspace 9 (follow)" })
	hl.bind("CTRL + b", hl.dsp.window.move({ workspace = "0", follow = true }), { description = "Move window to workspace 10 (follow)" })

	-- Focus workspace by number
	hl.bind("1", hl.dsp.focus({ workspace = "1" }), { description = "Focus workspace 1" })
	hl.bind("2", hl.dsp.focus({ workspace = "2" }), { description = "Focus workspace 2" })
	hl.bind("3", hl.dsp.focus({ workspace = "3" }), { description = "Focus workspace 3" })
	hl.bind("4", hl.dsp.focus({ workspace = "4" }), { description = "Focus workspace 4" })
	hl.bind("5", hl.dsp.focus({ workspace = "5" }), { description = "Focus workspace 5" })
	hl.bind("6", hl.dsp.focus({ workspace = "6" }), { description = "Focus workspace 6" })
	hl.bind("7", hl.dsp.focus({ workspace = "7" }), { description = "Focus workspace 7" })
	hl.bind("8", hl.dsp.focus({ workspace = "8" }), { description = "Focus workspace 8" })
	hl.bind("9", hl.dsp.focus({ workspace = "9" }), { description = "Focus workspace 9" })
	hl.bind("0", hl.dsp.focus({ workspace = "10" }), { description = "Focus workspace 10" })
	hl.bind("l", cycle_workspace_layout, { description = "Cycle workspace layout" })

	-- Desktop appearance
	hl.bind("w", hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/WallpaperSelect.sh"'), { description = "Wallpaper chooser" })
	hl.bind("SHIFT + w", hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/WallpaperRandom.sh"'), { description = "Random wallpaper" })
	hl.bind("t", hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/ThemeChanger.sh"'), { description = "Theme chooser" })

	hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
hl.bind("SUPER + w", hl.dsp.submap("window-cmd"), { description = "Window submap [window-cmd]" })
hl.define_submap("window-cmd", function()
	-- hl.bind("SHIFT + h", hl.dsp.resize({ x = 10, y = 0, relative = true }), { repeating = true })
	hl.bind("TAB", function()
		hl.dispatch(hl.dsp.window.cycle_next())
		hl.dispatch(hl.dsp.window.bring_to_top())
	end, { description = "Cycle to next window (raise)" })

	hl.bind("n", hl.dsp.layout("togglesplit"), { description = "Toggle split direction" })
	hl.bind("SUPER + l", hl.dsp.layout("dwindle"), { description = "Set dwindle layout" })
	hl.bind("r", function()
		local ws = hl.get_active_workspace()
		if ws then
			if ws.tiled_layout == "master" then
				hl.dispatch(hl.dsp.layout("orientationnext"))
			elseif ws.tiled_layout == "dwindle" then
				hl.dispatch(hl.dsp.layout("togglesplit"))
			end
		end
	end, { description = "Rotate layout (master orientation / dwindle split)" })
	hl.bind("SHIFT + r", function()
		local ws = hl.get_active_workspace()
		if ws and ws.tiled_layout == "master" then
			hl.dispatch(hl.dsp.layout("orientationprev"))
		end
	end, { description = "Rotate master orientation backward" })
	hl.bind("comma", function()
		local ws = hl.get_active_workspace()
		if ws then
			if ws.tiled_layout == "master" then
				hl.dispatch(hl.dsp.layout("swapwithmaster"))
			elseif ws.tiled_layout == "dwindle" then
				hl.dispatch(hl.dsp.layout("swapsplit"))
			end
		end
	end, { description = "Swap with master / swap split" })
	hl.bind("period", function()
		local ws = hl.get_active_workspace()
		if ws and ws.tiled_layout == "master" then
			hl.dispatch(hl.dsp.layout("rollnext"))
		end
	end, { description = "Roll windows forward (master)" })

	hl.bind("q", hl.dsp.window.close(), { description = "Close active window" })
	hl.bind("c", hl.dsp.window.center(), { description = "Center window" })
	hl.bind("f", hl.dsp.window.fullscreen(), { description = "Toggle fullscreen" })
	hl.bind("m", hl.dsp.window.fullscreen({ mode = "maximized" }), { description = "Maximize window" })
	hl.bind("t", hl.dsp.window.float(), { description = "Toggle floating" })

	hl.bind("s", hl.dsp.submap("window-swap"), { description = "Window-swap submap [window-swap]" })
	hl.define_submap("window-swap", function()
		hl.bind("h", hl.dsp.window.swap({ direction = "left" }), { description = "Swap window left" })
		hl.bind("j", hl.dsp.window.swap({ direction = "down" }), { description = "Swap window down" })
		hl.bind("k", hl.dsp.window.swap({ direction = "up" }), { description = "Swap window up" })
		hl.bind("l", hl.dsp.window.swap({ direction = "right" }), { description = "Swap window right" })
		hl.bind("escape", hl.dsp.submap("window-cmd"), { description = "Back to window submap" })
	end)
	-- hl.bind("SHIFT + t", hl.dsp.float())
	-- hl.bind("SHIFT + t", hl.dsp.float())
	-- hl.bind("b", focus browser)
	-- hl.bind("b", focus browser)
	-- hl.bind("g", focus terminal)
	-- hl.bind("g", focus terminal)

	hl.bind("CTRL + h", hl.dsp.window.move({ direction = "left" }), { description = "Move window left" })
	hl.bind("CTRL + j", hl.dsp.window.move({ direction = "down" }), { description = "Move window down" })
	hl.bind("CTRL + k", hl.dsp.window.move({ direction = "up" }), { description = "Move window up" })
	hl.bind("CTRL + l", hl.dsp.window.move({ direction = "right" }), { description = "Move window right" })

	hl.bind("ALT + h", hl.dsp.window.move({ x = -10, y = 0, relative = true }), { description = "Nudge window left" })
	hl.bind("ALT + j", hl.dsp.window.move({ x = 0, y = 10, relative = true }), { description = "Nudge window down" })
	hl.bind("ALT + k", hl.dsp.window.move({ x = 10, y = -10, relative = true }), { description = "Nudge window up-right" })
	hl.bind("ALT + l", hl.dsp.window.move({ x = 10, y = 0, relative = true }), { description = "Nudge window right" })

	hl.bind("SHIFT + h", hl.dsp.window.resize({ x = -10, y = 0, relative = true }), { description = "Shrink window width" })
	hl.bind("SHIFT + j", hl.dsp.window.resize({ x = 0, y = 10, relative = true }), { description = "Grow window height" })
	hl.bind("SHIFT + k", hl.dsp.window.resize({ x = 0, y = -10, relative = true }), { description = "Shrink window height" })
	hl.bind("SHIFT + l", hl.dsp.window.resize({ x = 10, y = 0, relative = true }), { description = "Grow window width" })

	hl.bind("CTRL + SHIFT + h", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { description = "Shrink window width (large)" })
	hl.bind("CTRL + SHIFT + j", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { description = "Grow window height (large)" })
	hl.bind("CTRL + SHIFT + k", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { description = "Shrink window height (large)" })
	hl.bind("CTRL + SHIFT + l", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { description = "Grow window width (large)" })

	-- Focus movement within submap
	hl.bind("h", hl.dsp.focus({ direction = "left" }), { description = "Focus window left" })
	hl.bind("j", hl.dsp.focus({ direction = "down" }), { description = "Focus window down" })
	hl.bind("k", hl.dsp.focus({ direction = "up" }), { description = "Focus window up" })
	hl.bind("l", hl.dsp.focus({ direction = "right" }), { description = "Focus window right" })
	--
	-- Use `reset` to go back to the global submap
	hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

-- focus submap for focusing specific applications
hl.bind("SUPER + f", hl.dsp.submap("focus-cmd"), { description = "Focus-app submap [focus-cmd]" })

hl.define_submap("focus-cmd", function()
	-- Focus terminal (ghostty)
	hl.bind("t", function()
		hl.dispatch(hl.dsp.focus({ window = "class:com.mitchellh.ghostty" }))
	end, { description = "Focus Ghostty terminal" })
	hl.bind("b", function()
		hl.dispatch(hl.dsp.focus({ window = "class:brave-browser" }))
	end, { description = "Focus Brave browser" })
	hl.bind("l", hl.dsp.focus({ last = true }), { description = "Focus last window" })

	-- Exit submap
	hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

-- Actions
-- Launcher/bar dispatch by $HYPR_LAUNCHER / $HYPR_BAR (see hypr/scripts/shell-env.sh).
hl.bind("SUPER + CTRL + RETURN", hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh"'), { description = "App launcher (rofi/quickshell)" })
hl.bind("SUPER + r", hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh"'), { description = "App launcher (rofi/quickshell)" })
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/StartBar.sh"'), { description = "Restart status bar (waybar/quickshell)" })
-- Escape hatch: full config reload. Resets runtime workspace/layout state;
-- theme colors normally arrive via scripts/ApplyHyprColors.sh without this.
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"), { description = "Reload Hyprland config (resets runtime layout state)" })
hl.bind("SUPER + Escape", function()
	-- quickshell session dialog; fall back to wlogout if the qs daemon isn't running
	os.execute("qs ipc call session toggle 2>/dev/null || setsid -f wlogout --protocol layer-shell")
end, { description = "Session/power menu" })
hl.bind("SUPER + slash", function()
	os.execute("qs ipc call keymap toggle 2>/dev/null")
end, { description = "Keymap cheatsheet overlay", submap_universal = true })
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock session" })

-- Workspace switching
hl.bind("SUPER + 1", hl.dsp.focus({ workspace = 1 }), { description = "Focus workspace 1" })
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = 2 }), { description = "Focus workspace 2" })
hl.bind("SUPER + 3", hl.dsp.focus({ workspace = 3 }), { description = "Focus workspace 3" })
hl.bind("SUPER + 4", hl.dsp.focus({ workspace = 4 }), { description = "Focus workspace 4" })
hl.bind("SUPER + 5", hl.dsp.focus({ workspace = 5 }), { description = "Focus workspace 5" })
hl.bind("SUPER + 6", hl.dsp.focus({ workspace = 6 }), { description = "Focus workspace 6" })
hl.bind("SUPER + 7", hl.dsp.focus({ workspace = 7 }), { description = "Focus workspace 7" })
hl.bind("SUPER + 8", hl.dsp.focus({ workspace = 8 }), { description = "Focus workspace 8" })
hl.bind("SUPER + 9", hl.dsp.focus({ workspace = 9 }), { description = "Focus workspace 9" })
hl.bind("SUPER + 0", hl.dsp.focus({ workspace = 10 }), { description = "Focus workspace 10" })

-- Move window to workspace
hl.bind("SUPER + ALT + x", hl.dsp.window.move({ workspace = 1 }), { description = "Move window to workspace 1" })
hl.bind("SUPER + ALT + c", hl.dsp.window.move({ workspace = 2 }), { description = "Move window to workspace 2" })
hl.bind("SUPER + ALT + v", hl.dsp.window.move({ workspace = 3 }), { description = "Move window to workspace 3" })
hl.bind("SUPER + ALT + s", hl.dsp.window.move({ workspace = 4 }), { description = "Move window to workspace 4" })
hl.bind("SUPER + ALT + d", hl.dsp.window.move({ workspace = 5 }), { description = "Move window to workspace 5" })
hl.bind("SUPER + ALT + f", hl.dsp.window.move({ workspace = 6 }), { description = "Move window to workspace 6" })
hl.bind("SUPER + ALT + w", hl.dsp.window.move({ workspace = 7 }), { description = "Move window to workspace 7" })
hl.bind("SUPER + ALT + e", hl.dsp.window.move({ workspace = 8 }), { description = "Move window to workspace 8" })
hl.bind("SUPER + ALT + r", hl.dsp.window.move({ workspace = 9 }), { description = "Move window to workspace 9" })
hl.bind("SUPER + ALT + b", hl.dsp.window.move({ workspace = 10 }), { description = "Move window to workspace 10" })

-- Workspace cycling
hl.bind("SUPER + Tab", hl.dsp.focus({ workspace = "m+1" }), { description = "Next workspace on monitor" })
hl.bind("SUPER + SHIFT + Tab", hl.dsp.focus({ workspace = "m-1" }), { description = "Previous workspace on monitor" })
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace (scroll)" })
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace (scroll)" })
hl.bind("SUPER + CTRL + down", hl.dsp.focus({ workspace = "empty" }), { description = "Focus first empty workspace" })

-- Media keys (no modifier)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -q s +10%"), { locked = true, repeating = true, description = "Brightness +10%" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q s 10%-"), { locked = true, repeating = true, description = "Brightness -10%" })
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"),
	{ locked = true, repeating = true, description = "Volume +5%" }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"),
	{ locked = true, repeating = true, description = "Volume -5%" }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, description = "Toggle mute" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play/pause media" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"), { locked = true, description = "Pause media" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true, description = "Next track" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true, description = "Previous track" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"), { locked = true, description = "Toggle mic mute" })

-- Keyboard backlight
hl.bind("code:238", hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s +10"), { description = "Keyboard backlight +" })
hl.bind("code:237", hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s 10-"), { description = "Keyboard backlight -" })

-- Clipboard and file manager
-- New standalone quickshell ClipboardDialog (clipvault). CTRL+ALT+V below is kept
-- as a fallback (old Launcher clip mode) until the dialog is confirmed stable.
hl.bind(
	"SUPER + V",
	hl.dsp.exec_cmd("qs ipc call clipboard toggle"),
	{ description = "Clipboard history (quickshell dialog)" }
)
hl.bind(
	"CTRL + ALT + V",
	hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh clip"'),
	{ description = "Clipboard history (launcher clip mode)" }
)
hl.bind(
	"SUPER + E",
	hl.dsp.exec_cmd("ghostty --class=app.filemanager --window-padding-x=10,10 --confirm-close-surface=false -e yazi"),
	{ description = "File manager (yazi)" }
)
