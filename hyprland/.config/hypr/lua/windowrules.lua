-- Window rules using hl.window_rule() / hl.layer_rule()
-- Reference: https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua

-- `size` and `move` are strict numeric vec2s in the Lua API — unlike hyprland.conf's
-- `windowrule = size 1200 80%`, a percent string here is dropped *silently*: the rule
-- still loads ("ok"), the window just keeps its default geometry. Verified 2026-07-12:
-- size = "1200 80%" -> 800x600 (app default), size = {1200, 1728} -> 1200x1728.
--
-- So resolve percents ourselves, against the smallest attached monitor — a static rule
-- can't know which screen the window will open on, and undersizing is recoverable while
-- overflowing a smaller screen is not.
local function vec2(w, h)
  local mw, mh = math.huge, math.huge
  for _, m in ipairs(hl.get_monitors()) do
    mw, mh = math.min(mw, m.width), math.min(mh, m.height)
  end
  if mw == math.huge then
    mw, mh = 1920, 1080 -- no monitors enumerated yet (early parse)
  end

  local function px(v, total)
    if type(v) == "number" then
      return math.floor(v)
    end
    local pct = tostring(v):match("^%s*(%d+%.?%d*)%%%s*$")
    if pct then
      return math.floor(total * tonumber(pct) / 100)
    end
    return math.floor(tonumber(v) or 0)
  end

  return { px(w, mw), px(h, mh) }
end

-- Suppress maximize events for all windows
hl.window_rule({
  name = "suppress-maximize",
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- Floaters
hl.window_rule({
  name = "floaters",
  match = {
    class = "^(pavucontrol|blueman-manager|nm-connection-editor|qalculate-gtk|Picture-in-Picture|[Ww]logout)$",
  },
  float = true,
})

-- Brave save/open file dialogs
hl.window_rule({
  name = "brave-dialogs",
  match = { title = "^(Save\\sFile|Open\\sFile|All\\sFiles)$" },
  float = true,
})

-- Yazi file manager (Ghostty class app.filemanager)
hl.window_rule({
  name = "yazi",
  match = { class = "^(app.filemanager)$" },
  float = true,
  size = vec2(1400, "80%"),
  rounding = 20,
  dim_around = true,
  xray = true,
})

-- Clipborg (clipboard)
hl.window_rule({
  name = "clipborg",
  match = { class = "^(app.clipborg)$" },
  float = true,
  center = true,
  size = vec2(1200, "80%"),
  opacity = "0.95 0.55 0.55",
  border_size = 2,
  rounding = 20,
  dim_around = true,
  no_blur = true,
  no_dim = true,
  no_screen_share = true,
  xray = true,
})

-- Floating Terminal
hl.window_rule({
  name = "float-terminal",
  match = { class = "^(app.floatterm)$" },
  float = true,
  size = vec2("75%", 350),
  center = true,
})

-- Mullvad VPN
hl.window_rule({
  name = "mullvad",
  match = { class = "^(Mullvad VPN)$" },
  float = true,
  center = true,
  no_initial_focus = true,
})

-- JetBrains Toolbox
hl.window_rule({
  name = "jetbrains-toolbox",
  match = { class = "^(jetbrains-toolbox)$" },
  float = true,
  move = vec2("75%", 100),
  workspace = "1",
  monitor = "1",
})

-- Rofi
hl.window_rule({
  name = "rofi",
  match = { class = ".*(Rofi).*" },
  float = true,
  size = vec2(1400, "80%"),
  rounding = 20,
  dim_around = true,
  xray = true,
})

-- xwaylandvideobridge
hl.window_rule({
  name = "xwayland-video-bridge",
  match = { class = "^(xwaylandvideobridge)$" },
  no_initial_focus = true,
  no_focus = true,
  no_anim = true,
  max_size = "1 1",
  opacity = 0.0,
})

-- Layer rules: Rofi
hl.layer_rule({
  name = "rofi-layer",
  match = { namespace = "^(rofi)$" },
  dim_around = true,
  xray = true,
  blur = true,
  ignore_alpha = 0,
})

-- Layer rules: quickshell notification drawer.
-- The drawer's own surface is deliberately near-transparent (notifications.json
-- drawer.opacity) so it reads as glass rather than a panel; without compositor blur behind
-- it that is just "hard to read". ignore_alpha keeps the blur off the fully clear regions —
-- the drawer window covers the whole output and is transparent outside the slab.
hl.layer_rule({
  name = "quickshell-notification-drawer",
  match = { namespace = "^(quickshell-notification-drawer)$" },
  blur = true,
  ignore_alpha = 0.15,
  xray = true,
})

-- Layer rules: quickshell submap (which-key) hints.
-- Same glass as the drawer, and the same dependency: the slab is drawn at the drawer's
-- opacity, which reads as frosted only with compositor blur behind it. The window spans the
-- bottom of the output and is fully transparent outside the slab, so ignore_alpha keeps the
-- blur off the clear regions. The surface takes no keyboard and has an empty input region.
hl.layer_rule({
  name = "quickshell-submap-hints",
  match = { namespace = "^(quickshell-submap-hints)$" },
  blur = true,
  ignore_alpha = 0.15,
  xray = true,
})

-- Layer rules: SwayNC
hl.layer_rule({
  name = "swaync-notifications",
  match = { namespace = "^(swaync-notification-window)$" },
  xray = true,
})

hl.layer_rule({
  name = "swaync-center",
  match = { namespace = "^(swaync-control-center)$" },
  blur = true,
  ignore_alpha = 0.3,
})
