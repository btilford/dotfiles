-- Animations using proper Lua API (hl.curve + hl.animation)
-- Reference: https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua

hl.config({
  animations = {
    enabled = true,
    workspace_wraparound = true,
  },
})

-- Bezier curves
hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("winIn", { type = "bezier", points = { { 0.1, 1.1 }, { 0.1, 1.1 } } })
hl.curve("winOut", { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
hl.curve("liner", { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })
hl.curve("ease", { type = "bezier", points = { { 0.25, 0.1 }, { 0.25, 1.0 } } })
hl.curve("snap", { type = "bezier", points = { { 0.5, 0 }, { 0.2, 1 } } })

-- Animation rules
hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "wind", style = "slide" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "winIn", style = "popin" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 8, bezier = "winOut", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 8, bezier = "wind", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 0.5, bezier = "snap" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 2, bezier = "snap", style = "once" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "ease" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 8, bezier = "wind" })
