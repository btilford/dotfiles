-- Auto-select the window layout by active monitor count.
--   1 monitor   -> "scrolling" with full-width columns (column_width = 1.0)
--   2+ monitors -> "master"
-- Reacts to hotplug via monitor.added / monitor.removed events.
-- See vault plan: Plans/hyprland-single-monitor-scrolling-layout.md
--
-- Must be required AFTER lua.windows (sets the initial default) and lua.workspaces
-- (assigns workspaces to monitors) so this has the final say on layout.

local SINGLE_LAYOUT = "scrolling"
local MULTI_LAYOUT = "master"
local SINGLE_COLUMN_WIDTH = 1.0
local MULTI_COLUMN_WIDTH = 0.75
local MAX_WORKSPACE = 10

local function apply_layout()
    local monitors = hl.get_monitors() or {}
    -- Treat 0 (not yet enumerated at hyprland.start) as single; monitor.added
    -- fires per-display afterward and re-runs this, correcting multi-monitor hosts.
    local single = #monitors <= 1
    local layout = single and SINGLE_LAYOUT or MULTI_LAYOUT
    local column_width = single and SINGLE_COLUMN_WIDTH or MULTI_COLUMN_WIDTH

    -- Default layout for newly created workspaces.
    hl.config({ general = { layout = layout } })
    -- Column width only affects the scrolling layout; harmless under master.
    hl.config({ scrolling = { column_width = column_width } })

    -- Force the layout on already-existing workspaces. The keybind layout-cycle in
    -- lua/keybindings.lua proves workspace_rule takes effect at runtime.
    for i = 1, MAX_WORKSPACE do
        hl.workspace_rule({ workspace = tostring(i), layout = layout })
    end
end

hl.on("hyprland.start", apply_layout)
hl.on("monitor.added", apply_layout)
hl.on("monitor.removed", apply_layout)
