#!/bin/bash
# Wrapper for hyprctl dispatch calls from keybindings
exec hyprctl dispatch "$@"
