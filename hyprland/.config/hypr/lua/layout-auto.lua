-- Per-workspace layout defaults.
--
-- Multi-monitor desktop: explicit layout per workspace (see WS_LAYOUTS). The scrolling layout's
-- direction + column_width are otherwise GLOBAL (scrolling:direction / scrolling:column_width), so
-- to vary them per workspace each scrolling rule carries its own `layout_opts`.
-- Single monitor (laptop): every workspace = scrolling, full-width columns.
--
-- Reacts to hotplug via monitor.added / monitor.removed. Must be required AFTER lua.windows and
-- lua.workspaces so this has the final say. See vault plan: Plans/hyprland-single-monitor-scrolling-layout.md

local SINGLE_LAYOUT = "scrolling"
local SINGLE_COLUMN_WIDTH = 1.0
local MAX_WORKSPACE = 11

-- Per-workspace defaults for the multi-monitor desktop.
--   h100 = scrolling, full-width columns, horizontal
--   h75  = scrolling, 75% columns, horizontal
--   v75  = scrolling, 75% columns, vertical
local H100 = { column_width = 1.0, direction = "horizontal" }
local H75 = { column_width = 0.75, direction = "horizontal" }
local V75 = { column_width = 0.75, direction = "down" }

local WS_LAYOUTS = {
	[1] = { layout = "master" },                        -- Main (primary)
	[2] = { layout = "scrolling", opts = H100 },        -- CLI1 (secondary)
	[3] = { layout = "scrolling", opts = V75 },         -- RefLeft (left vertical)
	[4] = { layout = "scrolling", opts = V75 },         -- RefRight (right vertical)
	[5] = { layout = "scrolling", opts = H100 },        -- CLI2 (primary)
	[6] = { layout = "scrolling", opts = H100 },        -- Draw (secondary)
	[7] = { layout = "scrolling", opts = V75 },         -- Music (left vertical)
	[8] = { layout = "scrolling", opts = V75 },         -- (right vertical)
	[9] = { layout = "master" },                        -- Other (primary)
	[10] = { layout = "scrolling", opts = H75 },        -- Messaging (secondary)
	[11] = { layout = "master" },                       -- stray; no direct shortcut
}

local function apply_layout()
	local monitors = hl.get_monitors() or {}
	-- 0 (not yet enumerated at hyprland.start) is treated as single; monitor.added re-runs this.
	local single = #monitors <= 1

	if single then
		hl.config({ general = { layout = SINGLE_LAYOUT } })
		hl.config({ scrolling = { column_width = SINGLE_COLUMN_WIDTH, direction = "horizontal" } })
		for i = 1, MAX_WORKSPACE do
			hl.workspace_rule({
				workspace = tostring(i),
				layout = SINGLE_LAYOUT,
				layout_opts = { column_width = SINGLE_COLUMN_WIDTH, direction = "horizontal" },
			})
		end
		return
	end

	-- Multi-monitor: default engine for any unlisted/new workspace, then explicit per-ws rules.
	hl.config({ general = { layout = "master" } })
	for id, spec in pairs(WS_LAYOUTS) do
		hl.workspace_rule({
			workspace = tostring(id),
			layout = spec.layout,
			layout_opts = spec.opts, -- nil for master rules; ignored
		})
	end
end

hl.on("hyprland.start", apply_layout)
hl.on("monitor.added", apply_layout)
hl.on("monitor.removed", apply_layout)
