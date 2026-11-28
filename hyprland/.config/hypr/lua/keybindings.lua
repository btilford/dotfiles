-- Key bindings using the real Hyprland Lua API (hl.dsp.*)
-- Every bind carries a { description = ... } so `hyprctl binds` is readable.
--
-- Optional `group = "..."`: the box the bind is drawn in on that overlay,
-- carried as "<group>" the same way. Groups appear in definition order.
--
-- Optional `hint = "..."`: a short label for the which-key overlay
-- (quickshell SubmapHints), whose fixed-width cells fit about 20 characters.
-- Hyprland stores nothing but the description string, so the hint rides inside
-- it as "{hint}" -- placed before any trailing "[submap]" tag, which
-- config/Keymap.qml matches with an end anchor. Keymap.action() strips the
-- braces for the full-width cheatsheet; Keymap.hint() returns them for the
-- overlay. Keep the two parsers in step.
-- A local wrapper, not an override: `hl` is the compositor's and .luacheckrc
-- declares it read-only, so every bind in this file calls bind() instead.
local function bind(keys, action, opts)
  if type(opts) == "table" and (opts.hint or opts.group) then
    local o = {}
    for k, v in pairs(opts) do
      if k ~= "hint" and k ~= "group" then
        o[k] = v
      end
    end
    local d = o.description or ""
    local body, tag = d:match("^(.-)%s*(%[[^%]]+%])$")
    body = body or d
    if opts.hint then
      body = body .. " {" .. opts.hint .. "}"
    end
    if opts.group then
      body = body .. " <" .. opts.group .. ">"
    end
    o.description = tag and (body .. " " .. tag) or body
    opts = o
  end
  return hl.bind(keys, action, opts)
end

-- Applications (single-string format works)
bind("SUPER + o", hl.dsp.submap("open-cmd"), { description = "Open-app submap [open-cmd]" })
hl.define_submap("open-cmd", function()
  bind("b", hl.dsp.exec_cmd("/usr/bin/brave"), { description = "Launch Brave", group = "Apps" })
  bind(
    "t",
    hl.dsp.exec_cmd("/usr/bin/ghostty"),
    { description = "Launch Ghostty terminal", hint = "Ghostty", group = "Apps" }
  )
  bind(
    "c",
    hl.dsp.exec_cmd("/usr/bin/speedcrunch"),
    { description = "Launch SpeedCrunch calculator", hint = "SpeedCrunch", group = "Apps" }
  )
  bind(
    "e",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh emoji"'),
    { description = "Emoji picker (launcher emoji mode)", hint = "Emoji", group = "Pickers" }
  )
  bind("u", hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh glyphs"'), {
    description = "Glyph picker: unicode + nerd font (launcher glyphs mode)",
    hint = "Glyphs",
    group = "Pickers",
  })
  bind(
    "i",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh icons"'),
    { description = "Icon browser (launcher icons mode)", hint = "Icons", group = "Pickers" }
  )
  bind(
    "v",
    hl.dsp.exec_cmd(
      'sh -c "qs ipc call clipboard toggle 2>/dev/null || ghostty --class=app.clipborg -e clipborg tui"'
    ),
    { description = "Clipboard history (quickshell dialog)", hint = "Clipboard", group = "Pickers" }
  )

  bind(
    "z",
    hl.dsp.exec_cmd("missioncenter"),
    { description = "Launch Mission Center", hint = "Mission Center", group = "Apps" }
  )
  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
-- Window management
bind("SUPER + Q", hl.dsp.window.close(), { description = "Close active window" })
bind(
  "SUPER + SHIFT + Q",
  hl.dsp.exec_cmd("sh -c \"hyprctl activewindow | grep pid | tr -d 'pid:' | xargs kill\""),
  { description = "Force-kill active window" }
)
-- System submap. SUPER+S was togglesplit, which window-cmd already carries on `n`
-- -- the top-level bind was a duplicate, so the letter is free for the one submap
-- the set was missing: machine-level operations, none of them window or workspace.
bind("SUPER + S", hl.dsp.submap("system-cmd"), { description = "System submap [system-cmd]" })

-- Blank and re-enable an output. A monitor added mid-session comes up with stale
-- content in its scanout buffer -- a small static patch of garbage that no repaint
-- ever clears, because the compositor only draws where it thinks something
-- changed. Only a modeset replaces the buffer, and DPMS off/on is the cheapest one
-- reachable from a keybind. Diagnosed 2026-08-19 on XREAL glasses hotplugged into
-- a running session; the same artifact had been showing on the tablet for months.
-- lua/monitors.lua does this automatically on hotplug -- this is the manual cure
-- for an output that was already up, or for one the hook missed.
local function dpms_cycle(name)
  hl.dispatch(hl.dsp.dpms({ action = "off", monitor = name }))
  hl.timer(function()
    hl.dispatch(hl.dsp.dpms({ action = "on", monitor = name }))
  end, { timeout = 400, type = "oneshot" })
end

hl.define_submap("system-cmd", function()
  bind("d", function()
    local mon = hl.get_active_monitor()
    if mon then
      dpms_cycle(mon.name)
    end
  end, {
    description = "DPMS-cycle focused monitor (clear hotplug garbage)",
    hint = "DPMS cycle this",
    group = "Display",
  })
  bind("SHIFT + d", function()
    for _, mon in ipairs(hl.get_monitors() or {}) do
      dpms_cycle(mon.name)
    end
  end, { description = "DPMS-cycle every monitor", hint = "DPMS cycle all", group = "Display" })
  bind("r", hl.dsp.exec_cmd("hyprctl reload"), {
    description = "Reload Hyprland config (resets runtime layout state)",
    hint = "Reload config",
    group = "Shell",
  })
  bind("b", hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/StartBar.sh"'), {
    description = "Restart status bar (waybar/quickshell)",
    hint = "Restart bar",
    group = "Shell",
  })
  bind(
    "l",
    hl.dsp.exec_cmd("loginctl lock-session"),
    { description = "Lock session", group = "Session" }
  )
  bind("e", function()
    os.execute("qs ipc call session toggle 2>/dev/null || setsid -f wlogout --protocol layer-shell")
  end, { description = "Session/power menu", group = "Session" })
  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
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

bind(
  "SUPER + SHIFT + L",
  cycle_workspace_layout,
  { description = "Cycle workspace layout (dwindle/master/scrolling)" }
)
bind(
  "SUPER + G",
  hl.dsp.exec_cmd("hyprctl dispatch togglegroup"),
  { description = "Toggle window group" }
)

-- Focus movement
bind("SUPER + h", hl.dsp.focus({ direction = "left" }), { description = "Focus window left" })
bind("SUPER + l", hl.dsp.focus({ direction = "right" }), { description = "Focus window right" })
bind("SUPER + k", hl.dsp.focus({ direction = "up" }), { description = "Focus window up" })
bind("SUPER + j", hl.dsp.focus({ direction = "down" }), { description = "Focus window down" })

-- Mouse drag/resize
bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Drag-move window" })
bind(
  "SUPER + mouse:273",
  hl.dsp.window.resize(),
  { mouse = true, description = "Drag-resize window" }
)

-- Move active window to workspace
bind(
  "SUPER + ALT + h",
  hl.dsp.window.move({ workspace = -1 }),
  { description = "Move window to previous workspace" }
)
bind(
  "SUPER + ALT + j",
  hl.dsp.window.move({ workspace = 2 }),
  { description = "Move window to workspace 2" }
)
bind(
  "SUPER + ALT + k",
  hl.dsp.window.move({ workspace = 1 }),
  { description = "Move window to workspace 1" }
)
bind(
  "SUPER + ALT + l",
  hl.dsp.window.move({ workspace = "+1" }),
  { description = "Move window to next workspace" }
)

bind(
  "SUPER + d",
  hl.dsp.submap("workspace-cmd"),
  { description = "Workspace submap [workspace-cmd]" }
)
hl.define_submap("workspace-cmd", function()
  bind(
    "TAB",
    hl.dsp.workspace.move({ workspace = "+1", monitor = "current" }),
    { description = "Next workspace (this monitor)", hint = "Next ws", group = "Go to" }
  )
  bind(
    "SHIFT + TAB",
    hl.dsp.workspace.move({ workspace = "-1", monitor = "current" }),
    { description = "Previous workspace (this monitor)", hint = "Prev ws", group = "Go to" }
  )
  bind("CTRL + TAB", hl.dsp.window.move({ workspace = "next_per_monitor", follow = true }), {
    description = "Move window to next workspace (follow)",
    hint = "Win to next ws",
    group = "Move window",
  })
  bind(
    "CTRL + SHIFT + TAB",
    hl.dsp.window.move({ workspace = "previous_per_monitor", follow = true }),
    {
      description = "Move window to previous workspace (follow)",
      hint = "Win to prev ws",
      group = "Move window",
    }
  )

  -- Move window to workspace by number
  bind("CTRL + x", hl.dsp.window.move({ workspace = "1", follow = true }), {
    description = "Move window to workspace 1 (follow)",
    hint = "Win to ws 1",
    group = "Move window",
  })
  bind("CTRL + c", hl.dsp.window.move({ workspace = "2", follow = true }), {
    description = "Move window to workspace 2 (follow)",
    hint = "Win to ws 2",
    group = "Move window",
  })
  bind("CTRL + v", hl.dsp.window.move({ workspace = "3", follow = true }), {
    description = "Move window to workspace 3 (follow)",
    hint = "Win to ws 3",
    group = "Move window",
  })
  bind("CTRL + s", hl.dsp.window.move({ workspace = "4", follow = true }), {
    description = "Move window to workspace 4 (follow)",
    hint = "Win to ws 4",
    group = "Move window",
  })
  bind("CTRL + d", hl.dsp.window.move({ workspace = "5", follow = true }), {
    description = "Move window to workspace 5 (follow)",
    hint = "Win to ws 5",
    group = "Move window",
  })
  bind("CTRL + f", hl.dsp.window.move({ workspace = "6", follow = true }), {
    description = "Move window to workspace 6 (follow)",
    hint = "Win to ws 6",
    group = "Move window",
  })
  bind("CTRL + w", hl.dsp.window.move({ workspace = "7", follow = true }), {
    description = "Move window to workspace 7 (follow)",
    hint = "Win to ws 7",
    group = "Move window",
  })
  bind("CTRL + e", hl.dsp.window.move({ workspace = "8", follow = true }), {
    description = "Move window to workspace 8 (follow)",
    hint = "Win to ws 8",
    group = "Move window",
  })
  bind("CTRL + r", hl.dsp.window.move({ workspace = "9", follow = true }), {
    description = "Move window to workspace 9 (follow)",
    hint = "Win to ws 9",
    group = "Move window",
  })
  bind("CTRL + b", hl.dsp.window.move({ workspace = "0", follow = true }), {
    description = "Move window to workspace 10 (follow)",
    hint = "Win to ws 10",
    group = "Move window",
  })

  -- Focus workspace by number
  bind(
    "1",
    hl.dsp.focus({ workspace = "1" }),
    { description = "Focus workspace 1", group = "Go to" }
  )
  bind(
    "2",
    hl.dsp.focus({ workspace = "2" }),
    { description = "Focus workspace 2", group = "Go to" }
  )
  bind(
    "3",
    hl.dsp.focus({ workspace = "3" }),
    { description = "Focus workspace 3", group = "Go to" }
  )
  bind(
    "4",
    hl.dsp.focus({ workspace = "4" }),
    { description = "Focus workspace 4", group = "Go to" }
  )
  bind(
    "5",
    hl.dsp.focus({ workspace = "5" }),
    { description = "Focus workspace 5", group = "Go to" }
  )
  bind(
    "6",
    hl.dsp.focus({ workspace = "6" }),
    { description = "Focus workspace 6", group = "Go to" }
  )
  bind(
    "7",
    hl.dsp.focus({ workspace = "7" }),
    { description = "Focus workspace 7", group = "Go to" }
  )
  bind(
    "8",
    hl.dsp.focus({ workspace = "8" }),
    { description = "Focus workspace 8", group = "Go to" }
  )
  bind(
    "9",
    hl.dsp.focus({ workspace = "9" }),
    { description = "Focus workspace 9", group = "Go to" }
  )
  bind(
    "0",
    hl.dsp.focus({ workspace = "10" }),
    { description = "Focus workspace 10", group = "Go to" }
  )
  bind(
    "l",
    cycle_workspace_layout,
    { description = "Cycle workspace layout", hint = "Cycle layout", group = "Look" }
  )

  -- Desktop appearance
  -- backend dispatch: quickshell launcher wallpaper mode, or rofi WallpaperSelect.sh
  bind(
    "w",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh wallpaper"'),
    { description = "Wallpaper chooser", group = "Look" }
  )
  bind(
    "SHIFT + w",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/WallpaperRandom.sh"'),
    { description = "Random wallpaper", group = "Look" }
  )
  bind(
    "t",
    hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/ThemeChanger.sh"'),
    { description = "Theme chooser", group = "Look" }
  )

  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
bind("SUPER + w", hl.dsp.submap("window-cmd"), { description = "Window submap [window-cmd]" })
-- App submap: actions on every window of one application (one Hyprland class),
-- across all workspaces and monitors. Hyprland's own dispatchers act on one
-- window or one workspace; nothing acts on "all of Brave", so these loop over
-- hl.get_windows() and dispatch per window by address.
--
-- Conventions, kept the same as workspace-cmd and window-cmd:
--   * SHIFT reverses: `.`/SHIFT+`.`, TAB/SHIFT+TAB, h/SHIFT+h, m/SHIFT+m, o/SHIFT+o.
--   * The left-hand numpad x c v / s d f / w e r / b is workspace 1-9 / 10.
--     CTRL+letter sends and follows (as in workspace-cmd); the plain letter
--     sends without changing the workspace you are on.
--   * Cycling keys (`.`, TAB) keep the submap open so they can repeat; every
--     other action exits it.
--
-- Classes are compared in Lua rather than passed as a get_windows filter,
-- because the filter's matching rules (exact vs regex) are undocumented in the
-- stubs. Order is by address: stable between presses, so a repeated cycle
-- visits each window once before wrapping.

local function win_sel(w)
  return "address:" .. w.address
end

local function app_windows(class)
  local out = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.class == class then
      out[#out + 1] = w
    end
  end
  table.sort(out, function(a, b)
    return a.address < b.address
  end)
  return out
end

-- Most recently focused window of a list (lowest focus_history_id).
local function most_recent(wins)
  local best
  for _, w in ipairs(wins) do
    if w.focus_history_id and (not best or w.focus_history_id < best.focus_history_id) then
      best = w
    end
  end
  return best or wins[1]
end

local function focus_win(w)
  hl.dispatch(hl.dsp.focus({ window = win_sel(w) }))
end

local function app_exit()
  hl.dispatch(hl.dsp.submap("reset"))
end

local function cycle_app_windows(step)
  local cur = hl.get_active_window()
  if not cur or not cur.class then
    return
  end
  local wins = app_windows(cur.class)
  if #wins < 2 then
    return
  end
  for i, w in ipairs(wins) do
    if w.address == cur.address then
      focus_win(wins[((i - 1 + step) % #wins) + 1])
      return
    end
  end
end

-- Next/previous application, alphabetical by class, landing on that app's
-- most recently used window. An alt-tab by app rather than by window.
local function cycle_apps(step)
  local cur = hl.get_active_window()
  local by_class, classes = {}, {}
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.class and w.class ~= "" and not (w.workspace and w.workspace.special) then
      if not by_class[w.class] then
        by_class[w.class] = {}
        classes[#classes + 1] = w.class
      end
      table.insert(by_class[w.class], w)
    end
  end
  if #classes == 0 then
    return
  end
  table.sort(classes)
  local idx = 0
  for i, c in ipairs(classes) do
    if cur and c == cur.class then
      idx = i
    end
  end
  local nxt = classes[((idx - 1 + step) % #classes) + 1]
  if idx == 0 then
    nxt = classes[1]
  end
  focus_win(most_recent(by_class[nxt]))
end

-- Toggle back to the most recently used window of any *other* app.
local function last_app()
  local cur = hl.get_active_window()
  local others = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    if not cur or (w.class ~= cur.class and not (w.workspace and w.workspace.special)) then
      others[#others + 1] = w
    end
  end
  if #others > 0 then
    focus_win(most_recent(others))
  end
end

-- Move every window of the focused app. `target` is a hl.dsp.window.move table
-- without window/follow ({ workspace = "3" } or { monitor = "+1" }). Each window
-- moves silently; following is done by focusing the original window afterwards,
-- so the view ends where the focused window went.
local function move_app(target, follow)
  local cur = hl.get_active_window()
  if not cur or not cur.class then
    return
  end
  for _, w in ipairs(app_windows(cur.class)) do
    local o = { window = win_sel(w), follow = false }
    for k, v in pairs(target) do
      o[k] = v
    end
    hl.dispatch(hl.dsp.window.move(o))
  end
  if follow then
    focus_win(cur)
  end
end

local function gather_app()
  local ws = hl.get_active_workspace()
  if ws and ws.id then
    move_app({ workspace = tostring(ws.id) }, true)
  end
end

-- Hide/restore through named special workspaces, so Hyprland holds the state:
-- `h` sends the app to special:hide-<class>, `o` sends the other apps on this
-- workspace to special:hide-others. Restore reads hl.get_windows() back, so a
-- config reload (which re-runs this file and wipes any Lua table) strands
-- nothing. A hidden app can also be peeked at in place, as a scratchpad, with
-- `hyprctl dispatch 'hl.dsp.workspace.toggle_special(...)'`.
local HIDE_PREFIX = "special:hide-"
local HIDE_OTHERS = HIDE_PREFIX .. "others"

local function hide_ws(class)
  return HIDE_PREFIX .. class:gsub("[^%w._-]", "_")
end

local function hide_app()
  local cur = hl.get_active_window()
  if not cur or not cur.class then
    return
  end
  local ws = hide_ws(cur.class)
  for _, w in ipairs(app_windows(cur.class)) do
    hl.dispatch(hl.dsp.window.move({ window = win_sel(w), workspace = ws, follow = false }))
  end
end

local function hide_other_apps()
  local cur = hl.get_active_window()
  local ws = hl.get_active_workspace()
  if not cur or not ws then
    return
  end
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.workspace and w.workspace.id == ws.id and w.class ~= cur.class then
      hl.dispatch(
        hl.dsp.window.move({ window = win_sel(w), workspace = HIDE_OTHERS, follow = false })
      )
    end
  end
end

-- Move every window whose workspace name satisfies `match` to this workspace.
local function restore_where(match)
  local ws = hl.get_active_workspace()
  if not ws or not ws.id then
    return
  end
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.workspace and w.workspace.name and match(w.workspace.name) then
      hl.dispatch(
        hl.dsp.window.move({ window = win_sel(w), workspace = tostring(ws.id), follow = false })
      )
    end
  end
end

-- The most recently hidden app = the hide-<class> workspace holding the most
-- recently focused window. Stateless, so it survives a reload too.
local function last_hidden_ws()
  local hidden = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local n = w.workspace and w.workspace.name or ""
    if n:sub(1, #HIDE_PREFIX) == HIDE_PREFIX and n ~= HIDE_OTHERS then
      hidden[#hidden + 1] = w
    end
  end
  local w = most_recent(hidden)
  return w and w.workspace.name or nil
end

local function restore_last_app()
  local name = last_hidden_ws()
  if name then
    restore_where(function(n)
      return n == name
    end)
  end
end

local function restore_all_hidden()
  restore_where(function(n)
    return n:sub(1, #HIDE_PREFIX) == HIDE_PREFIX
  end)
end

-- Peek: show the last hidden app's special workspace over the current one, as
-- a scratchpad, without restoring it. Press again to put it away.
-- toggle_special takes the name WITHOUT the "special:" prefix.
local function peek_last_hidden()
  local name = last_hidden_ws()
  if name then
    hl.dispatch(hl.dsp.workspace.toggle_special((name:gsub("^special:", ""))))
  end
end

-- New window: re-run the focused window's own command line from /proc. Apps
-- that keep a single instance (Brave, most browsers) answer with a new window.
local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function new_app_window()
  local cur = hl.get_active_window()
  if not cur or not cur.pid then
    return
  end
  local fh = io.open("/proc/" .. cur.pid .. "/cmdline", "rb")
  if not fh then
    return
  end
  local raw = fh:read("*a")
  fh:close()
  local args = {}
  for a in raw:gmatch("[^%z]+") do
    args[#args + 1] = shell_quote(a)
  end
  if #args > 0 then
    hl.dispatch(hl.dsp.exec_cmd(table.concat(args, " ")))
  end
end

-- Picker / close-all confirm live in quickshell (WindowPicker). The submap must
-- be reset BEFORE the picker opens: it takes an exclusive keyboard grab, and a
-- submap left active underneath would swallow the next key after it closes.
local function picker(args)
  app_exit()
  os.execute("qs ipc call windowpicker " .. args .. " >/dev/null 2>&1 &")
end

local function picker_app(mode)
  local cur = hl.get_active_window()
  if cur and cur.class then
    picker(mode .. " " .. shell_quote(cur.class))
  end
end

local function once(fn)
  return function()
    fn()
    app_exit()
  end
end

-- workspace number -> numpad letter, as in workspace-cmd
local APP_WS_KEYS = { "x", "c", "v", "s", "d", "f", "w", "e", "r", "b" }

bind("SUPER + a", hl.dsp.submap("app-cmd"), { description = "App submap [app-cmd]" })
hl.define_submap("app-cmd", function()
  bind("period", function()
    cycle_app_windows(1)
  end, {
    description = "Next window of this app (all workspaces)",
    hint = "Next app window",
    group = "Navigate",
  })
  bind("SHIFT + period", function()
    cycle_app_windows(-1)
  end, {
    description = "Previous window of this app (all workspaces)",
    hint = "Prev app window",
    group = "Navigate",
  })
  bind("TAB", function()
    cycle_apps(1)
  end, { description = "Next app", group = "Navigate" })
  bind("SHIFT + TAB", function()
    cycle_apps(-1)
  end, { description = "Previous app", hint = "Prev app", group = "Navigate" })
  bind(
    "l",
    once(last_app),
    { description = "Last-used other app", hint = "Last app", group = "Navigate" }
  )

  bind(
    "g",
    once(gather_app),
    { description = "Gather all windows of this app here", hint = "Gather here", group = "Arrange" }
  )
  bind(
    "h",
    once(hide_app),
    { description = "Hide all windows of this app", hint = "Hide app", group = "Hide" }
  )
  bind(
    "SHIFT + h",
    once(restore_last_app),
    { description = "Restore the last hidden app here", hint = "Unhide app", group = "Hide" }
  )
  bind("p", once(peek_last_hidden), {
    description = "Peek at the last hidden app (scratchpad toggle)",
    hint = "Peek hidden",
    group = "Hide",
  })
  bind(
    "SHIFT + p",
    once(restore_all_hidden),
    { description = "Restore every hidden app here", hint = "Unhide all", group = "Hide" }
  )
  bind(
    "o",
    once(hide_other_apps),
    { description = "Hide other apps on this workspace", hint = "Hide others", group = "Hide" }
  )
  bind(
    "SHIFT + o",
    once(function()
      restore_where(function(n)
        return n == HIDE_OTHERS
      end)
    end),
    { description = "Restore the hidden other apps", hint = "Unhide others", group = "Hide" }
  )
  bind(
    "m",
    once(function()
      move_app({ monitor = "+1" }, true)
    end),
    {
      description = "Move all windows of this app to next monitor",
      hint = "To next monitor",
      group = "Arrange",
    }
  )
  bind(
    "SHIFT + m",
    once(function()
      move_app({ monitor = "-1" }, true)
    end),
    {
      description = "Move all windows of this app to previous monitor",
      hint = "To prev monitor",
      group = "Arrange",
    }
  )
  bind(
    "CTRL + TAB",
    once(function()
      move_app({ workspace = "next_per_monitor" }, true)
    end),
    {
      description = "Send all windows of this app to next workspace (follow)",
      hint = "To next ws, follow",
      group = "Arrange",
    }
  )
  bind(
    "CTRL + SHIFT + TAB",
    once(function()
      move_app({ workspace = "previous_per_monitor" }, true)
    end),
    {
      description = "Send all windows of this app to previous workspace (follow)",
      hint = "To prev ws, follow",
      group = "Arrange",
    }
  )

  for n, key in ipairs(APP_WS_KEYS) do
    local ws = tostring(n == 10 and 10 or n)
    bind(
      key,
      once(function()
        move_app({ workspace = ws }, false)
      end),
      {
        description = "Send all windows of this app to workspace " .. ws,
        hint = "To ws " .. ws,
        group = "Send to ws",
      }
    )
    bind(
      "CTRL + " .. key,
      once(function()
        move_app({ workspace = ws }, true)
      end),
      {
        description = "Send all windows of this app to workspace " .. ws .. " (follow)",
        hint = "To ws " .. ws .. ", follow",
        group = "Send + follow",
      }
    )
  end

  bind(
    "n",
    once(new_app_window),
    { description = "New window of this app", hint = "New window", group = "Window" }
  )
  bind("slash", function()
    picker_app("pick")
  end, { description = "Pick a window of this app", hint = "Pick window", group = "Navigate" })
  bind("q", function()
    picker_app("close")
  end, {
    description = "Close all windows of this app (confirm)",
    hint = "Close all…",
    group = "Window",
  })
  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

hl.define_submap("window-cmd", function()
  -- bind("SHIFT + h", hl.dsp.resize({ x = 10, y = 0, relative = true }), { repeating = true })
  bind("TAB", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
  end, { description = "Cycle to next window (raise)", hint = "Next window", group = "Focus" })
  bind("slash", function()
    picker("pick ''")
  end, { description = "Pick any window", group = "Focus" })

  bind(
    "n",
    hl.dsp.layout("togglesplit"),
    { description = "Toggle split direction", hint = "Toggle split", group = "Layout" }
  )
  bind(
    "SUPER + l",
    hl.dsp.layout("dwindle"),
    { description = "Set dwindle layout", group = "Layout" }
  )
  bind("r", function()
    local ws = hl.get_active_workspace()
    if ws then
      if ws.tiled_layout == "master" then
        hl.dispatch(hl.dsp.layout("orientationnext"))
      elseif ws.tiled_layout == "dwindle" then
        hl.dispatch(hl.dsp.layout("togglesplit"))
      end
    end
  end, {
    description = "Rotate layout (master orientation / dwindle split)",
    hint = "Rotate layout",
    group = "Layout",
  })
  bind(
    "SHIFT + r",
    function()
      local ws = hl.get_active_workspace()
      if ws and ws.tiled_layout == "master" then
        hl.dispatch(hl.dsp.layout("orientationprev"))
      end
    end,
    { description = "Rotate master orientation backward", hint = "Rotate back", group = "Layout" }
  )
  bind("comma", function()
    local ws = hl.get_active_workspace()
    if ws then
      if ws.tiled_layout == "master" then
        hl.dispatch(hl.dsp.layout("swapwithmaster"))
      elseif ws.tiled_layout == "dwindle" then
        hl.dispatch(hl.dsp.layout("swapsplit"))
      end
    end
  end, { description = "Swap with master / swap split", hint = "Swap master", group = "Layout" })
  bind("period", function()
    local ws = hl.get_active_workspace()
    if ws and ws.tiled_layout == "master" then
      hl.dispatch(hl.dsp.layout("rollnext"))
    end
  end, { description = "Roll windows forward (master)", hint = "Roll forward", group = "Layout" })

  bind("q", hl.dsp.window.close(), { description = "Close active window", group = "Window state" })
  bind("c", hl.dsp.window.center(), { description = "Center window", group = "Window state" })
  bind(
    "f",
    hl.dsp.window.fullscreen(),
    { description = "Toggle fullscreen", group = "Window state" }
  )
  bind(
    "m",
    hl.dsp.window.fullscreen({ mode = "maximized" }),
    { description = "Maximize window", group = "Window state" }
  )
  bind("t", hl.dsp.window.float(), { description = "Toggle floating", group = "Window state" })

  bind(
    "s",
    hl.dsp.submap("window-swap"),
    { description = "Window-swap submap [window-swap]", group = "Layout" }
  )
  hl.define_submap("window-swap", function()
    bind(
      "h",
      hl.dsp.window.swap({ direction = "left" }),
      { description = "Swap window left", group = "Swap" }
    )
    bind(
      "j",
      hl.dsp.window.swap({ direction = "down" }),
      { description = "Swap window down", group = "Swap" }
    )
    bind(
      "k",
      hl.dsp.window.swap({ direction = "up" }),
      { description = "Swap window up", group = "Swap" }
    )
    bind(
      "l",
      hl.dsp.window.swap({ direction = "right" }),
      { description = "Swap window right", group = "Swap" }
    )
    bind(
      "escape",
      hl.dsp.submap("window-cmd"),
      { description = "Back to window submap", hint = "Back" }
    )
  end)
  -- bind("SHIFT + t", hl.dsp.float())
  -- bind("SHIFT + t", hl.dsp.float())
  -- bind("b", focus browser)
  -- bind("b", focus browser)
  -- bind("g", focus terminal)
  -- bind("g", focus terminal)

  bind(
    "CTRL + h",
    hl.dsp.window.move({ direction = "left" }),
    { description = "Move window left", group = "Move" }
  )
  bind(
    "CTRL + j",
    hl.dsp.window.move({ direction = "down" }),
    { description = "Move window down", group = "Move" }
  )
  bind(
    "CTRL + k",
    hl.dsp.window.move({ direction = "up" }),
    { description = "Move window up", group = "Move" }
  )
  bind(
    "CTRL + l",
    hl.dsp.window.move({ direction = "right" }),
    { description = "Move window right", group = "Move" }
  )

  bind(
    "ALT + h",
    hl.dsp.window.move({ x = -10, y = 0, relative = true }),
    { description = "Nudge window left", group = "Nudge" }
  )
  bind(
    "ALT + j",
    hl.dsp.window.move({ x = 0, y = 10, relative = true }),
    { description = "Nudge window down", group = "Nudge" }
  )
  bind(
    "ALT + k",
    hl.dsp.window.move({ x = 10, y = -10, relative = true }),
    { description = "Nudge window up-right", hint = "Nudge up-right", group = "Nudge" }
  )
  bind(
    "ALT + l",
    hl.dsp.window.move({ x = 10, y = 0, relative = true }),
    { description = "Nudge window right", group = "Nudge" }
  )

  bind(
    "SHIFT + h",
    hl.dsp.window.resize({ x = -10, y = 0, relative = true }),
    { description = "Shrink window width", hint = "Shrink W", group = "Resize" }
  )
  bind(
    "SHIFT + j",
    hl.dsp.window.resize({ x = 0, y = 10, relative = true }),
    { description = "Grow window height", hint = "Grow H", group = "Resize" }
  )
  bind(
    "SHIFT + k",
    hl.dsp.window.resize({ x = 0, y = -10, relative = true }),
    { description = "Shrink window height", hint = "Shrink H", group = "Resize" }
  )
  bind(
    "SHIFT + l",
    hl.dsp.window.resize({ x = 10, y = 0, relative = true }),
    { description = "Grow window width", hint = "Grow W", group = "Resize" }
  )

  bind(
    "CTRL + SHIFT + h",
    hl.dsp.window.resize({ x = -100, y = 0, relative = true }),
    { description = "Shrink window width (large)", hint = "Shrink W (big)", group = "Resize" }
  )
  bind(
    "CTRL + SHIFT + j",
    hl.dsp.window.resize({ x = 0, y = 100, relative = true }),
    { description = "Grow window height (large)", hint = "Grow H (big)", group = "Resize" }
  )
  bind(
    "CTRL + SHIFT + k",
    hl.dsp.window.resize({ x = 0, y = -100, relative = true }),
    { description = "Shrink window height (large)", hint = "Shrink H (big)", group = "Resize" }
  )
  bind(
    "CTRL + SHIFT + l",
    hl.dsp.window.resize({ x = 100, y = 0, relative = true }),
    { description = "Grow window width (large)", hint = "Grow W (big)", group = "Resize" }
  )

  -- Focus movement within submap
  bind(
    "h",
    hl.dsp.focus({ direction = "left" }),
    { description = "Focus window left", group = "Focus" }
  )
  bind(
    "j",
    hl.dsp.focus({ direction = "down" }),
    { description = "Focus window down", group = "Focus" }
  )
  bind(
    "k",
    hl.dsp.focus({ direction = "up" }),
    { description = "Focus window up", group = "Focus" }
  )
  bind(
    "l",
    hl.dsp.focus({ direction = "right" }),
    { description = "Focus window right", group = "Focus" }
  )
  --
  -- Use `reset` to go back to the global submap
  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

bind("SUPER + period", function()
  cycle_app_windows(1)
end, { description = "Next window of this app (all workspaces)", hint = "Next app window" })
bind("SUPER + SHIFT + period", function()
  cycle_app_windows(-1)
end, { description = "Previous window of this app (all workspaces)", hint = "Prev app window" })

-- focus submap for focusing specific applications
bind("SUPER + f", hl.dsp.submap("focus-cmd"), { description = "Focus-app submap [focus-cmd]" })

hl.define_submap("focus-cmd", function()
  -- Focus terminal (ghostty)
  bind("t", function()
    hl.dispatch(hl.dsp.focus({ window = "class:com.mitchellh.ghostty" }))
  end, { description = "Focus Ghostty terminal", hint = "Ghostty", group = "Apps" })
  bind("b", function()
    hl.dispatch(hl.dsp.focus({ window = "class:brave-browser" }))
  end, { description = "Focus Brave browser", group = "Apps" })
  bind("l", hl.dsp.focus({ last = true }), { description = "Focus last window", group = "Window" })
  bind("slash", function()
    picker("pick ''")
  end, { description = "Pick any window", group = "Window" })

  -- Exit submap
  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

-- Actions
-- Launcher/bar dispatch by $HYPR_LAUNCHER / $HYPR_BAR (see hypr/scripts/shell-env.sh).
bind(
  "SUPER + CTRL + RETURN",
  hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh"'),
  { description = "App launcher (rofi/quickshell)" }
)
bind(
  "SUPER + r",
  hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Launcher.sh"'),
  { description = "App launcher (rofi/quickshell)" }
)
bind(
  "SUPER + SHIFT + B",
  hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/StartBar.sh"'),
  { description = "Restart status bar (waybar/quickshell)", hint = "Restart bar" }
)
-- Escape hatch: full config reload. Resets runtime workspace/layout state;
-- theme colors normally arrive via scripts/ApplyHyprColors.sh without this.
bind(
  "SUPER + SHIFT + R",
  hl.dsp.exec_cmd("hyprctl reload"),
  { description = "Reload Hyprland config (resets runtime layout state)", hint = "Reload config" }
)
bind("SUPER + Escape", function()
  -- quickshell session dialog; fall back to wlogout if the qs daemon isn't running
  os.execute("qs ipc call session toggle 2>/dev/null || setsid -f wlogout --protocol layer-shell")
end, { description = "Session/power menu" })
bind("SUPER + slash", function()
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

bind("SUPER + n", hl.dsp.submap("notif-cmd"), { description = "Notifications submap [notif-cmd]" })
hl.define_submap("notif-cmd", function()
  bind("d", function()
    -- searchable history drawer; also opens from the bar bell
    notif_run("qs ipc call notifications drawer 2>/dev/null")
  end, { description = "Notification history drawer", hint = "History drawer", group = "View" })

  bind("f", function()
    -- focus the popup stack itself: j/k move, d dismisses, Esc releases. Popups never grab the
    -- keyboard on their own, so this is the only way in.
    notif_run("qs ipc call notifications focus 2>/dev/null")
  end, {
    description = "Focus the notification stack (keyboard control)",
    hint = "Focus stack",
    group = "View",
  })

  bind("x", function()
    notif_run("qs ipc call notifications dismissAll 2>/dev/null")
  end, { description = "Dismiss everything on screen", hint = "Dismiss all", group = "Clear" })

  bind("r", function()
    notif_run("qs ipc call notifications markRead 2>/dev/null")
  end, {
    description = "Mark all read (clear the bell count)",
    hint = "Mark all read",
    group = "Clear",
  })

  bind("z", function()
    -- Do Not Disturb toggle (story: notif-dnd-core); "z" for zzz. Read back with
    -- `qs ipc call notifications dndStatus`.
    notif_run("qs ipc call notifications dnd 2>/dev/null")
  end, { description = "Toggle Do Not Disturb", hint = "Do not disturb", group = "Mode" })

  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

-- Kept outside the submap: the drawer is the verb reached most often, and dismiss-all is a panic
-- key that should never need two presses.
bind("SUPER + i", function()
  os.execute("qs ipc call notifications drawer 2>/dev/null")
end, { description = "Notification history drawer", hint = "History drawer" })
bind("SUPER + SHIFT + N", function()
  os.execute("qs ipc call notifications dismissAll 2>/dev/null")
end, { description = "Dismiss all notifications" })
-- Clock drawer: weather, world clocks, calendar. The bar clock opens the same surface.
--
-- Routed through notif_run despite not being a notification verb: that helper resets the submap
-- BEFORE running, and the reason (the LOAD-BEARING comment above it) is about the keyboard, not
-- about notifications. This drawer takes the same EXCLUSIVE layer-shell grab, so pressing this
-- from inside a submap would leave that submap active with an exclusive surface swallowing every
-- key — including its own escape. The name is now narrower than what it does; renaming it is a
-- change of its own, not a rider on this one.
bind("SUPER + c", function()
  notif_run("qs ipc call clock drawer 2>/dev/null")
end, { description = "Clock drawer (weather, world clocks, calendar)", hint = "Clock drawer" })

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

bind("SUPER + t", hl.dsp.submap("time-cmd"), { description = "Copy date/time submap [time-cmd]" })
hl.define_submap("time-cmd", function()
  -- lowercase local, SHIFT UTC
  bind("d", function()
    time_run("date")
  end, { description = "Copy date (2026-08-19)", hint = "Date", group = "Date" })
  bind("SHIFT + d", function()
    time_run("date-utc")
  end, { description = "Copy date, UTC", group = "Date" })
  bind("t", function()
    time_run("time")
  end, { description = "Copy time (14:03:11)", group = "Time" })
  bind("SHIFT + t", function()
    time_run("time-utc")
  end, { description = "Copy time, UTC", group = "Time" })
  bind("b", function()
    time_run("datetime")
  end, { description = "Copy date + time", group = "Date + time" })
  bind("SHIFT + b", function()
    time_run("datetime-utc")
  end, { description = "Copy date + time, UTC", hint = "Date + time UTC", group = "Date + time" })
  bind(
    "i",
    function()
      time_run("iso")
    end,
    { description = "Copy ISO 8601 with offset", hint = "ISO 8601 local", group = "Date + time" }
  )
  bind(
    "SHIFT + i",
    function()
      time_run("iso-utc")
    end,
    { description = "Copy ISO 8601, UTC (Z suffix)", hint = "ISO 8601 UTC", group = "Date + time" }
  )

  -- No UTC variants below: all three are local by definition.
  bind("s", function()
    time_run("stamp")
  end, { description = "Copy Operon frontmatter stamp", hint = "Operon stamp", group = "Stamps" })
  bind("e", function()
    time_run("epoch")
  end, { description = "Copy Unix epoch seconds", hint = "Unix epoch", group = "Stamps" })
  bind("n", function()
    time_run("daily")
  end, {
    description = "Copy daily-note name (Aug-19-Wed)",
    hint = "Daily-note name",
    group = "Stamps",
  })

  -- Not a copy verb: the same surface as SUPER + c, reachable from here too. notif_run, not
  -- time_run — the drawer takes an EXCLUSIVE grab, so the submap must reset first (see above).
  bind("c", function()
    notif_run("qs ipc call clock drawer 2>/dev/null")
  end, {
    description = "Clock drawer (weather, world clocks, calendar)",
    hint = "Clock drawer",
    group = "Clock",
  })

  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
-- Timers submap. Pure wiring over the `timers` IpcHandler in shell.qml (start/alarm/pomodoro/
-- stopwatch/list) -- no quickshell code here, that surface is done and stable.
--
-- Reset-before-run, same as notif_run and time_run, but for a third reason: nothing bound here
-- takes an EXCLUSIVE layer-shell grab (unlike notif_run's drawer/focus verbs), so plain
-- os.execute is safe for every verb EXCEPT the list bind below. That one pipes qs's output
-- through notify-send, which is a SYNCHRONOUS D-Bus call answered by qs itself -- the same
-- single-threaded process that also has to round-trip to Hyprland. os.execute there would block
-- Hyprland's main thread on notify-send, which blocks on qs, which blocks on the compositor: the
-- wl-copy deadlock shape from time_run's comment, not just a slow keypress. That bind uses
-- hl.dsp.exec_cmd (fork, no wait) instead, same as time_run does for CopyDateTime.sh. The reset
-- still has to happen first regardless -- staying in the submap after an action swallows the
-- next keystroke, same as time_run's reason.
--
-- Most `id`-taking verbs (pause/resume/reset/cancel/extend) are still not bindable to a bare
-- key -- a key press cannot supply an arbitrary id, and which timer's id is "the one you want"
-- is a UI runtime detail these binds cannot know. `toggle` is the exception: shell.qml resolves
-- an id of 0 to the newest live timer (Timers.resolve, config/Timers.qml:160-164), so `toggle 0`
-- is bindable and pauses/resumes whichever timer was started most recently.
local function timer_run(cmd)
  hl.dispatch(hl.dsp.submap("reset"))
  os.execute(cmd)
end

bind("SUPER + m", hl.dsp.submap("timer-cmd"), { description = "Timer submap [timer-cmd]" })
hl.define_submap("timer-cmd", function()
  -- Fixed presets, not a prompt -- a prompt is new UI and this task is wiring only.
  bind("1", function()
    timer_run('qs ipc call timers start 5m "" 2>/dev/null')
  end, { description = "Start 5m timer", group = "Timers" })
  bind("2", function()
    timer_run('qs ipc call timers start 10m "" 2>/dev/null')
  end, { description = "Start 10m timer", group = "Timers" })
  bind("3", function()
    timer_run('qs ipc call timers start 15m "" 2>/dev/null')
  end, { description = "Start 15m timer", group = "Timers" })
  bind("4", function()
    timer_run('qs ipc call timers start 25m "" 2>/dev/null')
  end, { description = "Start 25m timer", group = "Timers" })
  bind("5", function()
    timer_run('qs ipc call timers start 45m "" 2>/dev/null')
  end, { description = "Start 45m timer", group = "Timers" })
  bind("6", function()
    timer_run('qs ipc call timers start 60m "" 2>/dev/null')
  end, { description = "Start 60m timer", group = "Timers" })

  bind("p", function()
    -- empty spec -> NotifyConfig.timers defaults (25m/5m/15m x4)
    timer_run('qs ipc call timers pomodoro "" "" 2>/dev/null')
  end, { description = "Start pomodoro (default cycle)", hint = "Pomodoro", group = "Pomodoro" })

  bind("w", function()
    timer_run('qs ipc call timers stopwatch "" 2>/dev/null')
  end, { description = "Toggle stopwatch (start/pause)", hint = "Stopwatch", group = "Stopwatch" })
  bind("SHIFT + w", function()
    timer_run("qs ipc call timers lap 2>/dev/null")
  end, { description = "Stopwatch lap", group = "Stopwatch" })
  bind("s", function()
    timer_run("qs ipc call timers stop 2>/dev/null")
  end, { description = "Stop stopwatch", group = "Stopwatch" })

  bind("t", function()
    timer_run("qs ipc call timers toggle 0 2>/dev/null")
  end, { description = "Pause/resume newest timer", hint = "Pause/resume", group = "Timers" })

  bind("c", function()
    timer_run("qs ipc call timers cancelAll 2>/dev/null")
  end, { description = "Cancel all timers", group = "Timers" })
  bind("i", function()
    hl.dispatch(hl.dsp.submap("reset"))
    hl.dispatch(
      hl.dsp.exec_cmd(
        'sh -c "out=\\"$(qs ipc call timers list 2>/dev/null)\\"; notify-send Timers \\"${out:-No timers running}\\""'
      )
    )
  end, { description = "List active timers", group = "Timers" })

  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

bind("CTRL + ALT + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock session" })

-- Workspace switching
bind("SUPER + 1", hl.dsp.focus({ workspace = 1 }), { description = "Focus workspace 1" })
bind("SUPER + 2", hl.dsp.focus({ workspace = 2 }), { description = "Focus workspace 2" })
bind("SUPER + 3", hl.dsp.focus({ workspace = 3 }), { description = "Focus workspace 3" })
bind("SUPER + 4", hl.dsp.focus({ workspace = 4 }), { description = "Focus workspace 4" })
bind("SUPER + 5", hl.dsp.focus({ workspace = 5 }), { description = "Focus workspace 5" })
bind("SUPER + 6", hl.dsp.focus({ workspace = 6 }), { description = "Focus workspace 6" })
bind("SUPER + 7", hl.dsp.focus({ workspace = 7 }), { description = "Focus workspace 7" })
bind("SUPER + 8", hl.dsp.focus({ workspace = 8 }), { description = "Focus workspace 8" })
bind("SUPER + 9", hl.dsp.focus({ workspace = 9 }), { description = "Focus workspace 9" })
bind("SUPER + 0", hl.dsp.focus({ workspace = 10 }), { description = "Focus workspace 10" })

-- AR glasses (XREAL) workspaces. F-keys rather than more digits: 1-0 are spoken
-- for, and these three only exist while the glasses are plugged in.
bind("SUPER + F1", hl.dsp.focus({ workspace = 11 }), { description = "Focus XR1 (ws 11)" })
bind("SUPER + F2", hl.dsp.focus({ workspace = 12 }), { description = "Focus XR2 (ws 12)" })
bind("SUPER + F3", hl.dsp.focus({ workspace = 13 }), { description = "Focus XR3 (ws 13)" })
bind(
  "SUPER + SHIFT + F1",
  hl.dsp.window.move({ workspace = 11 }),
  { description = "Move window to XR1 (ws 11)" }
)
bind(
  "SUPER + SHIFT + F2",
  hl.dsp.window.move({ workspace = 12 }),
  { description = "Move window to XR2 (ws 12)" }
)
bind(
  "SUPER + SHIFT + F3",
  hl.dsp.window.move({ workspace = 13 }),
  { description = "Move window to XR3 (ws 13)" }
)

-- Move window to workspace
bind(
  "SUPER + ALT + x",
  hl.dsp.window.move({ workspace = 1 }),
  { description = "Move window to workspace 1" }
)
bind(
  "SUPER + ALT + c",
  hl.dsp.window.move({ workspace = 2 }),
  { description = "Move window to workspace 2" }
)
bind(
  "SUPER + ALT + v",
  hl.dsp.window.move({ workspace = 3 }),
  { description = "Move window to workspace 3" }
)
bind(
  "SUPER + ALT + s",
  hl.dsp.window.move({ workspace = 4 }),
  { description = "Move window to workspace 4" }
)
bind(
  "SUPER + ALT + d",
  hl.dsp.window.move({ workspace = 5 }),
  { description = "Move window to workspace 5" }
)
bind(
  "SUPER + ALT + f",
  hl.dsp.window.move({ workspace = 6 }),
  { description = "Move window to workspace 6" }
)
bind(
  "SUPER + ALT + w",
  hl.dsp.window.move({ workspace = 7 }),
  { description = "Move window to workspace 7" }
)
bind(
  "SUPER + ALT + e",
  hl.dsp.window.move({ workspace = 8 }),
  { description = "Move window to workspace 8" }
)
bind(
  "SUPER + ALT + r",
  hl.dsp.window.move({ workspace = 9 }),
  { description = "Move window to workspace 9" }
)
bind(
  "SUPER + ALT + b",
  hl.dsp.window.move({ workspace = 10 }),
  { description = "Move window to workspace 10" }
)

-- Workspace cycling
bind(
  "SUPER + Tab",
  hl.dsp.focus({ workspace = "m+1" }),
  { description = "Next workspace on monitor" }
)
bind(
  "SUPER + SHIFT + Tab",
  hl.dsp.focus({ workspace = "m-1" }),
  { description = "Previous workspace on monitor" }
)
bind(
  "SUPER + mouse_down",
  hl.dsp.focus({ workspace = "e+1" }),
  { description = "Next workspace (scroll)" }
)
bind(
  "SUPER + mouse_up",
  hl.dsp.focus({ workspace = "e-1" }),
  { description = "Previous workspace (scroll)" }
)
bind(
  "SUPER + CTRL + down",
  hl.dsp.focus({ workspace = "empty" }),
  { description = "Focus first empty workspace" }
)

-- Dictation (hex). Hex's own hotkey (control+option+g) is not a global grab on
-- Wayland, so Hyprland drives it through the CLI. Not `locked`: no dictating
-- into the lock screen.
--
-- Every chord here is one-handed on the Crosses (zmk-config base.keymap): Super is
-- the hold on `a`, and its positional hold only fires when the next key is on the
-- right hand, the LEFT TOP ROW, or a thumb. So Super + left top row / left thumb
-- works single-handed; Super + s/d/f or the bottom row does not. Shift is the left
-- outer thumb. F-keys are out: they sit on SYM's right half.
-- SPACE is a hold-tap for the MOUSE layer, so it can only ever be tapped — which is
-- why hold-to-talk lives inside the submap on `t`, not on SUPER+SPACE itself.
local function dictate_run(action)
  hl.dispatch(hl.dsp.submap("reset"))
  hl.dispatch(hl.dsp.exec_cmd("hex " .. action))
end

bind(
  "SUPER + SHIFT + t",
  hl.dsp.exec_cmd("hex dictation toggle"),
  { description = "Dictation: toggle" }
)
bind(
  "SUPER + space",
  hl.dsp.submap("dictate-cmd"),
  { description = "Dictation submap [dictate-cmd]" }
)
hl.define_submap("dictate-cmd", function()
  -- Press starts, release stops. The submap stays active while `t` is held and is
  -- left on release, before hex pastes, so the transcript lands in the window.
  bind(
    "t",
    hl.dsp.exec_cmd("hex dictation start"),
    { description = "Hold to talk", group = "Dictation" }
  )
  bind("t", function()
    dictate_run("dictation stop")
  end, {
    release = true,
    description = "Hold to talk (release: transcribe)",
    hint = "Hold to talk",
    group = "Dictation",
  })
  bind("c", function()
    dictate_run("dictation cancel")
  end, { description = "Cancel dictation", group = "Dictation" })
  bind("v", function()
    dictate_run("paste-last")
  end, { description = "Paste last dictation", group = "Dictation" })
  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)

-- Media keys (no modifier)
bind(
  "XF86MonBrightnessUp",
  hl.dsp.exec_cmd("brightnessctl -q s +10%"),
  { locked = true, repeating = true, description = "Brightness +10%" }
)
bind(
  "XF86MonBrightnessDown",
  hl.dsp.exec_cmd("brightnessctl -q s 10%-"),
  { locked = true, repeating = true, description = "Brightness -10%" }
)
bind(
  "XF86AudioRaiseVolume",
  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"),
  { locked = true, repeating = true, description = "Volume +5%" }
)
bind(
  "XF86AudioLowerVolume",
  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"),
  { locked = true, repeating = true, description = "Volume -5%" }
)
bind(
  "XF86AudioMute",
  hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
  { locked = true, description = "Toggle mute" }
)
bind(
  "XF86AudioPlay",
  hl.dsp.exec_cmd("playerctl play-pause"),
  { locked = true, description = "Play/pause media" }
)
bind(
  "XF86AudioPause",
  hl.dsp.exec_cmd("playerctl pause"),
  { locked = true, description = "Pause media" }
)
bind(
  "XF86AudioNext",
  hl.dsp.exec_cmd("playerctl next"),
  { locked = true, description = "Next track" }
)
bind(
  "XF86AudioPrev",
  hl.dsp.exec_cmd("playerctl previous"),
  { locked = true, description = "Previous track" }
)
bind(
  "XF86AudioMicMute",
  hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"),
  { locked = true, description = "Toggle mic mute" }
)

-- Keyboard backlight
bind(
  "code:238",
  hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s +10"),
  { description = "Keyboard backlight +" }
)
bind(
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
bind(
  "SUPER + Y",
  hl.dsp.exec_cmd(
    'sh -c "qs ipc call clipboard toggle 2>/dev/null || ghostty --class=app.clipborg -e clipborg tui"'
  ),
  { description = "Clipboard history (quickshell dialog)", hint = "Clipboard" }
)
bind(
  "SUPER + E",
  hl.dsp.exec_cmd(
    "ghostty --class=app.filemanager --window-padding-x=10,10 --confirm-close-surface=false -e yazi"
  ),
  { description = "File manager (yazi)" }
)

-- Screenshots. Capture + annotation live in scripts/Screenshot.sh; these binds only pick
-- a target and an action. Print alone is the flameshot-style "select, then annotate";
-- the modifiers are the no-editor quick paths (copy to clipboard AND save).
--
-- exec_cmd, never os.execute: satty and slurp both run until the user finishes, and
-- os.execute would hold Hyprland's main thread for that whole time (see time_run above).
local function shot(args)
  return hl.dsp.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Screenshot.sh ' .. args .. '"')
end

bind("Print", shot("area edit"), { description = "Screenshot area, annotate (satty)" })
bind("SHIFT + Print", shot("area copy"), { description = "Screenshot area to clipboard + file" })
bind("CTRL + Print", shot("active copy"), { description = "Screenshot window to clipboard + file" })
bind("ALT + Print", shot("output copy"), { description = "Screenshot monitor to clipboard + file" })

-- Same set on SUPER+P for keyboards without a Print key, plus the rarer verbs. Every verb
-- resets the submap first: slurp takes the pointer and satty takes focus, and a submap
-- left active would swallow the next keystroke.
local function shot_run(args)
  hl.dispatch(hl.dsp.submap("reset"))
  hl.dispatch(shot(args))
end

bind("SUPER + P", hl.dsp.submap("shot-cmd"), { description = "Screenshot submap [shot-cmd]" })
hl.define_submap("shot-cmd", function()
  -- lowercase annotate, SHIFT copy+save without an editor
  bind("a", function()
    shot_run("area edit")
  end, { description = "Area, annotate", group = "Area" })
  bind("SHIFT + a", function()
    shot_run("area copy")
  end, { description = "Area to clipboard + file", hint = "Area", group = "Area" })
  bind("w", function()
    shot_run("active edit")
  end, { description = "Active window, annotate", hint = "Window, annotate", group = "Window" })
  bind("SHIFT + w", function()
    shot_run("active copy")
  end, { description = "Active window to clipboard + file", hint = "Window", group = "Window" })
  bind("m", function()
    shot_run("output edit")
  end, { description = "Focused monitor, annotate", hint = "Monitor, annotate", group = "Monitor" })
  bind("SHIFT + m", function()
    shot_run("output copy")
  end, { description = "Focused monitor to clipboard + file", hint = "Monitor", group = "Monitor" })
  bind(
    "s",
    function()
      shot_run("screen copy")
    end,
    { description = "All monitors to clipboard + file", hint = "All monitors", group = "Monitor" }
  )
  bind("d", function()
    shot_run("area edit 5")
  end, {
    description = "Area after 5s delay, annotate (open the menu first)",
    hint = "Area, 5s, annotate",
    group = "Area",
  })
  bind("l", function()
    shot_run("last")
  end, {
    description = "Re-open last screenshot in annotator",
    hint = "Re-annotate last",
    group = "Tools",
  })
  bind("f", function()
    shot_run("area flameshot")
  end, {
    description = "Flameshot GUI (portal; asks which screen)",
    hint = "Flameshot",
    group = "Tools",
  })
  bind("c", function()
    hl.dispatch(hl.dsp.submap("reset"))
    hl.dispatch(hl.dsp.exec_cmd("hyprpicker --autocopy --format=hex"))
  end, {
    description = "Colour picker to clipboard (hyprpicker)",
    hint = "Colour picker",
    group = "Tools",
  })
  bind("escape", hl.dsp.submap("reset"), { description = "Exit submap" })
end)
