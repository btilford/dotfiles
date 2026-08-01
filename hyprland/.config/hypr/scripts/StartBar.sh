#!/bin/sh
# Start (or restart) the status bar selected by $HYPR_BAR. See shell-env.sh.
# Called from autostart.lua and bound to SUPER+SHIFT+B.

. "$HOME/.config/hypr/scripts/shell-env.sh"

case "$HYPR_BAR" in
  waybar)
    pkill -x waybar 2> /dev/null
    exec waybar
    ;;
  quickshell | qs)
    # The bar is a component of the single qs daemon — ensure it's running rather
    # than spawning a second qs. (The bar component lands in a later increment.)
    exec "$HOME/.config/hypr/scripts/StartShell.sh"
    ;;
  *)
    notify-send "StartBar" "Unknown HYPR_BAR='$HYPR_BAR' (expected waybar|quickshell)"
    ;;
esac
