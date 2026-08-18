# yakuake — drop-down terminal (Linux/KDE)

Stow package. `stow --no-folding yakuake` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/yakuakerc` | `~/.config/yakuakerc` |

| Section | What is set |
|---------|-------------|
| `[Animation]` | `Frames=0` — drop-down is instant, no slide |
| `[Appearance]` | `transparent-tabs` skin, borders hidden, translucent at 30% opacity, blur off |
| `[Window]` | 75% width × 42% height at position 46, dynamic tab titles, toggle-to-focus |
| `[Shortcuts]` | `Ctrl+W` close terminal, `Ctrl+Tab` / `Ctrl+Shift+Tab` cycle, `Ctrl+Shift+E`/`L` and `Ctrl+Shift+O`/`B` split |

`Blur=false` is a decision, not an oversight — the comment in the file records
that KWin's blur and yakuake's translucency do not compose well.

## Two things this file does NOT control

- **The global drop-down key** (F12 by default) is a KDE global shortcut and lives
  in `kglobalshortcutsrc`, which is not tracked here. A fresh machine gets the
  default until it is rebound in System Settings.
- **Font and colours** come from the konsole profile — yakuake embeds konsole's
  terminal part. See [`konsole/`](../konsole).

Legacy on this machine: the Hyprland session uses `quickshell` surfaces and
ghostty. Kept for KDE/Plasma machines. yakuake rewrites this file from its own
settings dialog, through the symlink into the repo.
