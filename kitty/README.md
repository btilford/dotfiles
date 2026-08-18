# kitty — terminal emulator (secondary)

Stow package. **Currently not stowed on this machine, and not stowable as laid
out — see below.**

| Path in package | Where kitty actually reads it |
|-----------------|-------------------------------|
| `kitty.conf` | `~/.config/kitty/kitty.conf` |

## ⚠️ The package layout is wrong

Every stow package mirrors `$HOME`, so `kitty/kitty.conf` installs to
`~/kitty.conf` — a path kitty never reads. The file needs to move to
`kitty/.config/kitty/kitty.conf` before `stow --no-folding kitty` does anything
useful. Nothing is currently broken by it because the package has never been
stowed (`~/kitty.conf` does not exist), which is exactly why it went unnoticed.

## What is in it

JetBrainsMono Nerd Font 12, no window decorations, 0.7 background opacity
(dynamic), 2000 lines of scrollback, no audio bell, 10px padding.

kitty is not the session terminal — ghostty is (see [`xdg/`](../xdg), which exists
partly to stop kitty's `kitty-open.desktop` from claiming `inode/directory` and
hijacking every `xdg-open` on a folder). Keep that in mind before making this the
default anywhere.
