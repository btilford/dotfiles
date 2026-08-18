# tmux — terminal multiplexer

Stow package. `stow --no-folding tmux` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.tmux.conf` | `~/.tmux.conf` |
| `.config/sesh/sesh.example.toml` | `~/.config/sesh/sesh.example.toml` |

`tmux-256color`, passthrough on, vi copy mode, mouse on, 50k scrollback,
`detach-on-destroy off`, activity monitored without the visual flash.

`focus-events on` and `escape-time 10` are both there **for nvim** — the first
makes `autoread`/`FocusGained` fire, the second undoes tmux-sensible's 500 ms Esc
delay, which otherwise reads as lag in every mode change.

## Popups (cwd-pinned, guarded)

| Key | Opens |
|-----|-------|
| `prefix + P` | [`tuicr`](../tuicr) — review the current repo |
| `prefix + G` | [`gh dash`](../gh-dash) |
| `prefix + v` | `clipborg tui` (Linux only) |
| `prefix + E` | `edit-output.sh` — pipe the pane's output into an editor |
| `prefix + D` | workmux diff |
| `prefix + b` | sidebar |

Each is wrapped in `if-shell 'command -v <tool>'`, so a machine without the tool
gets no binding rather than a popup that flashes and dies. All are pinned with
`-d '#{pane_current_path}'` so they act on the pane's repo, not the session's.

`C-hjkl` is bound **without** the prefix for pane movement; nvim handles its own
side of that split via `aserowy/tmux.nvim`.

## Plugins, and one that cannot be disabled by commenting

Managed by `tpm`. Note the comment in the file: **commenting out a `@plugin` line
does not disable the plugin.** tpm sources every directory under its plugin path,
so a plugin keeps rebinding keys and starting its daemon until the *directory* is
removed. `snirt/tmux-agents-mon` is commented only so tpm stops reinstalling it;
its bindings are set here instead.

## `sesh.toml` lives in the private repo

Only `sesh.example.toml` is here. The real session list names work directories and
client projects, so it is stowed from `private-dotfiles` (`sesh/` package). This
was found the hard way — work sessions re-entered the tracked file on `master`
past every gate, which is why `~/.config/dotfiles/scrub.patterns` now exists.

## Testing a branch's config

```sh
tmux -L <private-socket> -f ~/dotfiles/tmux/.tmux.conf
```

Never test on the default socket: the live server holds real work and other
agents' sessions.
