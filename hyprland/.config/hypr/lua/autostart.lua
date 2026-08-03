-- Autostart programs
-- Uses hl.exec_cmd() inside hl.on("hyprland.start") for proper async execution

hl.on("hyprland.start", function()
  -- Host detection (used for per-host config below).
  local hf = io.open("/etc/hostname", "r")
  local host = hf and hf:read("*l") or ""
  if hf then
    hf:close()
  end

  -- systemd graphical session bootstrap (Hyprland launched via start-hyprland, not uwsm).
  -- Activates graphical-session.target so xdg-desktop-portal can start. Without it the portal
  -- stays dead, GTK apps can't read portal settings, and fall back to stale gtk-xft-dpi in
  -- ~/.config/gtk-*.0/settings.ini (240 DPI) → huge fonts. Requires hyprland-session.target.
  hl.exec_cmd(
    "sh -c '"
      .. "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; "
      .. "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR; "
      .. "systemctl --user start hyprland-session.target'"
  )

  -- Wallpaper daemon (must come first for other components)
  hl.exec_cmd("awww-daemon")

  -- Status bar and notifications
  -- StartBar.sh picks waybar or quickshell based on $HYPR_BAR (see scripts/shell-env.sh).
  hl.exec_cmd('sh -c "$HOME/.config/hypr/scripts/StartBar.sh"')
  -- Bring up the quickshell daemon when any component (bar/launcher) selects quickshell.
  hl.exec_cmd('sh -c "$HOME/.config/hypr/scripts/StartShell.sh --if-selected"')
  hl.exec_cmd("swaync")

  -- System applets
  hl.exec_cmd("nm-applet")
  hl.exec_cmd("blueman-applet")

  -- Clipboard manager (clipborg; replaced cliphist/clipse) is NOT started here.
  -- It runs as clipborg.service, enabled and WantedBy=graphical-session.target.
  --
  -- Starting it from both places gave two daemons that each bind
  -- /run/user/1000/clipborg.sock. That does not fail: the second one unlinks the
  -- path and rebinds it, so BOTH keep listening — new connections reach the
  -- newer daemon while every client already connected keeps talking to the
  -- older one. Observed 2026-08-03: `clipborg llm --list` and a fresh socket
  -- both showed a newly configured prompt while the quickshell dialog did not,
  -- because it was still on a day-old daemon holding the previous config. They
  -- also both capture into the same sqlite db.
  --
  -- systemd owns it because that is where the unit's environment lives — the
  -- api keys arrive via EnvironmentFile drop-in, which an exec_cmd from here
  -- cannot reproduce.

  -- Idle/lock daemon — per-host config: hosts in nosuspend_hosts never call systemctl suspend.
  local nosuspend_hosts = { ["cachyos-fwd"] = true }
  local hypridle_cfg = nosuspend_hosts[host] and "hypridle.nosuspend.conf" or "hypridle.conf"
  hl.exec_cmd("hypridle -c " .. os.getenv("HOME") .. "/.config/hypr/" .. hypridle_cfg)

  -- VPN
  hl.exec_cmd("mullvad-vpn")
  -- netbird mesh gets its own tray item (SNI, rendered by the qs bar's Tray module);
  -- the quickshell Vpn singleton deliberately ignores netbird interfaces
  hl.exec_cmd('sh -c "command -v netbird-ui >/dev/null && exec netbird-ui"')

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

  -- GTK/XDG settings — color-scheme synced across gsettings/dconf/kdeglobals/qt6ct
  hl.exec_cmd('sh -c "$HOME/.config/hypr/scripts/SyncColorScheme.sh"')
  hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark")

  -- Wallpaper and theme scripts
  hl.exec_cmd('sh -c "$HOME/.config/hypr/scripts/Hyprsunset.sh init"')
  hl.exec_cmd(
    'sh -c "$HOME/.config/hypr/scripts/WallpaperAutoChange.sh $HOME/Pictures/wallpapers/"'
  )

  -- Element messenger
  hl.exec_cmd("element-desktop")

  -- OpenCode vault server (cachyos-fwd only — vault lives here)
  if host == "cachyos-fwd" then
    hl.exec_cmd(
      "fish -c 'cd ~/Documents/personal-notes/notes && opencode serve --hostname 0.0.0.0 --port 4096'"
    )
  end
end)
