#!/bin/sh
# Shared selector for which bar/launcher Hyprland uses.
# Sourced by StartBar.sh and Launcher.sh — do not exec.
#
# Selection precedence:
#   1. shell.local.env (per-machine, gitignored, NOT stowed) — write overrides here
#   2. environment already exported into the session
#   3. built-in defaults below (waybar + rofi)
#
# To switch to quickshell on a machine:
#   printf 'HYPR_BAR=quickshell\nHYPR_LAUNCHER=quickshell\n' > ~/.config/hypr/shell.local.env

[ -f "$HOME/.config/hypr/shell.local.env" ] && . "$HOME/.config/hypr/shell.local.env"

HYPR_BAR="${HYPR_BAR:-waybar}"
HYPR_LAUNCHER="${HYPR_LAUNCHER:-rofi}"
