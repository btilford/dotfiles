-- Hyprland Lua Config Module Loader
-- Loads all modules in the correct order

-- Colors (must be early for other modules to reference)
local colors = require("lua.colors")
_G.colors = colors

-- Core system configuration
require("lua.monitors")
require("lua.environments")
require("lua.keyboard")
require("lua.windows")
require("lua.decorations")
require("lua.layouts")
require("lua.workspaces")
require("lua.misc")
require("lua.keybindings")
require("lua.windowrules")
require("lua.animations")
require("lua.custom")
require("lua.autostart")
