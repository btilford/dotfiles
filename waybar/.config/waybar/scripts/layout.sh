#!/bin/bash
# Get current Hyprland layout
LAYOUT=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // .data // empty')

if [ -z "$LAYOUT" ] || [ "$LAYOUT" = "null" ]; then
    LAYOUT=$(hyprctl getoption general:layout 2>/dev/null | awk '{print $2}')
fi

# Map to friendly icons/names
case "$LAYOUT" in
    "master") echo "󰕴 master" ;;
    "dwindle") echo "󰕰 dwindle" ;;
    "scrolling") echo "󰕲 scrolling" ;;
    *) echo "$LAYOUT" ;;
esac
