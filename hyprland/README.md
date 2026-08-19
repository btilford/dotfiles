# Hyprland Dotfiles

Stow-managed Hyprland configuration for a multi-monitor AMD desktop with Nvidia/Intel laptop support.

## Verified Working Versions

| Package              | Version    |
| -------------------- | ---------- |
| hyprland             | 0.54.3     |
| awww                 | 0.12.0     |
| hypridle             | 0.1.7      |
| hyprlock             | 0.9.4      |
| hyprpaper            | 0.8.3      |
| hyprcursor           | 0.1.13     |
| hyprutils            | 0.12.0     |
| hyprlang             | 0.6.8      |
| aquamarine           | 0.10.0     |
| hyprgraphics         | 0.5.1      |
| waybar               | 0.15.0     |
| rofi                 | 2.0.0      |
| wallust              | 3.5.2      |
| ghostty              | 1.3.1      |
| swaync               | 0.12.6     |
| networkmanager-dmenu | 2.6.3      |
| wlogout              | 1.2.2      |
| nwg-dock-hyprland    | 0.4.8      |

## Stow Packages

| Package    | Contents                                  |
| ---------- | ----------------------------------------- |
| `hyprland` | Hyprland, Waybar, Rofi, wlogout, swaync   |
| `wallust`  | Wallust config + color templates          |

### Installing

```bash
cd ~/dotfiles
stow --no-folding hyprland
stow --no-folding wallust
```

## Structure

```text
hyprland/.config/hypr/
├── hyprland.conf           # Main entry point — sources all conf/ files
├── hypridle.conf           # Idle/sleep/lock timeouts
├── hyprlock.conf           # Lock screen layout
├── hyprpaper.conf          # Static wallpaper (unused — awww used instead)
├── pyprland.toml           # Pyprland plugin config
├── conf/
│   ├── animations/         # Animation presets (default/disabled/standard)
│   ├── decorations/        # Blur, shadows, opacity
│   ├── environments/       # Env vars (default + nvidia)
│   ├── keybindings/        # All key bindings
│   ├── layouts/            # Dwindle/master layout options
│   ├── monitors/           # Monitor configs (default/laptop/fwd)
│   ├── windowrules/        # Window and layer rules
│   └── workspaces/         # Named persistent workspace definitions
├── scripts/                # Helper shell scripts
├── shaders/                # GLSL screen shaders (blue light filter etc.)
├── themes/                 # Static color palette (fallback)
└── wallust/                # Runtime wallust-generated colors (git-ignored)

wallust/.config/wallust/
├── wallust.toml            # Wallust config + template mappings
└── templates/              # Color templates for each app
    ├── colors-hyprland.conf
    ├── colors-waybar.css
    ├── colors-rofi.rasi
    ├── colors-ghostty.conf
    └── colors-swaync.css
```

## Wallust Color Pipeline

Wallpaper changes every 30 minutes via `WallpaperAutoChange.sh`. Each change triggers `WallustSwww.sh` which runs wallust and regenerates colors for all apps:

```text
awww (wallpaper) → wallust run -s <image>
                        ↓ generates
~/.config/hypr/wallust/wallust-hyprland.conf   → Hyprland borders
~/.config/waybar/wallust/colors-waybar.css     → Waybar (imported in style.css)
~/.config/rofi/wallust/colors-rofi.rasi        → Rofi
~/.config/ghostty/wallust.conf                 → Ghostty palette
~/.config/swaync/wallust/colors-wallust.css    → SwayNC
```

Wallust template variables: `{{color0}}`–`{{color15}}`, `{{foreground}}`, `{{background}}`, `{{cursor}}`.
Filters: `| strip` removes `#` prefix, `| rgb` outputs `R,G,B` decimal.

## Key Bindings

| Binding          | Action                        |
| ---------------- | ----------------------------- |
| `Super+Return`   | Ghostty terminal              |
| `Super+B`        | Brave browser                 |
| `Super+R`        | Rofi launcher                 |
| `Super+Q`        | Kill window                   |
| `Super+F`        | Fullscreen                    |
| `Super+T`        | Toggle float + center         |
| `Super+L` (hjkl) | Move focus                    |
| `Super+Escape`   | wlogout menu                  |
| `Ctrl+Alt+L`     | Lock screen                   |
| `Super+E`        | Yazi file manager             |
| `Ctrl+Alt+V`     | Clipse clipboard manager      |
| `Super+Shift+B`  | Reload Waybar                 |
| `Super+0–9`      | Switch workspace              |
| `Super+F1–F3`    | Switch to XR1–XR3 (glasses)   |
| `Super+Shift+F1–F3` | Move window to XR1–XR3     |

## Waybar

- **Left-click network** → `networkmanager_dmenu` (rofi connection picker)
- **Right-click network** → `nm-connection-editor` (full GUI)
- **Right-click clock** → calendar popup (scroll to navigate months)
- **Left-click clock** → toggle time/date format
- Colors sourced from `wallust/colors-waybar.css` via `@import` in `style.css`

## Monitor Setup

4-monitor desk setup at 1.5x scale:

| Monitor          | Position         | Transform    |
| ---------------- | ---------------- | ------------ |
| Dell U3225QE     | center (primary) | landscape    |
| XPPen UGD MD180U | bottom center    | landscape    |
| Dell S2725QC     | left             | rotated 90°  |
| Dell S2725QC     | right            | rotated 270° |
| XREAL One Pro    | far right (x4000)| landscape    |

The XREAL One Pro is AR glasses, not a panel on the desk: a 1920x1080 virtual
display over DP alt-mode, driven at 120Hz and **scale 1** rather than 1.5 — a
downscale into 1080p optics costs sharpness where text is already hardest to
read. It is plugged in place of one of the USB-C sinks (the two portraits or the
tablet), so its position only has to avoid their slots. It gets three
non-persistent workspaces, XR1–XR3 (11–13), all scrolling with full-width
columns — see `lua/layout-auto.lua`.

Alternate configs in `conf/monitors/`: `laptop.conf` (1.0x scale), `fwd.conf` (no dock variant).

## Hardware Notes

### AMD (default)

No special configuration needed. Default `environments/default.conf` applies.

### Nvidia laptops

Source `conf/environments/nvidia.conf` from `hyprland.conf` for the Nvidia-specific env vars.
`hyprlock` uses `renderer = egl` which works correctly on Nvidia, AMD, and Intel.

### `awww` (replaces `swww`)

Arch Linux renamed `swww` → `awww` in March 2026. All scripts updated to use `awww`/`awww-daemon`.
Cache dir: `~/.cache/awww/` (created automatically on startup via `autostart.conf`).

## Known Issues & Notes

- **Wallust background color**: Ghostty uses a fixed `background = #1a1b26` rather than the wallust-generated background to ensure consistent text contrast across all wallpapers. Only the 16-color palette and foreground come from wallust.
- **Rofi transparency**: Base layer uses `rgba({{background | rgb}}, 0.3)` — adjust the alpha in `wallust/templates/colors-rofi.rasi` and re-run `wallust run -s <wallpaper>` to change.
- **pyprland**: Config present in `pyprland.toml` but package not currently installed. Install with `pacman -S pyprland` to enable scratchpad/expose/shift_monitors features.
- **SwayNC layerrules**: `name` must be the first key in any named block in Hyprland 0.54+.
