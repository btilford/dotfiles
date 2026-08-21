-- Key bindings using the real Hyprland Lua API (hl.dsp.*)
-- Every bind carries a { description = ... } so `hyprctl binds` is readable.

-- Applications (single-string format works)
hl.bind("SUPER + o", hl.dsp.submap("open-cmd"), { description = "Open-app submap [open-cmd]" })
hl.define_submap("open-cmd", function()
  hl.bind("b", hl.dsp.exec_cmd("/usr/bin/brave"), { description = "Launch Brave" })
  hl.bind("t", hl.dsp.exec_cmd("/usr/bin/ghostty"), { description = "Launch Ghostty terminal" })
  hl.bind(
    "c",
    hl.dsp.exec_cmd("/usr/bin/speedcrunch"),
    { description = "Launch SpeedCrunch calculator" }
  )
  hl.bind(
    "e",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh emoji"'),
    { description = "Emoji picker (launcher emoji mode)" }
  )
  hl.bind(
    "u",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh glyphs"'),
    { description = "Glyph picker: unicode + nerd font (launcher glyphs mode)" }
  )
  hl.bind(
    "i",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh icons"'),
    { description = "Icon browser (launcher icons mode)" }
  )
  hl.bind(
    "v",
    hl.dsp.exec_cmd(
      'sh -c "qs ipc call clipboard toggle 2>/dev/null || ghostty --class=app.clipborg -e clipborg tui"'
    ),
    { description = "Clipboard history (quickshell dialog)" }
  )

  hl.bind("z", hl.dsp.exec_cmd("missioncenter"), { description = "Launch Mission Center" })
  hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
-- Window management
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close active window" })
hl.bind(
  "SUPER + SHIFT + Q",
  hl.dsp.exec_cmd("sh -c \"hyprctl activewindow | grep pid | tr -d 'pid:' | xargs kill\""),
  { description = "Force-kill active window" }
)
-- System submap. SUPER+S was togglesplit, which window-cmd already carries on `n`
-- -- the top-level bind was a duplicate, so the letter is free for the one submap
-- the set was missing: machine-level operations, none of them window or workspace.
hl.bind("SUPER + S", hl.dsp.submap("system-cmd"), { description = "System submap [system-cmd]" })

-- Blank and re-enable an output. A monitor added mid-session comes up with stale
-- content in its scanout buffer -- a small static patch of garbage that no repaint
-- ever clears, because the compositor only draws where it thinks something
-- changed. Only a modeset replaces the buffer, and DPMS off/on is the cheapest one
-- reachable from a keybind. Diagnosed 2026-08-19 on XREAL glasses hotplugged into
-- a running session; the same artifact had been showing on the tablet for months.
-- lua/monitors.lua does this automatically on hotplug -- this is the manual cure
-- for an output that was already up, or for one the hook missed.
local function dpms_cycle(name)
  hl.dispatch(hl.dsp.dpms("off", name))
  hl.timer(function()
    hl.dispatch(hl.dsp.dpms("on", name))
  end, { timeout = 400, type = "oneshot" })
end

hl.define_submap("system-cmd", function()
  hl.bind("d", function()
    local mon = hl.get_active_monitor()
    if mon then
      dpms_cycle(mon.name)
    end
  end, { description = "DPMS-cycle focused monitor (clear hotplug garbage)" })
  hl.bind("SHIFT + d", function()
    for _, mon in ipairs(hl.get_monitors() or {}) do
      dpms_cycle(mon.name)
    end
  end, { description = "DPMS-cycle every monitor" })
  hl.bind(
    "r",
    hl.dsp.exec_cmd("hyprctl reload"),
    { description = "Reload Hyprland config (resets runtime layout state)" }
  )
  hl.bind(
    "b",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/StartBar.sh"'),
    { description = "Restart status bar (waybar/quickshell)" }
  )
  hl.bind("l", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock session" })
  hl.bind("e", function()
    os.execute("qs ipc call session toggle 2>/dev/null || setsid -f wlogout --protocol layer-shell")
  end, { description = "Session/power menu" })
  hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
local cycle_layouts = { "dwindle", "master", "scrolling" }
local cycle_layout_idx = 1

local function cycle_workspace_layout()
  local ws = hl.get_active_workspace()
  local current = ws and (ws.tiled_layout or ws.layout)
  local found = false

  if current then
    for i = 1, #cycle_layouts do
      if cycle_layouts[i] == current then
        cycle_layout_idx = i
        found = true
        break
      end
    end
  end

  if not found then
    cycle_layout_idx = 1
  end

  cycle_layout_idx = (cycle_layout_idx % #cycle_layouts) + 1
  local next_layout = cycle_layouts[cycle_layout_idx]

  hl.workspace_rule({
    workspace = tostring(ws.id),
    layout = next_layout,
  })
end

hl.bind(
  "SUPER + SHIFT + L",
  cycle_workspace_layout,
  { description = "Cycle workspace layout (dwindle/master/scrolling)" }
)
hl.bind(
  "SUPER + G",
  hl.dsp.exec_cmd("hyprctl dispatch togglegroup"),
  { description = "Toggle window group" }
)

-- Focus movement
hl.bind("SUPER + h", hl.dsp.focus({ direction = "left" }), { description = "Focus window left" })
hl.bind("SUPER + l", hl.dsp.focus({ direction = "right" }), { description = "Focus window right" })
hl.bind("SUPER + k", hl.dsp.focus({ direction = "up" }), { description = "Focus window up" })
hl.bind("SUPER + j", hl.dsp.focus({ direction = "down" }), { description = "Focus window down" })

-- Mouse drag/resize
hl.bind(
  "SUPER + mouse:272",
  hl.dsp.window.drag(),
  { mouse = true, description = "Drag-move window" }
)
hl.bind(
  "SUPER + mouse:273",
  hl.dsp.window.resize(),
  { mouse = true, description = "Drag-resize window" }
)

-- Move active window to workspace
hl.bind(
  "SUPER + ALT + h",
  hl.dsp.window.move({ workspace = -1 }),
  { description = "Move window to previous workspace" }
)
hl.bind(
  "SUPER + ALT + j",
  hl.dsp.window.move({ workspace = 2 }),
  { description = "Move window to workspace 2" }
)
hl.bind(
  "SUPER + ALT + k",
  hl.dsp.window.move({ workspace = 1 }),
  { description = "Move window to workspace 1" }
)
hl.bind(
  "SUPER + ALT + l",
  hl.dsp.window.move({ workspace = "+1" }),
  { description = "Move window to next workspace" }
)

hl.bind(
  "SUPER + d",
  hl.dsp.submap("workspace-cmd"),
  { description = "Workspace submap [workspace-cmd]" }
)
hl.define_submap("workspace-cmd", function()
  hl.bind(
    "TAB",
    hl.dsp.workspace.move({ workspace = "+1", monitor = "current" }),
    { description = "Next workspace (this monitor)" }
  )
  hl.bind(
    "SHIFT + TAB",
    hl.dsp.workspace.move({ workspace = "-1", monitor = "current" }),
    { description = "Previous workspace (this monitor)" }
  )
  hl.bind(
    "CTRL + TAB",
    hl.dsp.window.move({ workspace = "next_per_monitor", follow = true }),
    { description = "Move window to next workspace (follow)" }
  )
  hl.bind(
    "CTRL + SHIFT + TAB",
    hl.dsp.window.move({ workspace = "previous_per_monitor", follow = true }),
    { description = "Move window to previous workspace (follow)" }
  )

  -- Move window to workspace by number
  hl.bind(
    "CTRL + x",
    hl.dsp.window.move({ workspace = "1", follow = true }),
    { description = "Move window to workspace 1 (follow)" }
  )
  hl.bind(
    "CTRL + c",
    hl.dsp.window.move({ workspace = "2", follow = true }),
    { description = "Move window to workspace 2 (follow)" }
  )
  hl.bind(
    "CTRL + v",
    hl.dsp.window.move({ workspace = "3", follow = true }),
    { description = "Move window to workspace 3 (follow)" }
  )
  hl.bind(
    "CTRL + s",
    hl.dsp.window.move({ workspace = "4", follow = true }),
    { description = "Move window to workspace 4 (follow)" }
  )
  hl.bind(
    "CTRL + d",
    hl.dsp.window.move({ workspace = "5", follow = true }),
    { description = "Move window to workspace 5 (follow)" }
  )
  hl.bind(
    "CTRL + f",
    hl.dsp.window.move({ workspace = "6", follow = true }),
    { description = "Move window to workspace 6 (follow)" }
  )
  hl.bind(
    "CTRL + w",
    hl.dsp.window.move({ workspace = "7", follow = true }),
    { description = "Move window to workspace 7 (follow)" }
  )
  hl.bind(
    "CTRL + e",
    hl.dsp.window.move({ workspace = "8", follow = true }),
    { description = "Move window to workspace 8 (follow)" }
  )
  hl.bind(
    "CTRL + r",
    hl.dsp.window.move({ workspace = "9", follow = true }),
    { description = "Move window to workspace 9 (follow)" }
  )
  hl.bind(
    "CTRL + b",
    hl.dsp.window.move({ workspace = "0", follow = true }),
    { description = "Move window to workspace 10 (follow)" }
  )

  -- Focus workspace by number
  hl.bind("1", hl.dsp.focus({ workspace = "1" }), { description = "Focus workspace 1" })
  hl.bind("2", hl.dsp.focus({ workspace = "2" }), { description = "Focus workspace 2" })
  hl.bind("3", hl.dsp.focus({ workspace = "3" }), { description = "Focus workspace 3" })
  hl.bind("4", hl.dsp.focus({ workspace = "4" }), { description = "Focus workspace 4" })
  hl.bind("5", hl.dsp.focus({ workspace = "5" }), { description = "Focus workspace 5" })
  hl.bind("6", hl.dsp.focus({ workspace = "6" }), { description = "Focus workspace 6" })
  hl.bind("7", hl.dsp.focus({ workspace = "7" }), { description = "Focus workspace 7" })
  hl.bind("8", hl.dsp.focus({ workspace = "8" }), { description = "Focus workspace 8" })
  hl.bind("9", hl.dsp.focus({ workspace = "9" }), { description = "Focus workspace 9" })
  hl.bind("0", hl.dsp.focus({ workspace = "10" }), { description = "Focus workspace 10" })
  hl.bind("l", cycle_workspace_layout, { description = "Cycle workspace layout" })

  -- Desktop appearance
  -- backend dispatch: quickshell launcher wallpaper mode, or rofi WallpaperSelect.sh
  hl.bind(
    "w",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh wallpaper"'),
    { description = "Wallpaper chooser" }
  )
  hl.bind(
    "SHIFT + w",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/WallpaperRandom.sh"'),
    { description = "Random wallpaper" }
  )
  hl.bind(
    "t",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/ThemeChanger.sh"'),
    { description = "Theme chooser" }
  )

  hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
hl.bind("SUPER + w", hl.dsp.submap("window-cmd"), { description = "Window submap [window-cmd]" })
hl.define_submap("window-cmd", function()
  -- hl.bind("SHIFT + h", hl.dsp.resize({ x = 10, y = 0, relative = true }), { repeating = true })
  hl.bind("TAB", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
  end, { description = "Cycle to next window (raise)" })

  hl.bind("n", hl.dsp.layout("togglesplit"), { description = "Toggle split direction" })
  hl.bind("SUPER + l", hl.dsp.layout("dwindle"), { description = "Set dwindle layout" })
  hl.bind("r", function()
    local ws = hl.get_active_workspace()
    if ws then
      if ws.tiled_layout == "master" then
        hl.dispatch(hl.dsp.layout("orientationnext"))
      elseif ws.tiled_layout == "dwindle" then
        hl.dispatch(hl.dsp.layout("togglesplit"))
      end
    end
  end, { description = "Rotate layout (master orientation / dwindle split)" })
  hl.bind("SHIFT + r", function()
    local ws = hl.get_active_workspace()
    if ws and ws.tiled_layout == "master" then
      hl.dispatch(hl.dsp.layout("orientationprev"))
    end
  end, { description = "Rotate master orientation backward" })
  hl.bind("comma", function()
    local ws = hl.get_active_workspace()
    if ws then
      if ws.tiled_layout == "master" then
        hl.dispatch(hl.dsp.layout("swapwithmaster"))
      elseif ws.tiled_layout == "dwindle" then
        hl.dispatch(hl.dsp.layout("swapsplit"))
      end
    end
  end, { description = "Swap with master / swap split" })
  hl.bind("period", function()
    local ws = hl.get_active_workspace()
    if ws and ws.tiled_layout == "master" then
      hl.dispatch(hl.dsp.layout("rollnext"))
    end
  end, { description = "Roll windows forward (master)" })

  hl.bind("q", hl.dsp.window.close(), { description = "Close active window" })
  hl.bind("c", hl.dsp.window.center(), { description = "Center window" })
  hl.bind("f", hl.dsp.window.fullscreen(), { description = "Toggle fullscreen" })
  hl.bind(
    "m",
    hl.dsp.window.fullscreen({ mode = "maximized" }),
    { description = "Maximize window" }
  )
  hl.bind("t", hl.dsp.window.float(), { description = "Toggle floating" })

  hl.bind("s", hl.dsp.submap("window-swap"), { description = "Window-swap submap [window-swap]" })
  hl.define_submap("window-swap", function()
    hl.bind("h", hl.dsp.window.swap({ direction = "left" }), { description = "Swap window left" })
    hl.bind("j", hl.dsp.window.swap({ direction = "down" }), { description = "Swap window down" })
    hl.bind("k", hl.dsp.window.swap({ direction = "up" }), { description = "Swap window up" })
    hl.bind("l", hl.dsp.window.swap({ direction = "right" }), { description = "Swap window right" })
    hl.bind("escape", hl.dsp.submap("window-cmd"), { description = "Back to window submap" })
  end)
  -- hl.bind("SHIFT + t", hl.dsp.float())
  -- hl.bind("SHIFT + t", hl.dsp.float())
  -- hl.bind("b", focus browser)
  -- hl.bind("b", focus browser)
  -- hl.bind("g", focus terminal)
  -- hl.bind("g", focus terminal)

  hl.bind(
    "CTRL + h",
    hl.dsp.window.move({ direction = "left" }),
    { description = "Move window left" }
  )
  hl.bind(
    "CTRL + j",
    hl.dsp.window.move({ direction = "down" }),
    { description = "Move window down" }
  )
  hl.bind("CTRL + k", hl.dsp.window.move({ direction = "up" }), { description = "Move window up" })
  hl.bind(
    "CTRL + l",
    hl.dsp.window.move({ direction = "right" }),
    { description = "Move window right" }
  )

  hl.bind(
    "ALT + h",
    hl.dsp.window.move({ x = -10, y = 0, relative = true }),
    { description = "Nudge window left" }
  )
  hl.bind(
    "ALT + j",
    hl.dsp.window.move({ x = 0, y = 10, relative = true }),
    { description = "Nudge window down" }
  )
  hl.bind(
    "ALT + k",
    hl.dsp.window.move({ x = 10, y = -10, relative = true }),
    { description = "Nudge window up-right" }
  )
  hl.bind(
    "ALT + l",
    hl.dsp.window.move({ x = 10, y = 0, relative = true }),
    { description = "Nudge window right" }
  )

  hl.bind(
    "SHIFT + h",
    hl.dsp.window.resize({ x = -10, y = 0, relative = true }),
    { description = "Shrink window width" }
  )
  hl.bind(
    "SHIFT + j",
    hl.dsp.window.resize({ x = 0, y = 10, relative = true }),
    { description = "Grow window height" }
  )
  hl.bind(
    "SHIFT + k",
    hl.dsp.window.resize({ x = 0, y = -10, relative = true }),
    { description = "Shrink window height" }
  )
  hl.bind(
    "SHIFT + l",
    hl.dsp.window.resize({ x = 10, y = 0, relative = true }),
    { description = "Grow window width" }
  )

  hl.bind(
    "CTRL + SHIFT + h",
    hl.dsp.window.resize({ x = -100, y = 0, relative = true }),
    { description = "Shrink window width (large)" }
  )
  hl.bind(
    "CTRL + SHIFT + j",
    hl.dsp.window.resize({ x = 0, y = 100, relative = true }),
    { description = "Grow window height (large)" }
  )
  hl.bind(
    "CTRL + SHIFT + k",
    hl.dsp.window.resize({ x = 0, y = -100, relative = true }),
    { description = "Shrink window height (large)" }
  )
  hl.bind(
    "CTRL + SHIFT + l",
    hl.dsp.window.resize({ x = 100, y = 0, relative = true }),
    { description = "Grow window width (large)" }
  )

  -- Focus movement within submap
  hl.bind("h", hl.dsp.focus({ direction = "left" }), { description = "Focus window left" })
  hl.bind("j", hl.dsp.focus({ direction = "down" }), { description = "Focus window down" })
  hl.bind("k", hl.dsp.focus({ direction = "up" }), { description = "Focus window up" })
  hl.bind("l", hl.dsp.focus({ direction = "right" }), { description = "Focus window right" })
  --
  -- Use `reset` to go back to the global submap
  hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

-- focus submap for focusing specific applications
hl.bind("SUPER + f", hl.dsp.submap("focus-cmd"), { description = "Focus-app submap [focus-cmd]" })

hl.define_submap("focus-cmd", function()
  -- Focus terminal (ghostty)
  hl.bind("t", function()
    hl.dispatch(hl.dsp.focus({ window = "class:com.mitchellh.ghostty" }))
  end, { description = "Focus Ghostty terminal" })
  hl.bind("b", function()
    hl.dispatch(hl.dsp.focus({ window = "class:brave-browser" }))
  end, { description = "Focus Brave browser" })
  hl.bind("l", hl.dsp.focus({ last = true }), { description = "Focus last window" })

  -- Exit submap
  hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

-- Actions
-- Launcher/bar dispatch by $HYPR_LAUNCHER / $HYPR_BAR (see hypr/scripts/shell-env.sh).
hl.bind(
  "SUPER + CTRL + RETURN",
  hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh"'),
  { description = "App launcher (rofi/quickshell)" }
)
hl.bind(
  "SUPER + r",
  hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh"'),
  { description = "App launcher (rofi/quickshell)" }
)
hl.bind(
  "SUPER + SHIFT + B",
  hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/StartBar.sh"'),
  { description = "Restart status bar (waybar/quickshell)" }
)
-- Escape hatch: full config reload. Resets runtime workspace/layout state;
-- theme colors normally arrive via scripts/ApplyHyprColors.sh without this.
hl.bind(
  "SUPER + SHIFT + R",
  hl.dsp.exec_cmd("hyprctl reload"),
  { description = "Reload Hyprland config (resets runtime layout state)" }
)
hl.bind("SUPER + Escape", function()
  -- quickshell session dialog; fall back to wlogout if the qs daemon isn't running
  os.execute("qs ipc call session toggle 2>/dev/null || setsid -f wlogout --protocol layer-shell")
end, { description = "Session/power menu" })
hl.bind("SUPER + slash", function()
  os.execute("qs ipc call keymap toggle 2>/dev/null")
end, { description = "Keymap cheatsheet overlay", submap_universal = true })
-- Notifications submap. One entry point for every notification verb, which keeps the top-level
-- namespace free — and the KeymapOverlay picks it up as its own tree node from the "[notif-cmd]"
-- description tag, so the map documents itself.
--
-- LOAD-BEARING: any verb that hands the keyboard to quickshell (the drawer and focus mode both
-- take an EXCLUSIVE layer-shell grab) must leave the submap FIRST. A submap is a Hyprland-side
-- mode, and an exclusive surface swallows every key before Hyprland sees it — so the submap
-- would stay active with no way to press its own escape: an invisible mode the user is stuck in
-- until that surface closes. Reset, then run.
local function notif_run(cmd)
  hl.dispatch(hl.dsp.submap("reset"))
  os.execute(cmd)
end

hl.bind(
  "SUPER + n",
  hl.dsp.submap("notif-cmd"),
  { description = "Notifications submap [notif-cmd]" }
)
hl.define_submap("notif-cmd", function()
  hl.bind("d", function()
    -- searchable history drawer; also opens from the bar bell
    notif_run("qs ipc call notifications drawer 2>/dev/null || swaync-client -t 2>/dev/null")
  end, { description = "Notification history drawer" })

  hl.bind("f", function()
    -- focus the popup stack itself: j/k move, d dismisses, Esc releases. Popups never grab the
    -- keyboard on their own, so this is the only way in.
    notif_run("qs ipc call notifications focus 2>/dev/null")
  end, { description = "Focus the notification stack (keyboard control)" })

  hl.bind("x", function()
    -- falls back to swaync while it is still the server on hosts without HYPR_NOTIFY=quickshell
    notif_run("qs ipc call notifications dismissAll 2>/dev/null || swaync-client -C 2>/dev/null")
  end, { description = "Dismiss everything on screen" })

  hl.bind("r", function()
    notif_run("qs ipc call notifications markRead 2>/dev/null")
  end, { description = "Mark all read (clear the bell count)" })

  hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

-- Kept outside the submap: the drawer is the verb reached most often, and dismiss-all is a panic
-- key that should never need two presses.
hl.bind("SUPER + i", function()
  os.execute("qs ipc call notifications drawer 2>/dev/null || swaync-client -t 2>/dev/null")
end, { description = "Notification history drawer" })
hl.bind("SUPER + SHIFT + N", function()
  os.execute("qs ipc call notifications dismissAll 2>/dev/null || swaync-client -C 2>/dev/null")
end, { description = "Dismiss all notifications" })
-- Clock drawer: weather, world clocks, calendar. The bar clock opens the same surface.
--
-- Routed through notif_run despite not being a notification verb: that helper resets the submap
-- BEFORE running, and the reason (the LOAD-BEARING comment above it) is about the keyboard, not
-- about notifications. This drawer takes the same EXCLUSIVE layer-shell grab, so pressing this
-- from inside a submap would leave that submap active with an exclusive surface swallowing every
-- key — including its own escape. The name is now narrower than what it does; renaming it is a
-- change of its own, not a rider on this one.
hl.bind("SUPER + c", function()
  notif_run("qs ipc call clock drawer 2>/dev/null")
end, { description = "Clock drawer (weather, world clocks, calendar)" })

-- Copy a formatted timestamp to the clipboard. The format table lives in
-- scripts/CopyDateTime.sh, which takes a format NAME — these binds never carry a raw
-- date(1) format string, so a format is defined once instead of in eleven places.
--
-- Every verb resets the submap before running, for a different reason than notif_run's:
-- nothing here grabs the keyboard, these are simply actions rather than a mode, and
-- staying in the submap after a copy means the next keystroke is swallowed. Same shape,
-- different why — which is why this is its own helper and not a call to notif_run.
--
-- exec_cmd, NEVER os.execute. `os.execute` blocks Hyprland's main thread until the child
-- exits, and this child owns the Wayland clipboard, so it does not exit — the first press
-- of a time-cmd verb froze the whole desktop for half an hour until the wl-copy process
-- was killed by hand. The script now detaches wl-copy as well; this is the second half of
-- that fix, and the more important half, because it holds for ANY command bound here.
--
-- The os.execute calls elsewhere in this file are safe only because every one of them is
-- a `qs ipc call` that returns immediately. That is a property of those commands, not of
-- os.execute — do not read them as precedent.
local function time_run(fmt)
  hl.dispatch(hl.dsp.submap("reset"))
  hl.dispatch(hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/CopyDateTime.sh ' .. fmt .. '"'))
end

hl.bind(
  "SUPER + t",
  hl.dsp.submap("time-cmd"),
  { description = "Copy date/time submap [time-cmd]" }
)
hl.define_submap("time-cmd", function()
  -- lowercase local, SHIFT UTC
  hl.bind("d", function()
    time_run("date")
  end, { description = "Copy date (2026-08-19)" })
  hl.bind("SHIFT + d", function()
    time_run("date-utc")
  end, { description = "Copy date, UTC" })
  hl.bind("t", function()
    time_run("time")
  end, { description = "Copy time (14:03:11)" })
  hl.bind("SHIFT + t", function()
    time_run("time-utc")
  end, { description = "Copy time, UTC" })
  hl.bind("b", function()
    time_run("datetime")
  end, { description = "Copy date + time" })
  hl.bind("SHIFT + b", function()
    time_run("datetime-utc")
  end, { description = "Copy date + time, UTC" })
  hl.bind("i", function()
    time_run("iso")
  end, { description = "Copy ISO 8601 with offset" })
  hl.bind("SHIFT + i", function()
    time_run("iso-utc")
  end, { description = "Copy ISO 8601, UTC (Z suffix)" })

  -- No UTC variants below: all three are local by definition.
  hl.bind("s", function()
    time_run("stamp")
  end, { description = "Copy Operon frontmatter stamp" })
  hl.bind("e", function()
    time_run("epoch")
  end, { description = "Copy Unix epoch seconds" })
  hl.bind("n", function()
    time_run("daily")
  end, { description = "Copy daily-note name (Aug-19-Wed)" })

  hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
-- Timers submap. Pure wiring over the `timers` IpcHandler in shell.qml (start/alarm/pomodoro/
-- stopwatch/list) -- no quickshell code here, that surface is done and stable.
--
-- Reset-before-run, same as notif_run and time_run, but for a third reason: nothing bound here
-- takes an EXCLUSIVE layer-shell grab (unlike notif_run's drawer/focus verbs), and every verb is
-- a `qs ipc call` that returns immediately (unlike time_run's wl-copy child), so plain os.execute
-- is safe. The reset still has to happen first -- staying in the submap after a start/toggle
-- swallows the next keystroke, same as time_run's reason.
--
-- Verbs that take an `id` (pause/resume/toggle/reset/cancel/extend) are not bindable to a bare
-- key -- a key press cannot supply an id -- so they are left to the card UI and not wired here.
local function timer_run(cmd)
  hl.dispatch(hl.dsp.submap("reset"))
  os.execute(cmd)
end

hl.bind("SUPER + m", hl.dsp.submap("timer-cmd"), { description = "Timer submap [timer-cmd]" })
hl.define_submap("timer-cmd", function()
  -- Fixed presets, not a prompt -- a prompt is new UI and this task is wiring only.
  hl.bind("1", function()
    timer_run('qs ipc call timers start 5m "" 2>/dev/null')
  end, { description = "Start 5m timer" })
  hl.bind("2", function()
    timer_run('qs ipc call timers start 10m "" 2>/dev/null')
  end, { description = "Start 10m timer" })
  hl.bind("3", function()
    timer_run('qs ipc call timers start 15m "" 2>/dev/null')
  end, { description = "Start 15m timer" })
  hl.bind("4", function()
    timer_run('qs ipc call timers start 25m "" 2>/dev/null')
  end, { description = "Start 25m timer" })
  hl.bind("5", function()
    timer_run('qs ipc call timers start 45m "" 2>/dev/null')
  end, { description = "Start 45m timer" })
  hl.bind("6", function()
    timer_run('qs ipc call timers start 60m "" 2>/dev/null')
  end, { description = "Start 60m timer" })

  hl.bind("p", function()
    -- empty spec -> NotifyConfig.timers defaults (25m/5m/15m x4)
    timer_run('qs ipc call timers pomodoro "" "" 2>/dev/null')
  end, { description = "Start pomodoro (default cycle)" })

  hl.bind("w", function()
    timer_run('qs ipc call timers stopwatch "" 2>/dev/null')
  end, { description = "Toggle stopwatch (start/pause)" })
  hl.bind("SHIFT + w", function()
    timer_run("qs ipc call timers lap 2>/dev/null")
  end, { description = "Stopwatch lap" })
  hl.bind("s", function()
    timer_run("qs ipc call timers stop 2>/dev/null")
  end, { description = "Stop stopwatch" })

  hl.bind("c", function()
    timer_run("qs ipc call timers cancelAll 2>/dev/null")
  end, { description = "Cancel all timers" })
  hl.bind("i", function()
    timer_run('notify-send Timers "$(qs ipc call timers list 2>/dev/null)"')
  end, { description = "List active timers" })

  hl.bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

hl.bind(
  "CTRL + ALT + L",
  hl.dsp.exec_cmd("loginctl lock-session"),
  { description = "Lock session" }
)

-- Workspace switching
hl.bind("SUPER + 1", hl.dsp.focus({ workspace = 1 }), { description = "Focus workspace 1" })
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = 2 }), { description = "Focus workspace 2" })
hl.bind("SUPER + 3", hl.dsp.focus({ workspace = 3 }), { description = "Focus workspace 3" })
hl.bind("SUPER + 4", hl.dsp.focus({ workspace = 4 }), { description = "Focus workspace 4" })
hl.bind("SUPER + 5", hl.dsp.focus({ workspace = 5 }), { description = "Focus workspace 5" })
hl.bind("SUPER + 6", hl.dsp.focus({ workspace = 6 }), { description = "Focus workspace 6" })
hl.bind("SUPER + 7", hl.dsp.focus({ workspace = 7 }), { description = "Focus workspace 7" })
hl.bind("SUPER + 8", hl.dsp.focus({ workspace = 8 }), { description = "Focus workspace 8" })
hl.bind("SUPER + 9", hl.dsp.focus({ workspace = 9 }), { description = "Focus workspace 9" })
hl.bind("SUPER + 0", hl.dsp.focus({ workspace = 10 }), { description = "Focus workspace 10" })

-- AR glasses (XREAL) workspaces. F-keys rather than more digits: 1-0 are spoken
-- for, and these three only exist while the glasses are plugged in.
hl.bind("SUPER + F1", hl.dsp.focus({ workspace = 11 }), { description = "Focus XR1 (ws 11)" })
hl.bind("SUPER + F2", hl.dsp.focus({ workspace = 12 }), { description = "Focus XR2 (ws 12)" })
hl.bind("SUPER + F3", hl.dsp.focus({ workspace = 13 }), { description = "Focus XR3 (ws 13)" })
hl.bind(
  "SUPER + SHIFT + F1",
  hl.dsp.window.move({ workspace = 11 }),
  { description = "Move window to XR1 (ws 11)" }
)
hl.bind(
  "SUPER + SHIFT + F2",
  hl.dsp.window.move({ workspace = 12 }),
  { description = "Move window to XR2 (ws 12)" }
)
hl.bind(
  "SUPER + SHIFT + F3",
  hl.dsp.window.move({ workspace = 13 }),
  { description = "Move window to XR3 (ws 13)" }
)

-- Move window to workspace
hl.bind(
  "SUPER + ALT + x",
  hl.dsp.window.move({ workspace = 1 }),
  { description = "Move window to workspace 1" }
)
hl.bind(
  "SUPER + ALT + c",
  hl.dsp.window.move({ workspace = 2 }),
  { description = "Move window to workspace 2" }
)
hl.bind(
  "SUPER + ALT + v",
  hl.dsp.window.move({ workspace = 3 }),
  { description = "Move window to workspace 3" }
)
hl.bind(
  "SUPER + ALT + s",
  hl.dsp.window.move({ workspace = 4 }),
  { description = "Move window to workspace 4" }
)
hl.bind(
  "SUPER + ALT + d",
  hl.dsp.window.move({ workspace = 5 }),
  { description = "Move window to workspace 5" }
)
hl.bind(
  "SUPER + ALT + f",
  hl.dsp.window.move({ workspace = 6 }),
  { description = "Move window to workspace 6" }
)
hl.bind(
  "SUPER + ALT + w",
  hl.dsp.window.move({ workspace = 7 }),
  { description = "Move window to workspace 7" }
)
hl.bind(
  "SUPER + ALT + e",
  hl.dsp.window.move({ workspace = 8 }),
  { description = "Move window to workspace 8" }
)
hl.bind(
  "SUPER + ALT + r",
  hl.dsp.window.move({ workspace = 9 }),
  { description = "Move window to workspace 9" }
)
hl.bind(
  "SUPER + ALT + b",
  hl.dsp.window.move({ workspace = 10 }),
  { description = "Move window to workspace 10" }
)

-- Workspace cycling
hl.bind(
  "SUPER + Tab",
  hl.dsp.focus({ workspace = "m+1" }),
  { description = "Next workspace on monitor" }
)
hl.bind(
  "SUPER + SHIFT + Tab",
  hl.dsp.focus({ workspace = "m-1" }),
  { description = "Previous workspace on monitor" }
)
hl.bind(
  "SUPER + mouse_down",
  hl.dsp.focus({ workspace = "e+1" }),
  { description = "Next workspace (scroll)" }
)
hl.bind(
  "SUPER + mouse_up",
  hl.dsp.focus({ workspace = "e-1" }),
  { description = "Previous workspace (scroll)" }
)
hl.bind(
  "SUPER + CTRL + down",
  hl.dsp.focus({ workspace = "empty" }),
  { description = "Focus first empty workspace" }
)

-- Media keys (no modifier)
hl.bind(
  "XF86MonBrightnessUp",
  hl.dsp.exec_cmd("brightnessctl -q s +10%"),
  { locked = true, repeating = true, description = "Brightness +10%" }
)
hl.bind(
  "XF86MonBrightnessDown",
  hl.dsp.exec_cmd("brightnessctl -q s 10%-"),
  { locked = true, repeating = true, description = "Brightness -10%" }
)
hl.bind(
  "XF86AudioRaiseVolume",
  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"),
  { locked = true, repeating = true, description = "Volume +5%" }
)
hl.bind(
  "XF86AudioLowerVolume",
  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"),
  { locked = true, repeating = true, description = "Volume -5%" }
)
hl.bind(
  "XF86AudioMute",
  hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
  { locked = true, description = "Toggle mute" }
)
hl.bind(
  "XF86AudioPlay",
  hl.dsp.exec_cmd("playerctl play-pause"),
  { locked = true, description = "Play/pause media" }
)
hl.bind(
  "XF86AudioPause",
  hl.dsp.exec_cmd("playerctl pause"),
  { locked = true, description = "Pause media" }
)
hl.bind(
  "XF86AudioNext",
  hl.dsp.exec_cmd("playerctl next"),
  { locked = true, description = "Next track" }
)
hl.bind(
  "XF86AudioPrev",
  hl.dsp.exec_cmd("playerctl previous"),
  { locked = true, description = "Previous track" }
)
hl.bind(
  "XF86AudioMicMute",
  hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"),
  { locked = true, description = "Toggle mic mute" }
)

-- Keyboard backlight
hl.bind(
  "code:238",
  hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s +10"),
  { description = "Keyboard backlight +" }
)
hl.bind(
  "code:237",
  hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s 10-"),
  { description = "Keyboard backlight -" }
)

-- Clipboard and file manager
-- Standalone quickshell ClipboardDialog (clipborg). Launcher's clip mode is gone.
-- Falls back to the clipborg TUI when there's no qs daemon (e.g. a rofi-backend
-- host), which is what the old Launcher.sh clip branch used to provide.
-- SUPER+Y rather than SUPER+V: `y` is yank, which is the verb this actually is, and it
-- keeps V free for a paste-side counterpart later. Moved 2026-08-19 alongside the
-- SUPER+T time submap below.
hl.bind(
  "SUPER + Y",
  hl.dsp.exec_cmd(
    'sh -c "qs ipc call clipboard toggle 2>/dev/null || ghostty --class=app.clipborg -e clipborg tui"'
  ),
  { description = "Clipboard history (quickshell dialog)" }
)
hl.bind(
  "SUPER + E",
  hl.dsp.exec_cmd(
    "ghostty --class=app.filemanager --window-padding-x=10,10 --confirm-close-surface=false -e yazi"
  ),
  { description = "File manager (yazi)" }
)
