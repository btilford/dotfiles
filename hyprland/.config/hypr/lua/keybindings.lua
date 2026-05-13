-- Key bindings using the real Hyprland Lua API (hl.dsp.*)
-- Window management prioritized on simple SUPER. Workspace switching on SUPER+number.

-- Applications
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("/usr/bin/ghostty"))
hl.bind("SUPER + B", hl.dsp.exec_cmd("/usr/bin/brave"))
hl.bind("SUPER + CTRL + E", hl.dsp.exec_cmd("/usr/bin/smile"))
hl.bind("SUPER + CTRL + C", hl.dsp.exec_cmd("/usr/bin/speedcrunch"))

-- Window management
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + Q", hl.dsp.exec_cmd("sh -c \"hyprctl activewindow | grep pid | tr -d 'pid:' | xargs kill\""))
hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + M", hl.dsp.window.fullscreen({mode = "maximized"}))
hl.bind("SUPER + T", hl.dsp.exec_cmd('hyprctl --batch "dispatch togglefloating; dispatch centerwindow 1"'))
hl.bind("SUPER + C", hl.dsp.exec_cmd('hyprctl --batch "dispatch centerwindow 1"'))
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("hyprctl dispatch workspaceopt allfloat"))
hl.bind("SUPER + S", hl.dsp.layout("togglesplit"))
hl.bind("SUPER + G", hl.dsp.exec_cmd("hyprctl dispatch togglegroup"))
hl.bind("SUPER + D", hl.dsp.exec_cmd("hyprctl dispatch swapsplit right"))

-- Focus movement
hl.bind("SUPER + h", hl.dsp.focus({direction = "left"}))
hl.bind("SUPER + l", hl.dsp.focus({direction = "right"}))
hl.bind("SUPER + k", hl.dsp.focus({direction = "up"}))
hl.bind("SUPER + j", hl.dsp.focus({direction = "down"}))

-- Mouse drag/resize
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), {mouse = true})
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), {mouse = true})

-- Move window (keyboard) - use hl.exec_cmd inside function for compositor context
hl.bind("SUPER + CTRL + h", function() hl.exec_cmd("hyprctl dispatch movewindow l") end)
hl.bind("SUPER + CTRL + j", function() hl.exec_cmd("hyprctl dispatch movewindow d") end)
hl.bind("SUPER + CTRL + k", function() hl.exec_cmd("hyprctl dispatch movewindow u") end)
hl.bind("SUPER + CTRL + l", function() hl.exec_cmd("hyprctl dispatch movewindow r") end)

-- Move active window to workspace
hl.bind("SUPER + ALT + h", hl.dsp.window.move({workspace = -1}))
hl.bind("SUPER + ALT + j", hl.dsp.window.move({workspace = 2}))
hl.bind("SUPER + ALT + k", hl.dsp.window.move({workspace = 1}))
hl.bind("SUPER + ALT + l", hl.dsp.window.move({workspace = "+1"}))

-- Resize window (keyboard) - use hl.exec_cmd inside function for compositor context
hl.bind("SUPER + SHIFT + h", function() hl.exec_cmd("hyprctl dispatch resizeactive -100 0") end)
hl.bind("SUPER + SHIFT + j", function() hl.exec_cmd("hyprctl dispatch resizeactive 0 100") end)
hl.bind("SUPER + SHIFT + k", function() hl.exec_cmd("hyprctl dispatch resizeactive 0 -100") end)
hl.bind("SUPER + SHIFT + l", function() hl.exec_cmd("hyprctl dispatch resizeactive 100 0") end)

-- Actions
hl.bind("SUPER + CTRL + RETURN", hl.dsp.exec_cmd("sh -c \"pkill rofi || rofi -show drun -replace -i\""))
hl.bind("SUPER + r", hl.dsp.exec_cmd("sh -c \"pkill rofi || rofi -show drun -replace -i\""))
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("sh -c \"$HOME/.config/waybar/launch.sh\""))
hl.bind("SUPER + Z", hl.dsp.exec_cmd("missioncenter"))
hl.bind("SUPER + Escape", function() os.execute("setsid -f wlogout --protocol layer-shell") end)
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("loginctl lock-session"))

-- Workspace switching
hl.bind("SUPER + 1", hl.dsp.focus({workspace = 1}))
hl.bind("SUPER + 2", hl.dsp.focus({workspace = 2}))
hl.bind("SUPER + 3", hl.dsp.focus({workspace = 3}))
hl.bind("SUPER + 4", hl.dsp.focus({workspace = 4}))
hl.bind("SUPER + 5", hl.dsp.focus({workspace = 5}))
hl.bind("SUPER + 6", hl.dsp.focus({workspace = 6}))
hl.bind("SUPER + 7", hl.dsp.focus({workspace = 7}))
hl.bind("SUPER + 8", hl.dsp.focus({workspace = 8}))
hl.bind("SUPER + 9", hl.dsp.focus({workspace = 9}))
hl.bind("SUPER + 0", hl.dsp.focus({workspace = 10}))

-- Move window to workspace
hl.bind("SUPER + ALT + x", hl.dsp.window.move({workspace = 1}))
hl.bind("SUPER + ALT + c", hl.dsp.window.move({workspace = 2}))
hl.bind("SUPER + ALT + v", hl.dsp.window.move({workspace = 3}))
hl.bind("SUPER + ALT + s", hl.dsp.window.move({workspace = 4}))
hl.bind("SUPER + ALT + d", hl.dsp.window.move({workspace = 5}))
hl.bind("SUPER + ALT + f", hl.dsp.window.move({workspace = 6}))
hl.bind("SUPER + ALT + w", hl.dsp.window.move({workspace = 7}))
hl.bind("SUPER + ALT + e", hl.dsp.window.move({workspace = 8}))
hl.bind("SUPER + ALT + r", hl.dsp.window.move({workspace = 9}))
hl.bind("SUPER + ALT + b", hl.dsp.window.move({workspace = 10}))

-- Workspace cycling
hl.bind("SUPER + Tab", hl.dsp.focus({workspace = "m+1"}))
hl.bind("SUPER + SHIFT + Tab", hl.dsp.focus({workspace = "m-1"}))
hl.bind("SUPER + mouse_down", hl.dsp.focus({workspace = "e+1"}))
hl.bind("SUPER + mouse_up", hl.dsp.focus({workspace = "e-1"}))
hl.bind("SUPER + CTRL + down", hl.dsp.focus({workspace = "empty"}))

-- Media keys
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -q s +10%"), {locked = true, repeating = true})
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q s 10%-"), {locked = true, repeating = true})
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"), {locked = true, repeating = true})
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"), {locked = true, repeating = true})
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), {locked = true})
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), {locked = true})
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"), {locked = true})
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), {locked = true})
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), {locked = true})
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"), {locked = true})

-- Keyboard backlight
hl.bind("code:238", hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s +10"))
hl.bind("code:237", hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s 10-"))

-- Clipboard and file manager
hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd("ghostty --class=app.clipse --window-padding-x=10,10 --confirm-close-surface=false -e clipse"))
hl.bind("SUPER + E", hl.dsp.exec_cmd("ghostty --class=app.filemanager --window-padding-x=10,10 --confirm-close-surface=false -e yazi"))
