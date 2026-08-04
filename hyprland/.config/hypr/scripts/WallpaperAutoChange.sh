#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# source https://wiki.archlinux.org/title/Hyprland#Using_a_script_to_change_wallpaper_every_X_minutes

# This script will randomly go through the files of a directory, setting it
# up as the wallpaper at regular intervals
#
# NOTE: this script uses bash (not POSIX shell) for the RANDOM variable

wallust_refresh=$HOME/.config/hypr/scripts/RefreshNoWaybar.sh

focused_monitor=$(hyprctl monitors | awk '/^Monitor/{name=$2} /focused: yes/{print name}')

if [[ $# -lt 1 ]] || [[ ! -d $1 ]]; then
  echo "Usage:
	$0 <dir containing images>"
  exit 1
fi

# Edit below to control the images transition
export SWWW_TRANSITION_FPS=60
export SWWW_TRANSITION_TYPE=simple

# This controls (in seconds) when to switch to the next image
INTERVAL=1800
# INTERVAL=10

# Apply a wallpaper, retrying until the daemon is actually accepting connections.
#
# LOAD-BEARING at login. autostart.lua fires `awww-daemon` and this script as two
# separate async exec_cmd calls moments apart, so on a cold start this script
# reaches its first `awww img` before the daemon has created its socket. That call
# fails — and the ONLY sleep in the loop is the INTERVAL one *after* it, so the
# desktop then sits with no wallpaper for a full 30 minutes until the next
# iteration. Observed 2026-08-03: no wallpaper after login until one was picked by
# hand from the launcher.
#
# Retrying rather than waiting on a readiness probe keeps this independent of which
# subcommands awww happens to expose, and it also covers the daemon being restarted
# underneath a long-running loop. 10s is far longer than a cold start needs and
# still bounded, so a genuinely dead daemon cannot wedge the loop forever.
set_wallpaper() {
  local img=$1 tries=0
  until awww img "$img" 2> /dev/null; do
    tries=$((tries + 1))
    if ((tries >= 50)); then
      echo "WallpaperAutoChange: awww not responding after 10s, skipping $img" >&2
      return 1
    fi
    sleep 0.2
  done
}

while true; do
  find "$1" |
    while read -r img; do
      echo "$((RANDOM % 1000)):$img"
    done |
    sort -n | cut -d':' -f2- |
    while read -r img; do
      # swww img -o $focused_monitor "$img"
      # Only regenerate colours and refresh the UI if the wallpaper actually
      # applied — otherwise a failed set repaints everything to the wrong palette.
      if set_wallpaper "$img"; then
        # Regenerate colors from the exact image path to avoid cache races
        $HOME/.config/hypr/scripts/WallustSwww.sh "$img"
        # Refresh UI components that depend on wallust output
        $wallust_refresh
      fi
      sleep $INTERVAL

    done
done
