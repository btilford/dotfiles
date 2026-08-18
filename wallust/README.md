# wallust — wallpaper-derived colour palettes

Stow package. `stow --no-folding wallust` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/wallust/wallust.toml` | `~/.config/wallust/wallust.toml` |
| `.config/wallust/templates/*` | `~/.config/wallust/templates/` |

`kmeans` backend, `labmixed` colour space, `softdark16` palette, contrast checking
on. Run on every wallpaper switch by the `hyprland` package's rotation script.

## This package writes into six other packages' directories

That is the whole point, and it is the source of most of this repo's "file the
repo does not own" rules. Every target below is **generated at runtime, never
committed**:

| Template | Target |
|----------|--------|
| `colors-hyprland.lua` | `~/.config/hypr/lua/colors.lua` |
| `colors-rofi.rasi` | `~/.config/rofi/wallust/colors-rofi.rasi` |
| `colors-waybar.css` | `~/.config/waybar/wallust/colors-waybar.css` |
| `colors-ghostty.conf` | `~/.config/ghostty/wallust.conf` |
| `colors-swaync.css` | `~/.config/swaync/wallust/colors-wallust.css` |
| `colors-quickshell.json` | `~/.config/quickshell/wallust/colors.json` |
| `colors-quickshell.json` | `~/.config/clipborg/colors.json` |

Each consuming package excludes its own target in `.stow-local-ignore` and
`.gitignore`, or keeps a `.gitkeep`-only directory for it. Two of those were
learned the hard way:

- **`hypr/lua/colors.lua` is a frozen seed, not an exclusion.** `lua/init.lua`
  does a bare `require("lua.colors")`, so a machine with no `colors.lua` does not
  fall back to defaults — Hyprland's config fails to load outright. It is tracked,
  stowed, and carries a `skip-worktree` bit (`.stow-frozen`).
- **`ghostty/wallust.conf` was tracked as an empty 0-byte file.** ghostty reads it
  if present, so re-stowing that package would have blanked the terminal palette.
  Now excluded.

`stow -R hyprland` will abort on `colors.lua` for exactly this reason — wallust
has replaced the symlink with a real file. Symlink new `hyprland` files by hand
rather than forcing a restow.

## Editing a template

The templates are wallust's own `{{colorN}}` syntax. After changing one, nothing
updates until wallust runs again — trigger a wallpaper switch, or run `wallust`
directly against the current wallpaper.

Hyprland's `disable_autoreload` is **true**, so writing `colors.lua` no longer
silently reloads the compositor. Lua edits need a deliberate `hyprctl reload`.
