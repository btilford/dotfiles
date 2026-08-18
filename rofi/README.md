# rofi — application launcher (legacy, being replaced by quickshell)

Stow package. `stow --no-folding rofi` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/rofi/config.rasi` | main config |
| `.config/rofi/themes/KooL_style-4.rasi` | active theme |
| `.config/rofi/themes/gruvbox-common.rasinc` | retired theme, kept as an alternate |
| `.config/rofi/wallust/` | runtime colour output (`.gitkeep` tracked) |

Extracted from the `hyprland` package so it can be stowed and unstowed
independently — the first step toward toggling between rofi and
[`quickshell`](../quickshell), whose launcher now covers the same modes.

> Agent-facing notes: [`CLAUDE.md`](CLAUDE.md).

## Status: keep it limping, don't invest

quickshell's launcher is the one being developed. rofi stays as a fallback for
machines where quickshell is not running. Full removal is a future plan.

## Runtime files — generated, never committed

- `host-dpi.rasi` — per-host DPI override, written by `hypr/scripts/Launcher.sh`
  on **every** rofi launch, and `@import`ed by `config.rasi`.
- `wallust/colors-rofi.rasi` — written by [`wallust`](../wallust) on every
  wallpaper switch.
- `.current_wallpaper` — symlink managed by the wallpaper scripts.

All three are in `.stow-local-ignore`. Stow with `--no-folding` so `wallust/` and
the config dir stay real directories that runtime files can be written into.
