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
  -- Notification daemon per $HYPR_NOTIFY. NOT an unconditional `swaync`: only one
  -- process can own org.freedesktop.Notifications, and starting swaync here raced
  -- the qs daemon on hosts set to quickshell — swaync won, so quickshell popups
  -- never appeared while swaync's drawer kept working.
  hl.exec_cmd('sh -c "$HOME/.config/hypr/scripts/StartNotify.sh"')

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

  -- Polkit agent: the systemd unit first, scripts/Polkit.sh (which probes a list of
  -- known agent paths) as fallback.
  --
  -- This was previously a hardcoded
  -- "/usr/lib/polkit-kde-agent/polkit-kde-authentication-agent-1", which is not
  -- where Arch puts it -- polkit-kde-agent ships /usr/lib/polkit-kde-authentication-agent-1,
  -- with no polkit-kde-agent/ directory. So the path never existed, no agent ever
  -- started, and EVERY polkit prompt on this host failed silently: no error, no
  -- window, the calling app simply reports polkit missing or hangs. Found 2026-09-01
  -- via Bazecor, which pkexecs to install its udev rule.
  --
  -- A hardcoded path is what caused this, so do not reintroduce one; the agent
  -- location differs across distros and across KDE/GNOME builds.
  --
  -- polkit-kde-agent ships plasma-polkit-agent.service, but it is a STATIC user unit:
  -- it cannot be `systemctl --user enable`d, and Plasma normally pulls it in through
  -- plasma-workspace.target, which nothing does here. Starting it explicitly is the
  -- deterministic option and matches the KDE bits already started below (kwalletd6,
  -- kded6). Polkit.sh is only the fallback -- it probes a list whose FIRST hit on this
  -- host is the gnome agent, and two agents registering for one session is a worse
  -- failure than none.
  hl.exec_cmd(
    "sh -c 'systemctl --user start plasma-polkit-agent.service "
      .. "|| exec $HOME/.config/hypr/scripts/Polkit.sh'"
  )

  -- KWallet and KDED6
  hl.exec_cmd("kwalletd6")
  hl.exec_cmd("kded6")

  -- Unlock the wallet from the password PAM already captured at login.
  --
  -- ksecretd is D-Bus activated and therefore needs no autostart of its own — it
  -- starts on demand in any session. (It no longer owns org.freedesktop.secrets
  -- either; see the gnome-keyring note below.) What does NOT happen on its own is
  -- the unlock: pam_kwallet5.so writes the login password to a socket at session
  -- time, and something must then run pam_kwallet_init to hand it over. Plasma
  -- does that via this unit; Hyprland has no equivalent, and /etc/xdg/autostart
  -- is not read here either. That is the whole reason the
  -- keyring felt "hit or miss" — it worked only when something had already
  -- prompted earlier in the session.
  --
  -- `static` means it cannot be enabled, but it can be started, which is the
  -- supported shape for a unit a session activates. Starting an already-active
  -- unit is a no-op, so this stays harmless in a KDE session where Plasma
  -- started it.
  --
  -- NOTE: this does not cover dotfiles-secrets.service. That unit reaches
  -- default.target before Hyprland runs its first exec_cmd, so it declares its own
  -- Wants=/After= on this unit instead. This line is for everything else in the
  -- session that wants an unlocked wallet.
  hl.exec_cmd("systemctl --user start plasma-kwallet-pam.service")

  -- gnome-keyring: nothing is started here, and it is now masked outright.
  --
  -- This comment used to say the package was not installed, and to warn that
  -- pulling it in would race ksecretd for org.freedesktop.secrets. It got pulled
  -- in (bitwarden, fractal, jetbrains-toolbox and qtkeychain-qt6 all depend on the
  -- virtual org.freedesktop.secrets), and it won the name — not by racing, but
  -- because it ships the ONLY activation file for that name in /usr/share.
  -- kwallet ships none, so the outcome was never in doubt.
  --
  -- Resolved deliberately, in two halves:
  --   * the xdg package ships ~/.local/share/dbus-1/services/
  --     org.freedesktop.secrets.service, naming ksecretd. XDG_DATA_HOME precedes
  --     XDG_DATA_DIRS, so it wins.
  --   * per machine, not committable:
  --       systemctl --user mask gnome-keyring-daemon.socket gnome-keyring-daemon.service
  --     Keep the masks even after the package is removed. They are what stops this
  --     coming back if something pulls gnome-keyring in again.
  --
  -- ksecretd still needs no exec line: D-Bus activates it on the first request and
  -- it then owns both org.freedesktop.secrets and org.kde.secretservicecompat.
  -- Adding a second start path is what would recreate the race.
  --
  -- Confirm the owner with:
  --   busctl --user list | grep org.freedesktop.secrets

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
