#!/bin/sh
# Open the app launcher selected by $HYPR_LAUNCHER. See shell-env.sh.
# Bound to SUPER+R and SUPER+CTRL+RETURN.

. "$HOME/.config/hypr/scripts/shell-env.sh"

case "$HYPR_LAUNCHER" in
    rofi)
        # emoji mode maps to rofimoji on the rofi backend
        if [ "$1" = "emoji" ]; then
            exec rofimoji --action copy
        fi
        # glyphs mode: rofimoji over the same character sets the quickshell
        # glyphs.json is generated from (see quickshell scripts/gen-glyph-data.py)
        if [ "$1" = "glyphs" ]; then
            exec rofimoji --action copy --files math arrows general_punctuation \
                currency_symbols letterlike_symbols number_forms box_drawing \
                geometric_shapes dingbats miscellaneous_symbols \
                miscellaneous_technical latin-1_supplement \
                alphabetic_presentation_forms nerd_font
        fi
        # icons mode has no rofi equivalent
        if [ "$1" = "icons" ]; then
            notify-send "Launcher" "icons mode requires the quickshell backend"
            exit 1
        fi
        # (clip mode is gone: the clipboard is the standalone quickshell
        # ClipboardDialog now, bound directly to SUPER+V with its own clipborg TUI
        # fallback — it no longer routes through this script.)
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
        if ! command -v qs >/dev/null 2>&1; then
            notify-send "Launcher" "quickshell (qs) not found on PATH"
            exit 1
        fi
        # Ensure the shell daemon is up, then toggle the launcher. Optional mode arg
        # ($2: combi|drun|run|files) lets specific binds open a mode directly.
        "$HOME/.config/hypr/scripts/StartShell.sh"
        mode="${1:-combi}"
        # Retry while the daemon cold-starts (Qt init + desktop-entry scan can take a few
        # seconds on first launch; instant once the daemon is already up from autostart).
        i=0
        while [ "$i" -lt 40 ]; do
            qs ipc call launcher toggle "$mode" 2>/dev/null && exit 0
            i=$((i + 1))
            sleep 0.25
        done
        notify-send "Launcher" "quickshell launcher IPC not responding"
        ;;
    *)
        notify-send "Launcher" "Unknown HYPR_LAUNCHER='$HYPR_LAUNCHER' (expected rofi|quickshell)"
        ;;
esac
