#!/usr/bin/env bash
# Sync every dark/light detection signal to one mode.
# Usage: SyncColorScheme.sh [Dark|Light]
# Defaults to the saved mode in ~/.cache/.theme_mode (Dark if unset).
#
# Signals covered:
#   - org.gnome.desktop.interface color-scheme — GTK apps and the gtk portal
#     backend, which serves org.freedesktop.portal.Settings for the
#     hyprland;gtk portal chain (electron/browsers detect through this)
#   - /org/freedesktop/appearance/color-scheme dconf key — unused by the gtk
#     backend but kept in sync so direct readers and a future kde portal agree
#   - kdeglobals via plasma-apply-colorscheme — KDE apps (Dolphin, Konsole);
#     writes the full [Colors:*] set and notifies running apps over D-Bus
#   - qt6ct color_scheme_path — pure Qt apps, picked up on app restart

mode="${1:-$(cat "$HOME/.cache/.theme_mode" 2> /dev/null)}"

case "$mode" in
  Light | light)
    mode="Light"
    scheme="prefer-light"
    kde_scheme="BreezeLight"
    qt6ct_colors="/usr/share/qt6ct/colors/airy.conf"
    ;;
  *)
    mode="Dark"
    scheme="prefer-dark"
    kde_scheme="BreezeDark"
    qt6ct_colors="/usr/share/qt6ct/colors/darker.conf"
    ;;
esac

gsettings set org.gnome.desktop.interface color-scheme "$scheme"
dconf write /org/freedesktop/appearance/color-scheme "'$scheme'"

if command -v plasma-apply-colorscheme > /dev/null 2>&1; then
  plasma-apply-colorscheme "$kde_scheme" > /dev/null
fi

qt6ct_conf="$HOME/.config/qt6ct/qt6ct.conf"
if [ -f "$qt6ct_conf" ]; then
  sed -i "s|^color_scheme_path=.*$|color_scheme_path=$qt6ct_colors|" "$qt6ct_conf"
fi

echo "$mode" > "$HOME/.cache/.theme_mode"
