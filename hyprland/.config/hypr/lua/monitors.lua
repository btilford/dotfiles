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

-- Clear stale scanout content on hotplug.
--
-- An output added mid-session comes up with whatever was in the framebuffer it was
-- allocated: on this machine a small static patch of colored noise, top-left,
-- which nothing ever repaints away. Damage tracking is why -- Hyprland only draws
-- the regions it believes changed, and a region it has never drawn keeps the
-- uninitialised memory underneath. `debug:damage_tracking = 0` (full repaint every
-- frame) does NOT fix it, because a repaint still writes into the same buffer; the
-- buffer itself has to be replaced, which means a modeset.
--
-- It is invisible to a screenshot: `grim` renders the scene into a fresh buffer,
-- so the artifact is visible on glass and absent from the capture. That is what
-- made it look like a cable or panel fault for so long. Verified 2026-08-19 by
-- blanking the output -- the patch vanished and did not return.
--
-- DPMS off/on is the cheapest modeset reachable from here. The delay lets the
-- output finish coming up first; cycling it immediately races Hyprland's own
-- setup and the garbage survives.
--
-- Startup is excluded deliberately: monitor.added fires for every display at
-- launch, and a black flash across the whole desk on every login is a worse bug
-- than the one being fixed. Displays present at launch get a modeset from the
-- initial configuration anyway.
local session_ready = false

hl.on("hyprland.start", function()
  hl.timer(function()
    session_ready = true
  end, { timeout = 10000, type = "oneshot" })
end)

-- Internal laptop panels are skipped: a lid open re-enables eDP and fires this,
-- and that path already carries a modeset of its own, so a cycle there is a black
-- flash for nothing.
hl.on("monitor.added", function(mon)
  if not session_ready or not mon or not mon.name then
    return
  end
  local name = mon.name
  if name:match("^eDP") or name:match("^LVDS") then
    return
  end
  hl.timer(function()
    hl.dispatch(hl.dsp.dpms("off", name))
    hl.timer(function()
      hl.dispatch(hl.dsp.dpms("on", name))
    end, { timeout = 400, type = "oneshot" })
  end, { timeout = 1500, type = "oneshot" })
end)
