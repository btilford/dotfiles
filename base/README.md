# base — cross-toolkit appearance and a couple of stray dotfiles

Stow package. `stow --no-folding base` from `~/dotfiles`.

| Path | Installs to | Purpose |
|------|-------------|---------|
| `.Xresources` | `~/.Xresources` | `Xcursor.theme: Bibata-Modern-Ice` — the XWayland cursor |
| `.gtkrc-2.0` | `~/.gtkrc-2.0` | GTK **2** theme/font/cursor (Breeze-Dark, breeze_cursors, Noto Sans 10) |
| `.config/qt6ct/qt6ct.conf` | `~/.config/qt6ct/qt6ct.conf` | Qt 6 style, palette, icon theme, fonts |
| `.config/xsettingsd/xsettingsd.conf` | `~/.config/xsettingsd/xsettingsd.conf` | the same settings again, over the XSETTINGS protocol |
| `.yarnrc.yml` | `~/.yarnrc.yml` | yarn supply-chain gate |

## Why the same theme is declared four times

There is no single place to set "the theme" for a Wayland session that also runs
XWayland clients. Each toolkit generation reads its own file and ignores the
others:

- **GTK 2** reads `~/.gtkrc-2.0` only.
- **GTK 3/4** read `~/.config/gtk-3.0/settings.ini` — **not in this package**;
  under Hyprland those are set through `gsettings`/portal by the `hyprland`
  package.
- **Qt 6** reads qt6ct when `QT_QPA_PLATFORMTHEME=qt6ct` is exported (the
  `hyprland` package's `environments.lua` does that).
- **XWayland/legacy X clients** get theirs from `xsettingsd`, and cursors from
  `.Xresources`.

Change the theme and you change it in all four, or one class of app goes light
while everything else is dark. `Gdk/UnscaledDPI 142540` in the xsettingsd file is
DPI × 1024 — that is the protocol's unit, not a typo.

## `.yarnrc.yml` is a supply-chain gate, not a preference

```yaml
npmMinimalAgeGate: 10080   # 7 days, in minutes
npmPreapprovedPackages: []
```

yarn refuses to install any npm release younger than a week, which is the window
in which a compromised-maintainer publish is normally caught and yanked. To take
a fresh release deliberately, add that one package to `npmPreapprovedPackages` —
do not lower the gate.

Note this is user-global: it applies to every yarn project on the machine.
