-- Test file for move/resize keybinds - trying multiple approaches

-- Approach 1: hl.dsp.exec_cmd directly (like working keybinds)
hl.bind("SUPER + CTRL + h", hl.dsp.exec_cmd("hyprctl dispatch movewindow l"))
hl.bind("SUPER + SHIFT + h", hl.dsp.exec_cmd("hyprctl dispatch resizeactive -100 0"))

-- Approach 2: Lua function with hl.exec_cmd (compositor context)
hl.bind("SUPER + CTRL + j", function() hl.exec_cmd("hyprctl dispatch movewindow d") end)
hl.bind("SUPER + SHIFT + j", function() hl.exec_cmd("hyprctl dispatch resizeactive 0 100") end)

-- Approach 3: Native API with string argument
hl.bind("SUPER + CTRL + k", hl.dsp.window.move("u"))
hl.bind("SUPER + SHIFT + k", hl.dsp.window.resize("u", 100))

-- Approach 4: Native API with table argument
hl.bind("SUPER + CTRL + l", hl.dsp.window.move({direction = "r"}))
hl.bind("SUPER + SHIFT + l", hl.dsp.window.resize({direction = "r", delta = 100}))
