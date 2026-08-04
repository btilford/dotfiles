#!/bin/sh
# Bring up the notification daemon this machine selected with $HYPR_NOTIFY
# (see scripts/shell-env.sh; set it in ~/.config/hypr/shell.local.env).
#
# Only ONE process can own org.freedesktop.Notifications on the session bus, and
# the winner is whoever asks first. Autostart used to run `swaync` unconditionally
# alongside the qs daemon, so on a host with HYPR_NOTIFY=quickshell the two raced
# every login — swaync typically won by ~1s, quickshell's NotificationServer never
# got the name, and popups silently vanished while swaync's own drawer kept working.
#
# swaync also ships a D-Bus activation file (org.erikreider.swaync.service ->
# swaync.service, WantedBy=graphical-session.target), so it can be started by the
# first notify-send even when nothing execs it. Stopping and masking the unit is
# what actually keeps it out of the way; killing the process is not enough.

. "$HOME/.config/hypr/scripts/shell-env.sh"

case "$HYPR_NOTIFY" in
  quickshell | qs)
    # qs owns the name (its NotificationServer is gated on the same variable).
    # Clear any swaync left over from a previous session or D-Bus activation.
    systemctl --user stop swaync.service > /dev/null 2>&1
    systemctl --user mask swaync.service > /dev/null 2>&1
    pkill -x swaync > /dev/null 2>&1
    ;;
  swaync)
    systemctl --user unmask swaync.service > /dev/null 2>&1
    pgrep -x swaync > /dev/null 2>&1 || exec swaync
    ;;
  *)
    notify-send "StartNotify" "Unknown HYPR_NOTIFY='$HYPR_NOTIFY' (expected swaync|quickshell)" 2> /dev/null
    ;;
esac
