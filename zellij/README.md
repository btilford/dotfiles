# zellij — terminal multiplexer (alternate to tmux)

Stow package. `stow --no-folding zellij` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/zellij/config.kdl` | `~/.config/zellij/config.kdl` |

## Fully custom keybindings

The config opens with `keybinds clear-defaults=true`, so **nothing** from zellij's
stock keymap survives — every binding in the file is the complete set. Adding a
mode means writing all of its bindings.

The layout is vim-shaped: `hjkl` movement in every mode, and `Ctrl g` returns to
`normal` from `locked`.

## Relationship to tmux

`tmux` is the multiplexer actually in use — `sesh` sessions, the popup bindings
(`prefix + P` tuicr, `prefix + G` gh-dash), and the visual-capture harness all
target it. zellij is kept for machines where tmux is not installed and for its
floating panes.

The two do not share a session or a socket. Nesting one in the other works but
doubles the prefix keys; pick one per terminal.
