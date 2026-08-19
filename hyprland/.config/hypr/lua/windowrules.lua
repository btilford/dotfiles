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
--
-- xray = false, matching the submap hints. xray makes the blur sample the WALLPAPER and ignore
-- every window in between, so on a saturated wallpaper the "frosted glass" is frosted
-- wallpaper and the slab takes that hue regardless of what is actually underneath it. It also
-- cuts a hole through the app you are reading and replaces it with unrelated scenery.
hl.layer_rule({
  name = "quickshell-notification-drawer",
  match = { namespace = "^(quickshell-notification-drawer)$" },
  blur = true,
  ignore_alpha = 0.15,
  xray = false,
})

-- Layer rules: quickshell clock drawer (weather, world clocks, calendar).
--
-- Its own namespace and its own rule rather than a shared one with the notification drawer:
-- a layer rule matches a namespace, and the two surfaces are separate windows with separate
-- lifetimes. The values match the notification drawer deliberately, so the two drawers read as
-- the same material — but they are stated here, so tuning one can never silently restyle the
-- other (which is exactly what happened when the submap hints borrowed the drawer's opacity).
--
-- Same two traps as the rules above: ignore_alpha (0.15) sits ABOVE the slab's own alpha (0.05,
-- ClockDrawer.slabOpacity), so the compositor skips blurring the slab itself and only the cards,
-- shimmer and text sit over a sharp background — a chosen look. And xray = false, because xray
-- makes the blur sample the WALLPAPER and ignore every window in between, which turns "frosted
-- glass" into frosted wallpaper and cuts a hole through whatever you were reading.
hl.layer_rule({
  name = "quickshell-clock-drawer",
  match = { namespace = "^(quickshell-clock-drawer)$" },
  blur = true,
  ignore_alpha = 0.15,
  xray = false,
})

-- Layer rules: quickshell submap (which-key) hints.
-- The slab is drawn at the drawer's opacity, which reads as frosted only with compositor
-- blur behind it. The window spans the bottom of the output and is fully transparent outside
-- the slab, so ignore_alpha keeps the blur off the clear regions. The surface takes no
-- keyboard and has an empty input region.
--
-- xray = FALSE here, unlike the drawer. xray makes the blur sample the WALLPAPER and ignore
-- the windows in between — so on a saturated wallpaper (the current one is an orange sunset)
-- the "frosted glass" is frosted *wallpaper*, and the slab reads as a brown wash no matter
-- what is actually underneath it. That is what made this overlay look brown rather than
-- glassy; opacity was never the cause.
--
-- It is also the wrong behaviour for THIS surface specifically. The hints appear over the
-- window you are working in, for a second, while you decide a key — blurring that window is
-- the feedback you want. Cutting a hole through it to the desktop replaces the context you
-- are mid-thought about with unrelated scenery.
--
-- ignore_alpha (0.15) is deliberately ABOVE the slab's own alpha (0.05, Shell.qml
-- submapHintsOpacity), which means the compositor skips blurring the slab itself and only the
-- shimmer/elevation/text — the parts above the threshold — sit over a sharp background.
--
-- That is a chosen look, not an oversight, and it was measured rather than assumed: dropping
-- ignore_alpha to 0.02 puts it below the slab alpha, full blur applies, and in-slab detail
-- variance falls from 0.064 to 0.042 with the background outside the slab identical to seven
-- decimal places. Both were compared side by side; the sharper one reads better here, and it
-- is also what makes the shimmer legible as a sweep rather than a haze.
--
-- The trap to remember if either number is ever touched: **blur silently does not apply when
-- ignore_alpha exceeds the surface's alpha.** Nothing warns, and an unblurred glass surface
-- looks like a design mistake rather than a missing effect. Raising submapHintsOpacity back
-- above 0.15 will switch full blur on again and change the look without either value moving.
hl.layer_rule({
  name = "quickshell-submap-hints",
  match = { namespace = "^(quickshell-submap-hints)$" },
  blur = true,
  ignore_alpha = 0.15,
  xray = false,
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
