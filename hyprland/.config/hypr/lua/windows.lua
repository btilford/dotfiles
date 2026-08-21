-- General window layout and colors
-- name: "Default"

hl.config({
  general = {
    gaps_in = 4,
    -- top gutter: breathing room between the bar and window tops, so popouts and
    -- their energy connector arcs float in clear space instead of on window content
    gaps_out = { top = 6, right = 2, bottom = 2, left = 2 },
    float_gaps = 4,
    gaps_workspaces = 4,
    border_size = 4,
    -- Multi-monitor default. lua/layout-auto.lua switches to "scrolling" on
    -- single-monitor setups (and back to "master" on 2+) at runtime/hotplug.
    layout = "master",
    resize_on_border = true,
    extend_border_grab_area = true,
    hover_icon_on_border = true,
    col = {
      active_border = "rgba(ff6600ff)",
      inactive_border = "rgba(ff660022)",
      nogroup_border = "rgba(ff660033)",
      nogroup_border_active = "rgba(ff6600ff)",
    },
    snap = {
      enabled = true,
      respect_gaps = true,
    },
  },
})

hl.config({
  scrolling = {
    column_width = 0.75,
  },
})
