-- Greeter-only Hyprland config. greetd runs it as the `greeter` user; it is not
-- the desktop config and must not grow into one — no keybinds, no bar, no
-- autostart beyond the wallpaper and the greeter itself.
--
-- Monitors: every output is enabled, so hotplug and a closed laptop lid behave
-- exactly as in a session. ReGreet is one window, so it lands on one output —
-- MON.main when the machine-local layout names one, else wherever the cursor is.

-- Fallback for every output, including ones the local layout does not name.
hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto",
  scale = "auto",
})

-- Machine-local layout: a copy of ~/.config/hypr/lua/monitors.local.lua, made by
-- setup:greeter (`desc:` serials are private, so it cannot be tracked here). The
-- greeter user cannot read $HOME, hence a copy rather than a dofile of the
-- original. pcall so a broken copy degrades to the fallback rule, never to a
-- greeter that does not start.
local local_layout = "/etc/greetd/monitors.local.lua"
local f = io.open(local_layout, "r")
if f then
  f:close()
  local ok, err = pcall(dofile, local_layout)
  if not ok then
    print("greeter: ignoring " .. local_layout .. ": " .. tostring(err))
  end
end
MON = MON or {}

hl.config({
  misc = {
    force_default_wallpaper = 0,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },
  animations = { enabled = false },
  ecosystem = {
    no_update_news = true,
    no_donation_nag = true,
  },
})

-- Theme files are written by greeter-theme-sync (wallust CSS + current wallpaper)
-- and seeded with fixed defaults by setup:greeter, so they always exist.
local theme = "/var/lib/greetd-theme"

hl.on("hyprland.start", function()
  hl.exec_cmd("swaybg -m fill -i " .. theme .. "/wallpaper")
  -- ReGreet opens on the focused monitor, so focus MON.main before starting it.
  -- A `monitor = MON.main` window rule and `cursor.default_monitor` both took the
  -- `desc:` string without complaint and put the window on another output anyway
  -- (2026-11-04: it landed on the drawing tablet). The focus dispatcher does
  -- resolve `desc:`, verified live by moving focus DP-3 -> DP-4 with it.
  if MON.main then
    hl.dispatch(hl.dsp.focus({ monitor = MON.main }))
  end
  -- Dispatcher strings are Lua under a Lua config: `hyprctl dispatch exit` is a
  -- parse error that still exits 0, so the greeter would never hand over.
  hl.exec_cmd(
    'sh -c "regreet --config /etc/greetd/regreet.toml --style '
      .. theme
      .. "/regreet.css; hyprctl dispatch 'hl.dsp.exit()'\""
  )
end)
