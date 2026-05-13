-- General window layout and colors
-- name: "Default"

hl.config({
    general = {
        gaps_in = 8,
        gaps_out = 4,
        float_gaps = 4,
        gaps_workspaces = 4,
        border_size = 0,
        layout = "dwindle",
        resize_on_border = true,
        extend_border_grab_area = true,
        hover_icon_on_border = true,
        col = {
            active_border = "rgba(ff881186)",
            inactive_border = "rgba(595959aa)",
            nogroup_border = "rgba(88ff1177)",
            nogroup_border_active = "rgba(ff881186)",
        },
        snap = {
            enabled = true,
            respect_gaps = true,
        },
    },
})
