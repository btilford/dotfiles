#!/bin/sh
# Shared selector for which bar/launcher Hyprland uses.
# Sourced by StartBar.sh and Launcher.sh — do not exec.
#
# Selection precedence:
#   1. shell.local.env (per-machine, gitignored, NOT stowed) — write overrides here
#   2. environment already exported into the session
#   3. built-in defaults below (quickshell throughout)
#
# quickshell is the default because it is what every machine here actually runs;
# the defaults had said waybar+rofi+swaync long after every host overrode all
# three, so a fresh clone came up as the legacy stack nothing was testing.
#
# waybar, rofi and swaync remain installed and configured, and this selector is
# how you get back to them — per machine, without touching the repo:
#   printf 'HYPR_BAR=waybar\nHYPR_LAUNCHER=rofi\nHYPR_NOTIFY=swaync\n' > ~/.config/hypr/shell.local.env

[ -f "$HOME/.config/hypr/shell.local.env" ] && . "$HOME/.config/hypr/shell.local.env"

HYPR_BAR="${HYPR_BAR:-quickshell}"
HYPR_LAUNCHER="${HYPR_LAUNCHER:-quickshell}"
# Which process owns org.freedesktop.Notifications. Only one can, so this is a
# selector, not a preference — see StartNotify.sh and quickshell's config/Shell.qml.
HYPR_NOTIFY="${HYPR_NOTIFY:-quickshell}"
