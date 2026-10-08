local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "Darcula (base16)"
-- config.color_scheme = 'Dark Ocean (terminal.sexy)'
config.font = wezterm.font("JetBrains Mono")
-- config.default_prog = { '/usr/bin/zellij', '-1' }
-- Temporary fix until scaled screens are supported
-- config.enable_wayland = false

-- Windows: open straight into WSL; PowerShell and cmd are never used here.
-- Matched by prefix so a distro upgrade (Ubuntu-26.04 -> ...) needs no edit,
-- and so podman-machine-default, also a WSL distro, is never picked.
if wezterm.target_triple:find("windows") then
  local domains = wezterm.default_wsl_domains()
  for _, dom in ipairs(domains) do
    dom.default_cwd = "~" -- otherwise new panes start in the Windows cwd
    if not config.default_domain and dom.distribution:find("^Ubuntu") then
      config.default_domain = dom.name
    end
  end
  config.wsl_domains = domains
end

return config
