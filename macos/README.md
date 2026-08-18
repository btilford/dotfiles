# macos — macOS-only bootstrap and window management

Stow package. macOS only. `stow --no-folding macos` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.aerospace.toml` | `~/.aerospace.toml` |
| `Library/KeyBindings/DefaultKeyBinding.dict` | `~/Library/KeyBindings/DefaultKeyBinding.dict` |
| `init.sh` | *(not stowed — a script you run once)* |

**AeroSpace** is the tiling window manager — the closest macOS gets to the
Hyprland layout on Linux, with workspaces and keyboard-driven focus rather than
Spaces.

**`DefaultKeyBinding.dict`** is a Cocoa text-system keybinding table, applied to
every AppKit text field on the machine. It is the only way to get Emacs/readline
motions into native apps; nothing about it is per-app.

## `init.sh` is a one-shot record, not an installer to run blind

It is a flat list of `brew install` lines from the original machine setup. Read it
before running:

- It has a typo on the first line (`brew isntall --cask ghostty`), which will fail
  and — because the script has no `set -e` — be skipped silently.
- Several formulae in it are stale (`exa` is unmaintained; `eza` replaced it).
- It predates [`metapac`](../metapac), which is now the declarative source of
  truth for packages on both platforms. `macos.toml` there is the list to trust.

Treat `init.sh` as history. Add packages to `metapac/.config/metapac/groups/macos.toml`.

## Also needed on a Mac

metapac reads its config from `~/Library/Application Support/metapac/`, not XDG,
and silently loads an **empty default** otherwise — every backend disabled, so
everything reads "clean". Bridge it once per machine:

```sh
ln -s ~/.config/metapac ~/"Library/Application Support/metapac"
```
