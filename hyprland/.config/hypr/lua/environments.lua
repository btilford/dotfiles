-- Environment Variables
-- name: "Default"

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("GDK_BACKEND", "wayland,x11")
-- Qt platform fallback list is ';'-separated, not ','. A comma makes Qt look for a single
-- plugin literally named "wayland,xcb" and fail (this broke quickshell). Semicolon = try
-- wayland, fall back to xcb.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")

hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")

hl.env("OZONE_PLATFORM", "wayland")

hl.env("wallpaper_path", os.getenv("HOME") .. "/wallpaper")

-- NVIDIA Settings
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
hl.env("__VK_LAYER_NV_optimus", "NVIDIA_only")
hl.env("EGL_PLATFORM", "wayland")
-- Alternative way to prevent 2nd cursor
hl.env("WLR_NO_HARDWARE_CURSORS", "1")

hl.config({
    cursor = {
        -- Prevent 2nd dead cursor at center of screen (sometimes)
        no_hardware_cursors = true,
    },
})
