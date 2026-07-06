# rofi package

Context for AI agents working on this stow package. Not stowed (excluded by `.stow-local-ignore`).

## What this package manages

The active rofi launcher config for Hyprland. Extracted from the `hyprland` package so it can be
stowed/unstowed independently — the first step toward toggling between rofi and quickshell.

> History: this package previously held an unused gruvbox config. It was replaced by the KooL /
> wallust config that was actually in use (moved out of `hyprland`). The gruvbox theme is preserved
> as `themes/gruvbox-common.rasinc` (alternate, not active).

Installs to `~/.config/rofi/`:

| File | Purpose |
|------|---------|
| `config.rasi` | Main config. `@theme`s `themes/KooL_style-4.rasi`; `@import`s runtime `~/.config/rofi/host-dpi.rasi`. |
| `themes/KooL_style-4.rasi` | Active theme. |
| `themes/gruvbox-common.rasinc` | Retired gruvbox theme, kept as an alternate. |
| `wallust/colors-rofi.rasi` | wallust color output (`.gitkeep` tracked). |

## Runtime-generated files (NOT stowed / NOT committed)

- `host-dpi.rasi` — per-host DPI override written by `hypr/scripts/Launcher.sh` on each rofi launch
  (cachyos-fwd gets `dpi: 96`, others empty). Imported by `config.rasi`.
- `.current_wallpaper` — symlink managed by wallpaper scripts.

## How it is launched

Hyprland binds (`SUPER+R`, `SUPER+CTRL+RETURN`) call `hypr/scripts/Launcher.sh`, which selects the
launcher from `$HYPR_LAUNCHER` (`rofi` default, or `quickshell`). Override per-machine in
`~/.config/hypr/shell.local.env` (not stowed). See the `hyprland` package.

## Rules

- No absolute paths — use `~`, `$HOME`, `$XDG_*`.
- Stow with `--no-folding` so `themes/` and `wallust/` stay real dirs and runtime files coexist.
- Do not commit `host-dpi.rasi`, `.current_wallpaper`, or generated wallust output.
