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
-- direction is the scroll AXIS and must be a valid enum value: right/left/up/down (the parser
-- reads only the first char, so "horizontal"/"vertical" silently fall back to the default → use
-- right for horizontal scrolling, down for vertical).
--   h100 = scrolling, full-width columns, horizontal (right)
--   h75  = scrolling, 75% columns, horizontal (right)
--   v75  = scrolling, 75% columns, vertical (down)
local H100 = { column_width = 1.0, direction = "right" }
local H75 = { column_width = 0.75, direction = "right" }
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
		hl.config({ scrolling = { column_width = SINGLE_COLUMN_WIDTH, direction = "right" } })
		for i = 1, MAX_WORKSPACE do
			hl.workspace_rule({
				workspace = tostring(i),
				layout = SINGLE_LAYOUT,
				layout_opts = { column_width = SINGLE_COLUMN_WIDTH, direction = "right" },
			})
		end
		return
	end

	-- Multi-monitor: master engine for any unlisted/new workspace, then explicit per-ws rules.
	-- Don't set the GLOBAL scrolling:direction here — changing it re-tiles every scrolling
	-- workspace to that value and clobbers the per-ws "down" (portrait). Each rule below carries
	-- its own direction instead.
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
-- A reload (manual SUPER+SHIFT+R — autoreload is off in misc.lua because wallust's colors.lua
-- writes were triggering it every wallpaper rotation) re-registers the workspace rules but does
-- NOT re-tile existing workspaces to their per-ws direction — they revert to the global
-- scrolling:direction. config.reloaded fires at runtime afterward, so re-running apply_layout
-- here re-applies the per-ws layouts (incl. portrait "down") for real.
hl.on("config.reloaded", apply_layout)

-- Per-workspace column widths.
--
-- The scrolling engine reads only `direction` from workspace-rule layoutopts; column_width in
-- layout_opts is silently ignored — new columns always get the GLOBAL scrolling:column_width
-- (defaultColumnWidth() in ScrollingAlgorithm.cpp consults no workspace rule; verified against
-- the v0.55.4 source 2026-07-14). Emulate it: when a window lands on a workspace whose spec
-- wants a different width, resize its freshly-created column with `layoutmsg colresize <w>`.
-- layoutmsg routes to the focused monitor's active workspace, so only act when the new window
-- actually holds focus (the normal case; silent-rule spawns are skipped). Deferred a beat so
-- focus and column creation have settled.
local function ws_column_width(id)
	local spec = WS_LAYOUTS[id]
	if spec and spec.layout == "scrolling" and spec.opts then
		return spec.opts.column_width
	end
	return nil
end

local function fix_column_width(w)
	local monitors = hl.get_monitors() or {}
	if #monitors <= 1 then
		return -- single-monitor path already sets the global width
	end
	if not w or w.floating or not w.workspace then
		return
	end
	local width = ws_column_width(w.workspace.id)
	if not width then
		return
	end
	hl.timer(function()
		local active = hl.get_active_window()
		if not active or not w.workspace or active.address ~= w.address then
			return -- focus moved on; colresize would hit the wrong workspace
		end
		hl.dispatch(hl.dsp.layout("colresize " .. width))
	end, { timeout = 80, type = "oneshot" })
end

hl.on("window.open", fix_column_width)
hl.on("window.move_to_workspace", fix_column_width)
