-- Window rules using hl.window_rule() / hl.layer_rule()
-- Reference: https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua

-- Suppress maximize events for all windows
hl.window_rule({
    name = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Floaters
hl.window_rule({
    name = "floaters",
    match = { class = "^(pavucontrol|blueman-manager|nm-connection-editor|qalculate-gtk|Picture-in-Picture|[Ww]logout)$" },
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
    size = "1400 80%",
    rounding = 20,
    dim_around = true,
    xray = true,
})

-- Clipvault (clipboard)
hl.window_rule({
    name = "clipvault",
    match = { class = "^(app.clipvault)$" },
    float = true,
    center = true,
    size = "1200 80%",
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
    size = "75% 350",
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
    move = "75% 100",
    workspace = "1",
    monitor = "1",
})

-- Rofi
hl.window_rule({
    name = "rofi",
    match = { class = ".*(Rofi).*" },
    float = true,
    size = "1400 80%",
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
