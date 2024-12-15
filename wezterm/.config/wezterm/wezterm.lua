local wezterm = require 'wezterm'

local config = wezterm.config_builder()

config.color_scheme = 'Darcula (base16)'
-- config.color_scheme = 'Dark Ocean (terminal.sexy)'
config.font = wezterm.font 'JetBrains Mono'
-- config.default_prog = { '/usr/bin/zellij', '-1' }
-- Temporary fix until scaled screens are supported
-- config.enable_wayland = false
return config
