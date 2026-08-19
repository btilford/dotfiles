# waybar package

Context for AI agents working on this stow package. Not stowed (excluded by `.stow-local-ignore`).

## What this package manages

The waybar status bar config for Hyprland. Extracted from the `hyprland` package so it can be
stowed/unstowed independently — the first step toward toggling between waybar and quickshell.

Installs to `~/.config/waybar/`:

| File | Purpose |
|------|---------|
| `config.jsonc` | Bar modules and layout. Custom layout module runs `scripts/layout.sh`. |
| `style.css` | Entry stylesheet. `@import`s `wallust/colors-waybar.css` (runtime, wallust-generated) and `theme.css`. |
| `theme.css` | Static theme tokens. |
| `launch.sh` | Standalone launcher/reload helper (legacy; startup now goes through `hypr/scripts/StartBar.sh`). |
| `scripts/layout.sh` | Keyboard-layout indicator source. |
| `wallust/` | Runtime color output dir (`.gitkeep` tracked; generated `colors-waybar.css` ignored). |

## How it is launched

Hyprland does not run `waybar` directly. `hyprland/.config/hypr/scripts/StartBar.sh` selects the
bar from `$HYPR_BAR`. **`quickshell` is now the default**; set `HYPR_BAR=waybar` to come back here. Per-machine override in
`~/.config/hypr/shell.local.env` (not stowed). See the `hyprland` package.

## Rules

- No absolute paths — use `~`, `$HOME`, `$XDG_*`.
- Stow with `--no-folding` so `wallust/` stays a real dir and runtime color files coexist.
- Do not commit generated `wallust/colors-waybar.css`.
