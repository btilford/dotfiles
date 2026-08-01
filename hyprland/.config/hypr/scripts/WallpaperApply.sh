#!/usr/bin/env bash
# Apply a wallpaper by full path — the apply half of the old WallpaperSelect.sh.
# Menu frontends call this with the chosen file: WallpaperSelect.sh (rofi) and the
# quickshell launcher's wallpaper mode. Images go to awww (all outputs), videos to
# mpvpaper; either way WallustSwww.sh runs at the end, which regenerates every
# wallust template and live-applies Hyprland colors (ApplyHyprColors.sh) — no reload.
#
# Usage: WallpaperApply.sh /full/path/to/wallpaper.{png,jpg,...,mp4,mkv,...}

SCRIPTSDIR="$HOME/.config/hypr/scripts"
iDIR="$HOME/.config/swaync/images"

# swww transition config
FPS=60
TYPE="any"
DURATION=2
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

selected_file="$1"

if [[ -z "$selected_file" || ! -f "$selected_file" ]]; then
  notify-send -i "$iDIR/error.png" "Wallpaper" "File not found: ${selected_file:-<none>}"
  exit 1
fi

# Kill existing wallpaper daemons for video
kill_wallpaper_for_video() {
  awww kill 2> /dev/null
  pkill mpvpaper 2> /dev/null
  pkill swaybg 2> /dev/null
  pkill hyprpaper 2> /dev/null
}

# Kill existing wallpaper daemons for image
kill_wallpaper_for_image() {
  pkill mpvpaper 2> /dev/null
  pkill swaybg 2> /dev/null
  pkill hyprpaper 2> /dev/null
}

modify_startup_config() {
  local selected_file="$1"
  local startup_config="$HOME/.config/hypr/UserConfigs/Startup_Apps.conf"

  # Machines without the JaKooLit-style startup config have nothing to persist here
  [[ -f "$startup_config" ]] || return 0

  # Check if it's a live wallpaper (video)
  if [[ "$selected_file" =~ \.(mp4|mkv|mov|webm)$ ]]; then
    # For video wallpapers:
    sed -i '/^\s*exec-once\s*=\s*awww-daemon\s*$/s/^/\#/' "$startup_config"
    sed -i '/^\s*#\s*exec-once\s*=\s*mpvpaper\s*.*$/s/^#\s*//;' "$startup_config"

    # Update the livewallpaper variable with the selected video path (using $HOME)
    selected_file="${selected_file/#$HOME/\$HOME}" # Replace /home/user with $HOME
    sed -i "s|^\$livewallpaper=.*|\$livewallpaper=\"$selected_file\"|" "$startup_config"

    echo "Configured for live wallpaper (video)."
  else
    # For image wallpapers:
    sed -i '/^\s*#\s*exec-once\s*=\s*awww-daemon\s*$/s/^\s*#\s*//;' "$startup_config"

    sed -i '/^\s*exec-once\s*=\s*mpvpaper\s*.*$/s/^/\#/' "$startup_config"

    echo "Configured for static wallpaper (image)."
  fi
}

# Apply Image Wallpaper
apply_image_wallpaper() {
  local image_path="$1"

  kill_wallpaper_for_image

  if ! pgrep -x "awww-daemon" > /dev/null; then
    echo "Starting awww-daemon..."
    awww-daemon &
  fi

  # No -o: apply to all outputs so every monitor/workspace shares the wallpaper
  awww img "$image_path" $SWWW_PARAMS

  # Run additional scripts (pass the image path to avoid cache race conditions)
  "$SCRIPTSDIR/WallustSwww.sh" "$image_path"
  sleep 2
  "$SCRIPTSDIR/Refresh.sh"
  sleep 1
}

apply_video_wallpaper() {
  local video_path="$1"

  # Check if mpvpaper is installed
  if ! command -v mpvpaper &> /dev/null; then
    notify-send -i "$iDIR/error.png" "E-R-R-O-R" "mpvpaper not found"
    return 1
  fi
  kill_wallpaper_for_video

  # Apply video wallpaper using mpvpaper
  mpvpaper '*' -o "load-scripts=no no-audio --loop" "$video_path" &
}

# Modify the Startup_Apps.conf file based on wallpaper type
modify_startup_config "$selected_file"

# **CHECK FIRST** if it's a video or an image **before calling any function**
if [[ "$selected_file" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
  apply_video_wallpaper "$selected_file"
else
  apply_image_wallpaper "$selected_file"
fi
