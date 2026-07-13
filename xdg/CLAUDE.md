# xdg package

Context for AI agents working on this stow package. Not stowed (excluded by `.stow-local-ignore`).

## What this package manages

Freedesktop defaults — which app handles which mime type, and which terminal
emulator gets used when something has to spawn one.

| Path | Purpose |
|------|---------|
| `.config/mimeapps.list` | Default handlers. Browser/scheme handlers plus `inode/directory`. |
| `.config/xdg-terminals.list` | Preferred emulators for `Terminal=true` desktop entries (xdg-terminal-exec spec). ghostty first. |
| `.local/share/applications/ghostty-yazi.desktop` | Directory handler: `ghostty -e yazi %f`. |

## Why the directory handler exists

kitty ships `kitty-open.desktop` (`kitty +open`) and it wins `inode/directory` by
default. Anything that calls `xdg-open` on a path then spawns **kitty**, not the
session's terminal — this is what made clipborg's `open`-mode actions appear in
kitty while its `terminal`-mode actions correctly used ghostty. The two are
different code paths and no `$TERMINAL` setting fixes the xdg-open one.

`ghostty-yazi.desktop` is `Terminal=false` on purpose: it launches the emulator
itself. A `Terminal=true` entry (like the stock `yazi.desktop`) hands the choice
of emulator back to xdg-open/gio, which is how we ended up in kitty in the first
place.

## Rules

- **Changing `inode/directory` changes the file manager for the whole session**, not
  just clipborg. Anything that opens a folder (browsers, chat apps, `xdg-open .`)
  goes through it.
- After editing `.local/share/applications/`, run
  `update-desktop-database ~/.local/share/applications` or the entry won't resolve.
- Verify with `xdg-mime query default inode/directory`, then actually
  `xdg-open ~/some-dir` — the query can be right while the entry fails `TryExec`.
- `$TERMINAL` (set in the `hyprland` package's `environments.lua`) governs programs
  that spawn a terminal themselves. It does **not** affect xdg-open. Keep both in sync.
