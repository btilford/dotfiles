# waybar — status bar (legacy, being replaced by quickshell)

Stow package. `stow --no-folding waybar` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/waybar/config.jsonc` | modules and layout |
| `.config/waybar/style.css` | entry stylesheet |
| `.config/waybar/theme.css` | static theme tokens |
| `.config/waybar/launch.sh` | standalone launcher/reload helper (legacy) |
| `.config/waybar/scripts/layout.sh` | keyboard-layout indicator |
| `.config/waybar/wallust/` | runtime colour output (`.gitkeep` tracked) |

Extracted from the `hyprland` package so it can be stowed and unstowed
independently — the first step toward toggling between waybar and
[`quickshell`](../quickshell).

> Agent-facing notes: [`CLAUDE.md`](CLAUDE.md).

## How it is launched

Hyprland does **not** run `waybar` directly. `hypr/scripts/StartBar.sh` picks the
bar from `$HYPR_BAR`, and **the default is now `quickshell`** — every machine here
already overrode it, so the old `waybar` default only ever produced a stack
nobody was testing.

This package stays installed and configured as the fallback. To use it, per
machine and without touching the repo:

```sh
printf 'HYPR_BAR=waybar\n' >> ~/.config/hypr/shell.local.env
```

## Colours come from wallust

`style.css` `@import`s `wallust/colors-waybar.css`, written by
[`wallust`](../wallust) on every wallpaper switch. That file is generated —
excluded in `.stow-local-ignore` and `.gitignore`; only the `.gitkeep` is tracked.

Stow with `--no-folding` so `wallust/` stays a **real directory** and the runtime
colour file can coexist with the tracked ones. This is exactly the case folding
breaks.
