# xdg — freedesktop defaults (Linux)

Stow package. `stow --no-folding xdg` from `~/dotfiles`.

| Path | Purpose |
|------|---------|
| `.config/mimeapps.list` | default handlers — browser/scheme handlers plus `inode/directory` |
| `.config/xdg-terminals.list` | preferred emulators for `Terminal=true` desktop entries; ghostty first |
| `.local/share/applications/ghostty-yazi.desktop` | directory handler: `ghostty -e yazi %f` |

> Agent-facing notes: [`CLAUDE.md`](CLAUDE.md).

## Why the directory handler exists

kitty ships `kitty-open.desktop` (`kitty +open`) and it wins `inode/directory` by
default. Anything that calls `xdg-open` on a path then spawns **kitty**, not the
session's terminal — which is how clipborg's `open`-mode actions ended up in kitty
while its `terminal`-mode actions correctly used ghostty. Two different code
paths, and no `$TERMINAL` setting fixes the xdg-open one.

`ghostty-yazi.desktop` is `Terminal=false` **on purpose**: it launches the emulator
itself. A `Terminal=true` entry (like the stock `yazi.desktop`) hands the choice of
emulator back to xdg-open/gio — which is what put us in kitty to begin with.

## Two knobs, kept in sync

| Knob | Governs |
|------|---------|
| `$TERMINAL` (set in the `hyprland` package's `environments.lua`) | programs that spawn a terminal themselves |
| this package | `xdg-open` |

Neither affects the other.

## Editing

Changing `inode/directory` changes the **file manager for the whole session** —
browsers, chat apps, `xdg-open .`, everything.

After editing `.local/share/applications/`:

```sh
update-desktop-database ~/.local/share/applications
xdg-mime query default inode/directory
xdg-open ~/some-dir            # actually try it
```

The query can be right while the entry fails `TryExec`, so run the last line too.
