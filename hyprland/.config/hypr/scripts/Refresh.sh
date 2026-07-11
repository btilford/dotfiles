#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Scripts for refreshing ags, waybar, rofi, swaync, wallust

SCRIPTSDIR=$HOME/.config/hypr/scripts
UserScripts=$HOME/.config/hypr/UserScripts

# Which bar this machine runs (waybar|quickshell) — only manage waybar when
# it's the active bar; the quickshell bar watches its wallust files itself.
. "$SCRIPTSDIR/shell-env.sh"

# Define file_exists function
file_exists() {
  if [ -e "$1" ]; then
    return 0 # File exists
  else
    return 1 # File does not exist
  fi
}

# Kill already running processes
_ps=(rofi swaync ags)
[ "$HYPR_BAR" = "waybar" ] && _ps+=(waybar)
for _prs in "${_ps[@]}"; do
  if pidof "${_prs}" >/dev/null; then
    pkill "${_prs}"
  fi
done

if [ "$HYPR_BAR" = "waybar" ]; then
  # added since wallust sometimes not applying
  killall -SIGUSR2 waybar
  # Added sleep for GameMode causing multiple waybar
  sleep 0.1
fi

# quit ags & relaunch ags
#ags -q && ags &

# quit quickshell & relaunch quickshell
#pkill qs && qs &

# some process to kill
for pid in $(pidof rofi swaync ags swaybg); do
  kill -SIGUSR1 "$pid"
  sleep 0.1
done

# Restart waybar only when it's the active bar
if [ "$HYPR_BAR" = "waybar" ]; then
  sleep 0.1
  waybar &
fi

# relaunch swaync
sleep 0.3
swaync >/dev/null 2>&1 &
# reload swaync
swaync-client --reload-config

# Relaunching rainbow borders if the script exists
sleep 1
if file_exists "${UserScripts}/RainbowBorders.sh"; then
  ${UserScripts}/RainbowBorders.sh &
fi

exit 0
