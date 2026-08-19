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

## Status: fallback only, don't invest

**`HYPR_LAUNCHER` now defaults to `quickshell`**, so a fresh clone does not use
this package at all. quickshell's launcher covers every mode rofi does here, plus
`icons`, which has no rofi equivalent.

rofi stays installed and configured as the fallback. To use it, per machine:

```sh
printf 'HYPR_LAUNCHER=rofi\n' >> ~/.config/hypr/shell.local.env
```

`Launcher.sh` keeps its rofi branch, including the rofimoji mappings for `emoji`
and `glyphs` and the per-host DPI workaround. Full removal is a separate change —
it would also retire the rofi wallust template and cut the GPL-3.0 surface.

## Runtime files — generated, never committed

- `host-dpi.rasi` — per-host DPI override, written by `hypr/scripts/Launcher.sh`
  on **every** rofi launch, and `@import`ed by `config.rasi`.
- `wallust/colors-rofi.rasi` — written by [`wallust`](../wallust) on every
  wallpaper switch.
- `.current_wallpaper` — symlink managed by the wallpaper scripts.

All three are in `.stow-local-ignore`. Stow with `--no-folding` so `wallust/` and
the config dir stay real directories that runtime files can be written into.
