#!/usr/bin/env bash
# Enumerate theme icons for the launcher's icons mode.
# Output: one "name<TAB>path" per unique icon name; svg preferred over png.
# Scans the active icon theme (qt6ct, then gsettings, else hicolor) plus
# hicolor, pixmaps, and the user icon dir — not every installed theme.

theme=$(sed -n 's/^icon_theme=//p' "$HOME/.config/qt6ct/qt6ct.conf" 2> /dev/null | head -1)
[ -z "$theme" ] && theme=$(gsettings get org.gnome.desktop.interface icon-theme 2> /dev/null | tr -d "'")
[ -z "$theme" ] && theme=hicolor

dirs=()
for d in "/usr/share/icons/$theme" /usr/share/icons/hicolor /usr/share/pixmaps "$HOME/.local/share/icons"; do
  [ -d "$d" ] && dirs+=("$d")
done
[ ${#dirs[@]} -eq 0 ] && exit 0

# -L: themes symlink heavily (breeze aliases); first-seen wins in awk, so svg pass first
{
  find -L "${dirs[@]}" -type f -name '*.svg' 2> /dev/null
  find -L "${dirs[@]}" -type f -name '*.png' 2> /dev/null
} | awk -F/ '{
    n = $NF
    sub(/\.(svg|png)$/, "", n)
    if (!seen[n]++) printf "%s\t%s\n", n, $0
}' | sort
