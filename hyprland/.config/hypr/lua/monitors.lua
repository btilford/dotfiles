-- Monitor configuration.
--
-- The monitor table itself is MACHINE-LOCAL and untracked. `desc:` matching needs
-- the panel serial to tell two identical models apart — this desk has two DELL
-- S2725QC, so the model prefix alone is ambiguous — and serials are hardware
-- identifiers that do not belong in a public repo.
--
-- Per machine:
--
--   cp ~/.config/hypr/lua/monitors.example.lua \
--      ~/.config/hypr/lua/monitors.local.lua
--
-- Find the descriptors with:  hyprctl monitors all | grep -E 'Monitor|description'
--
-- `*.local.lua` is reserved in .gitignore and .stow-local-ignore so it cannot be
-- committed by accident, and scripts/no-local-values.sh fails any commit that
-- contains a `desc:` serial.
--
-- With no local file, Hyprland keeps its own auto-detection: an unarranged but
-- working desktop rather than a black screen.

local local_config = os.getenv("HOME") .. "/.config/hypr/lua/monitors.local.lua"

local f = io.open(local_config, "r")
if f then
  f:close()
  dofile(local_config)
end

-- Publish the alias table for later modules (keyboard.lua, workspaces.lua — both
-- required after this one in hyprland.lua). Missing keys resolve to "" rather than
-- nil so a machine with no local file still loads: workspaces simply are not
-- pinned to a monitor.
MON = MON or {}
setmetatable(MON, {
  __index = function()
    return ""
  end,
})
