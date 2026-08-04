-- Custom Layouts
-- Includes a 3-column layout: one main center column + 2 smaller side columns

-- Parked, not registered — see the note at the bottom of this file. luacheck is
-- told about this one name rather than the file, so everything else here is still
-- checked.
-- luacheck: ignore threeColumnLayout
local function threeColumnLayout(ctx)
  local targets = ctx.targets
  local area = ctx.area
  local n = #targets

  if n == 0 then
    return
  end

  local sideWidth = math.floor(area.width * 0.25)
  local centerWidth = area.width - (sideWidth * 2)

  if n <= 3 then
    if targets[1] then
      ctx.grid_cell({
        x = area.x,
        y = area.y,
        w = sideWidth,
        h = area.height,
      }, { targets[1] })
    end
    if targets[2] then
      ctx.grid_cell({
        x = area.x + sideWidth,
        y = area.y,
        w = centerWidth,
        h = area.height,
      }, { targets[2] })
    end
    if targets[3] then
      ctx.grid_cell({
        x = area.x + sideWidth + centerWidth,
        y = area.y,
        w = sideWidth,
        h = area.height,
      }, { targets[3] })
    end
  else
    local colCount = 3
    local baseRows = math.floor(n / colCount)
    local extra = n % colCount
    local rowsPerCol = { baseRows, baseRows, baseRows }
    for i = 1, extra do
      rowsPerCol[i] = rowsPerCol[i] + 1
    end

    local colWidths = { sideWidth, centerWidth, sideWidth }
    local colXs = { area.x, area.x + sideWidth, area.x + sideWidth + centerWidth }
    local rowInCol = { 0, 0, 0 }

    for i, win in ipairs(targets) do
      local targetCol = ((i - 1) % colCount) + 1
      local h = math.floor(area.height / rowsPerCol[targetCol])
      local y = area.y + (rowInCol[targetCol] * h)

      ctx.grid_cell({
        x = colXs[targetCol],
        y = y,
        w = colWidths[targetCol],
        h = h,
      }, { win })

      rowInCol[targetCol] = rowInCol[targetCol] + 1
    end
  end
end

-- Layout API not yet activated, and this function does not match it yet. Per
-- /usr/share/hypr/stubs/hl.meta.lua the entry point is
--   hl.layout.register("threecolumn", { recalculate = function(ctx) ... end })
-- i.e. `hl.layout` is a namespace, not a callable, and a provider is a table with
-- a `recalculate` field. The context differs too: `ctx:grid_cell(i, cols, rows)`
-- RETURNS a box for cell i, and targets are placed with `target:place(box)` —
-- the body above instead calls grid_cell(box, {targets}) and places nothing.
-- Activating it means rewriting against the stub signatures, not uncommenting.
-- hl.dwindle({ preserve_split = true })
