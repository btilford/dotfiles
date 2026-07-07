#!/bin/sh
# Ensure exactly one quickshell (qs) daemon is running. Idempotent.
# The qs daemon hosts all shell components (launcher now; bar/notifs/etc. later).
#
# With --if-selected, only start when $HYPR_BAR or $HYPR_LAUNCHER selects quickshell
# (used from autostart so the daemon comes up when any component needs it).

if [ "$1" = "--if-selected" ]; then
    . "$HOME/.config/hypr/scripts/shell-env.sh"
    case "$HYPR_BAR:$HYPR_LAUNCHER" in
        *quickshell*) ;;
        *) exit 0 ;;
    esac
fi

command -v qs >/dev/null 2>&1 || {
    notify-send "quickshell" "qs not found on PATH" 2>/dev/null
    exit 1
}

# Force QT_QPA_PLATFORM=wayland: the session sets "wayland,xcb" (environments.lua), but
# quickshell's Qt build treats the comma-list as a single plugin name and dies with
# "Could not find the Qt platform plugin 'wayland,xcb'". qs only runs under Wayland anyway.
pgrep -x qs >/dev/null 2>&1 || QT_QPA_PLATFORM=wayland setsid -f qs >/dev/null 2>&1
