#!/bin/sh
# Start (or restart) the status bar selected by $HYPR_BAR. See shell-env.sh.
# Called from autostart.lua and bound to SUPER+SHIFT+B.

. "$HOME/.config/hypr/scripts/shell-env.sh"

case "$HYPR_BAR" in
    waybar)
        pkill -x waybar 2>/dev/null
        exec waybar
        ;;
    quickshell|qs)
        pkill -x qs 2>/dev/null
        if command -v qs >/dev/null 2>&1; then
            exec qs
        else
            notify-send "StartBar" "quickshell (qs) not found on PATH"
        fi
        ;;
    *)
        notify-send "StartBar" "Unknown HYPR_BAR='$HYPR_BAR' (expected waybar|quickshell)"
        ;;
esac
