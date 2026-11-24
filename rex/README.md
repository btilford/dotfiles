# rex

Config for [Rex](https://www.superlogical.com/rex/docs), modelled on
`tmux/.tmux.conf`: same prefix, same letters, a sesh-style picker, and
seamless nvim navigation.

## Where this config runs

Rex reads `~/.config/rex/init.lua` on the **server**. On Linux, the public
beta ships a server only. A client (Rex for Mac today) attaches to it, so the
keys below are pressed in the Mac app but resolved by this file.

Stow the package on every machine that runs a Rex server: the Arch box, and
the Mac if you use its local server.

```sh
stow --no-folding -t ~ rex
rex config check
rex config reload      # on the server machine; refused over a remote connection
```

The Arch package comes from the vendor pacman repo. Add it to `/etc/pacman.conf`
(or `/etc/pacman.d/rex.conf`) with the steps in the Rex Linux install docs, and
then `metapac sync`.

Machine-local additions go in `~/.config/rex/init.local.lua`. It is untracked,
loads last, and is matched by the reserved `*.local.*` ignore names.

## Files

| File | Purpose |
| --- | --- |
| `init.lua` | Loads the modules below, then `init.local.lua`. |
| `util.lua` | Vim detection, cwd lookup, the floating-popup helper. |
| `nav.lua` | `C-hjkl` and `M-hjkl`, vim-aware. |
| `popups.lua` | Actions: sesh picker, edit-output, tuicr, gh dash, clipborg, workmux, scratch. |
| `keys.lua` | The `C-b` prefix table. |
| `~/.local/bin/rex-sesh` | The picker that the sesh action runs. |

Every custom action is also in the command palette and on the CLI, for
example `rex do tuicr_popup`.

## Keys

No prefix:

| Key | Action |
| --- | --- |
| `C-h/j/k/l` | Focus a pane. In nvim, nvim gets the key first (see below). |
| `M-h/j/k/l` | Resize a pane. In nvim, nvim gets the key. |
| `cmd+k` | Clear the terminal, as in Ghostty. The session picker is on `C-b s`. |
| `M-r` | Reload the config. |
| `C-S-c` `C-S-v` | Copy and paste. |

`P`, `G`, `v`, `e` and `D` bind only when their tool is on the server's
`PATH`, as the `if-shell` guards in `.tmux.conf` do. Reload after you
install a tool.

After `C-b`:

| Key | tmux | Rex |
| --- | --- | --- |
| `c` `n` `,` `&` `1`–`9` | windows | tabs |
| `%` `"` | split | `pane.split` right / down |
| `z` `x` `o` `;` `!` `{` `}` `space` | panes | zoom, close, next, previous, break to tab, move, balance |
| `h/j/k/l` | select-pane | plain focus |
| `S` | sesh | sesh picker in the command palette |
| `C-s` | — | `rex-sesh` (fzf) in a floating layer |
| `s` `w` `$` `(` `)` | sessions | switch, rename, previous, next |
| `[` | copy-mode | copy mode (vi keys) |
| `f` | flash.tmux | Find (no label jump in Rex) |
| `]` | paste | paste clipboard |
| `r` | reload | `client.config.reload` |
| `p` | floax | floating scratch shell at the pane's cwd |
| `E` | edit-output.sh | scrollback in nvim, new tab |
| `P` `G` `v` | tuicr, gh dash, clipborg | the same tools, floating |
| `b` | workmux sidebar | Rex Activity sidebar |
| `e` `D` | workmux dashboard | workmux, floating |
| `C-b` | send-prefix | sends `C-b` |

## nvim navigation

The contract is the one tmux.nvim gives tmux:

1. Rex side (`nav.lua`): `C-h` in a pane whose foreground process is a vim is
   forwarded to vim with `pane.send_key`. In other panes, it moves Rex focus.
2. nvim side (`nvim/.config/nvim/lua/plugins/tmux.lua`): `C-h` moves between
   vim windows. At the edge, it runs `rex focus -s $REX_SESSION left`.

The nvim override applies only when `$REX_SESSION` is set and `$TMUX` is not.
tmux inside Rex keeps plain tmux.nvim behavior.

## Styling

Rex has no Lua API for appearance. The Mac app owns it. Settings that match
the tmux look:

| tmux | Rex for Mac setting |
| --- | --- |
| catppuccin mocha | Themes > Import Theme: a Ghostty `Catppuccin Mocha` theme file |
| `status-position top` | Interface > Tabs > Tab style: Above |
| orange active border | Interface > Active Pane > Highlight active pane edges, color from the palette |
| dim inactive (`window-style`) | Interface > Active Pane > Fade inactive panes |
| `pane-border-lines heavy` | Interface > Panes > Pane style: Compact |
| tmux-yank | Terminal > Selection > Copy on selection |
| prefix hints | Terminal > Keyboard > Show key sequence hints |
| `M-hjkl` on macOS | Terminal > Keyboard > Option key sends Alt |
| Ghostty `background-opacity` | Interface > Appearance > Interface style: Glass, and Use glass for panes (macOS 26 or later; hidden on macOS 15) |

The last four rows are set by one action. On each Mac, open the command
palette and run **Apply Dotfiles App Settings**.

## Not ported

- **flash.tmux**: Rex has Find, but no label jump.
- **workmux sidebar**: workmux drives tmux. Rex's Activity sidebar shows agent
  state from its own agent hooks and the program status protocol.
- **tmuxifier**: no layouts are defined. A layout in Rex is a Lua action that
  calls `rex.session.new_window` with `rex.layout.*`.
- **detach**: there is nothing to detach from. Close the app, and the server
  keeps the sessions.

## The sesh pickers

There are two. Both list live Rex sessions, then sesh.toml and zoxide
entries. Both reuse a session with the same label, or create one.

- `C-b S` (`sesh_pick`) uses `rex.ui.pick` in the command palette and needs no
  Remote Control. The palette has a fixed width and no preview pane.
- `C-b C-s` (`sesh`) runs `rex-sesh` with fzf and previews in a floating layer.
  It switches the app with `rex -C <client> do session.select`, which the app
  accepts only with Settings > Server > Client Info > Remote Control on.

**To check on Rex updates:** whether `rex.ui.pick` gets a preview pane or a
width option, or a config action can wait for a popup to exit. Either change
would let one picker have both the fzf look and the switch without Remote
Control.

## The server PATH

The server runs with launchd's or systemd's bare `PATH`. `util.lua` reads the
login shell's `PATH` once at load, and `u.exec` passes it to `rex.exec`. Call
`u.exec`, not `rex.exec`, for any tool outside `/usr/bin`.

## To do

- **A flash.nvim-style jump on `C-b f`.** The action reads the visible screen and
  lists its words and tokens in the command palette. Picking one enters copy
  mode and moves the cursor there with counted motions: `screen_top`, down N,
  `line_start`, right M. It needs no Remote Control. Labels on the screen, as
  flash.tmux draws them, need a floating replica and Remote Control.
