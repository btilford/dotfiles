-- Misc settings

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = false,
        initial_workspace_tracking = 1,
        -- Wallust rewrites lua/colors.lua on every wallpaper rotation (~30 min); with
        -- autoreload on, each rewrite silently re-parses the whole config — resetting
        -- runtime keyword state (ApplyHyprColors) and, before the config.reloaded
        -- handler in layout-auto.lua existed, all per-workspace layouts. Reload
        -- manually with SUPER+SHIFT+R. Verified 2026-07-14 with a border_size canary.
        disable_autoreload = true,
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
})
