#!/usr/bin/env bash
# List wallpapers for the quickshell launcher's wallpaper mode.
# Prints one "name<TAB>path<TAB>preview" line per wallpaper, sorted by name.
# Preview is a static image the launcher can thumbnail: the file itself for images,
# a cached first-frame PNG for gifs/videos (same caches WallpaperSelect.sh's rofi
# menu uses: ~/.cache/gif_preview and ~/.cache/video_preview), generated on miss.

PICTURES_DIR="$(xdg-user-dir PICTURES 2> /dev/null || echo "$HOME/Pictures")"
wallDIR="$PICTURES_DIR/wallpapers"

[[ -d "$wallDIR" ]] || exit 0

find -L "$wallDIR" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
  -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.webp" -o \
  -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \) -print0 |
  sort -z | while IFS= read -r -d '' pic_path; do
  pic_name=$(basename "$pic_path")
  preview="$pic_path"
  if [[ "$pic_name" =~ \.gif$ ]]; then
    preview="$HOME/.cache/gif_preview/${pic_name}.png"
    if [[ ! -f "$preview" ]]; then
      mkdir -p "$HOME/.cache/gif_preview"
      magick "${pic_path}[0]" -resize 1920x1080 "$preview" 2> /dev/null || preview=""
    fi
  elif [[ "$pic_name" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
    preview="$HOME/.cache/video_preview/${pic_name}.png"
    if [[ ! -f "$preview" ]]; then
      mkdir -p "$HOME/.cache/video_preview"
      ffmpeg -v error -y -i "$pic_path" -ss 00:00:01.000 -vframes 1 "$preview" 2> /dev/null || preview=""
    fi
  fi
  printf '%s\t%s\t%s\n' "$pic_name" "$pic_path" "$preview"
done
