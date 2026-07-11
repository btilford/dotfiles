-- General window decoration
-- name: "Default"
-- Glow effect using wallust colors (dynamic with theme)
--
-- NOTE: scripts/ApplyHyprColors.sh re-applies these colors at runtime via
-- `hyprctl keyword` on theme/wallpaper change (avoids a full reload). When
-- making a color here dynamic or changing a hardcoded value, update the
-- matching keyword there in lockstep.

-- Import wallust colors for dynamic glow
local colors = require("lua.colors")

-- Helper to convert hex color to 0xAARRGGBB format with alpha
local function glow_color(hex_color, alpha)
    -- Remove # if present
    hex_color = hex_color:gsub("^#", "")
    -- Convert to 0xAARRGGBB
    return "0x" .. alpha .. hex_color
end

hl.config({
    decoration = {
        -- Subtle time-driven glimmer sweeping across all outputs (see shaders/shimmer.frag).
        screen_shader = os.getenv("HOME") .. "/.config/hypr/shaders/shimmer.frag",
        rounding = 15,
        rounding_power = 8.0,
        active_opacity = 0.95,
        inactive_opacity = 0.8,
        fullscreen_opacity = 1.0,
        dim_modal = true,
        dim_inactive = true,
        dim_strength = 0.1,
        dim_special = 0.4,
        dim_around = 0.4,
        border_part_of_window = false,
        blur = {
            enabled = true,
            size = 6,
            passes = 2,
            new_optimizations = true,
            ignore_opacity = true,
            xray = true,
            noise = 0.01,
            contrast = 1.8,
            brightness = 0.8,
            vibrancy = 0.3,
            vibrancy_darkness = 0.1,
            popups = true,
            popups_ignorealpha = 0.1,
            input_methods = true,
            input_methods_ignorealpha = 0.1,
        },
        -- Glow effect using wallust colors (dynamic with theme changes)
        glow = {
            enabled = true,
            range = 5,
            render_power = 3,
            color = glow_color("FF6600", "FF"),        -- vivid orange (color9) for active
            color_inactive = glow_color(colors.color0, "22"), -- color0 with low alpha for inactive
        },
        -- Outer shadow for halo effect
        shadow = {
            enabled = true,
            range = 10,
            render_power = 3,
            color = glow_color("FF6600", "88"),
            color_inactive = glow_color("FF6600", "22"),
        },
    },
})
