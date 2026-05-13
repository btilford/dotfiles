-- Autostart programs
-- Uses hl.exec_cmd() inside hl.on("hyprland.start") for proper async execution

hl.on("hyprland.start", function()
    -- Wallpaper daemon (must come first for other components)
    hl.exec_cmd("awww-daemon")

    -- Status bar and notifications
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")

    -- System applets
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("blueman-applet")

    -- Clipboard manager
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Idle/lock daemon
    hl.exec_cmd("hypridle")

    -- App launcher helpers
    hl.exec_cmd("clipse")

    -- VPN
    hl.exec_cmd("mullvad-vpn")

    -- USB automount
    hl.exec_cmd("udiskie --no-tray")

    -- Dock
    -- hl.exec_cmd("nwg-dock-hyprland")

    -- Polkit agent
    hl.exec_cmd("/usr/lib/polkit-kde-agent/polkit-kde-authentication-agent-1")

    -- KWallet and KDED6
    hl.exec_cmd("kwalletd6")
    hl.exec_cmd("kded6")

    -- GNOME keyring
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")

    -- GTK/XDG settings
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark")

    -- Wallpaper and theme scripts
    hl.exec_cmd("sh -c \"$HOME/.config/hypr/scripts/Hyprsunset.sh init\"")
    hl.exec_cmd("sh -c \"$HOME/.config/hypr/scripts/WallpaperAutoChange.sh $HOME/Pictures/wallpapers/\"")

    -- Element messenger
    hl.exec_cmd("element-desktop")
end)
