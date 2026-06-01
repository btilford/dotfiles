-- General window layout and colors
-- name: "Default"

hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 2,
        float_gaps = 4,
        gaps_workspaces = 4,
        border_size = 1,
        layout = "dwindle",
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
