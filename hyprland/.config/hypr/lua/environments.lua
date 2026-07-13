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

-- Terminal for anything that spawns one from the session (clipborg's terminal-mode
-- actions, scripts that honour $TERMINAL). xdg-open does NOT read this — directories
-- and Terminal=true handlers are governed by the `xdg` package's mimeapps.list.
hl.env("TERMINAL", "ghostty")

-- QML modules that live outside ~/.config/quickshell. The clipborg repo ships the
-- ClipboardDialog as a `Clipborg` QML module; our components/ClipboardDialog.qml is a
-- thin wrapper that imports it, so the qs daemon needs the repo's examples/quickshell
-- dir on the import path. Point CLIPBORG_QML_PATH at your clone (environment.d/uwsm)
-- if it isn't in the default location; a missing path is harmless — quickshell loads
-- the wrapper through a LazyLoader, so the dialog is the only thing that fails.
local clipborg_qml = os.getenv("CLIPBORG_QML_PATH")
    or (os.getenv("HOME") .. "/Projects/public/clipborg/examples/quickshell")
local qml_paths = os.getenv("QML_IMPORT_PATH")
-- `hyprctl reload` re-runs this file with the env we set last time already exported,
-- so appending unconditionally stacks a duplicate path on every reload.
if not qml_paths or qml_paths == "" then
    qml_paths = clipborg_qml
elseif not string.find(qml_paths, clipborg_qml, 1, true) then
    qml_paths = qml_paths .. ":" .. clipborg_qml
end
hl.env("QML_IMPORT_PATH", qml_paths)

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
