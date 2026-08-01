#!/usr/bin/env bash
# Apply wallust theme colors to the running Hyprland session via
# `hyprctl keyword` instead of `hyprctl reload`. A full reload resets
# runtime state (active workspaces, per-monitor layout switches, window
# arrangement); keywords change only the targeted options.
#
# Color source: ~/.config/hypr/lua/colors.lua — the same wallust target
# the lua config reads at parse time, so a later manual `hyprctl reload`
# converges to identical colors.
#
# Keep the keyword list below in sync with lua/decorations.lua and
# lua/windows.lua. Most values are pre-wired at the hardcoded ff6600
# defaults those files use today; only glow:color_inactive is dynamic.

set -uo pipefail

colors_file="$HOME/.config/hypr/lua/colors.lua"

# Quiet no-ops outside a live Hyprland session or before wallust ran
command -v hyprctl > /dev/null 2>&1 || exit 0
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || exit 0
[ -s "$colors_file" ] || exit 0

# Extract `colorN = "RRGGBB"` from colors.lua; fall back if missing/malformed
get_color() {
  local name="$1" fallback="$2" value
  value=$(sed -n "s/^\s*${name}\s*=\s*\"\([0-9A-Fa-f]\{6\}\)\".*/\1/p" "$colors_file" | head -n1)
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

# Fallbacks mirror lua/decorations.lua defaults
color0=$(get_color color0 "B9AEB2")

if ! hyprctl --batch "\
keyword decoration:glow:color_inactive rgba(${color0}22);\
keyword decoration:glow:color rgba(ff6600ff);\
keyword decoration:shadow:color rgba(ff660088);\
keyword decoration:shadow:color_inactive rgba(ff660022);\
keyword general:col.active_border rgba(ff6600ff);\
keyword general:col.inactive_border rgba(ff660022)" > /dev/null 2>&1; then
  command -v notify-send > /dev/null 2>&1 && notify-send -u low -a ApplyHyprColors \
    -h string:x-dunst-stack-tag:applyhyprcolors \
    "Hyprland colors" "Failed to apply theme colors via hyprctl" || true
fi

exit 0
