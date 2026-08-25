# terminator — tiling terminal (Linux, legacy)

Stow package. `stow --no-folding terminator` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/terminator/config` | `~/.config/terminator/config` |

**The config is an empty skeleton** — `[global_config]`, `[keybindings]`,
`[profiles]` and `[plugins]` are all present but hold nothing, and `[layouts]`
declares only the default single-window/single-terminal layout. Terminator runs
entirely on its built-in defaults.

The package exists to own the path: terminator **rewrites this file itself**
whenever preferences change in its GUI, through the stow symlink and into the
repo. Tracking the skeleton makes that rewrite a readable diff rather than an
untracked file appearing.

`config.bak` is terminator's own backup, not ours. Nothing consumes it, so it is
neither tracked nor stowed — the "excluded" tier from the root `CLAUDE.md`
section "Files the repo does not own". It is listed in `.gitignore` and in this
package's `.stow-local-ignore`, and terminator recreates it when it needs it.
It was tracked from the initial nix-to-stow import until 2026-08-20.

Superseded on this machine — tiling is Hyprland's job and multiplexing is tmux's.
Kept for Linux machines with no compositor config.
