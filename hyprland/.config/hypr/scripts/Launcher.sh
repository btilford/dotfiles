#!/bin/sh
# Open the app launcher selected by $HYPR_LAUNCHER. See shell-env.sh.
# Bound to SUPER+R and SUPER+CTRL+RETURN.

. "$HOME/.config/hypr/scripts/shell-env.sh"

case "$HYPR_LAUNCHER" in
    rofi)
        # Per-host rofi DPI: cachyos-fwd drives 4K @ scale 1.5, where rofi auto-DPI
        # (~122) stacks on the compositor scale and renders oversized. Other hosts get
        # no override. Imported by config.rasi via @import "~/.config/rofi/host-dpi.rasi".
        host=$(cat /etc/hostname 2>/dev/null)
        if [ "$host" = "cachyos-fwd" ]; then
            printf 'configuration { dpi: 96; }\n' > "$HOME/.config/rofi/host-dpi.rasi"
        else
            : > "$HOME/.config/rofi/host-dpi.rasi"
        fi
        pkill rofi || rofi -show drun -replace -i
        ;;
    quickshell|qs)
        # TODO: wire to the quickshell launcher once its config exists.
        if command -v qs >/dev/null 2>&1; then
            qs ipc call launcher toggle 2>/dev/null \
                || notify-send "Launcher" "quickshell launcher IPC not wired up yet"
        else
            notify-send "Launcher" "quickshell (qs) not found on PATH"
        fi
        ;;
    *)
        notify-send "Launcher" "Unknown HYPR_LAUNCHER='$HYPR_LAUNCHER' (expected rofi|quickshell)"
        ;;
esac
