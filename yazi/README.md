# yazi — terminal file manager

Stow package. `stow --no-folding yazi` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/yazi/yazi.toml` | manager, preview and **opener** rules |
| `.config/yazi/keymap.toml` | keybindings |
| `.config/yazi/theme.toml` | theme selection |
| `.config/yazi/init.lua` | header/status Lua customisation |
| `.config/yazi/package.toml` | `ya pkg` dependency lockfile |
| `.config/yazi/flavors/` | vendored flavors: `ashen`, `sunset` |

Hidden files shown, natural sort, 10-line scrolloff.

## Openers are the substance of `yazi.toml`

Long `[opener]` blocks per class (`play`, `edit`, …), each a *list* — yazi offers
the whole list on `O` and uses the first entry for plain `Enter`. `edit` starts
with `$EDITOR "$@"` so it follows the session's editor rather than hardcoding one.

Every entry is `for = "unix"`. The file is Linux-shaped: `audacity`, `vlc`,
`shotcut`, `kate` and the JetBrains launchers are all assumed on `PATH`. An entry
whose command is missing simply fails when picked — yazi does not filter the list.

## Flavors are vendored, and pinned

`package.toml` pins `PinThePenguinOne/sunset` and `ficcdaf/ashen` by revision
**and hash**. The flavor trees themselves are committed under `flavors/` rather
than fetched, so a fresh clone renders correctly with no network. Update with
`ya pkg upgrade`, which rewrites both the lockfile and the vendored tree —
review that diff, it is large.

Note stow ignores `README.*` and `LICENSE.*` by default, so the upstream flavor
docs in those directories are not symlinked into `~`. The flavor still works;
only its documentation is left behind.

## `init.lua`

Adds `user@host:` to the header and the hovered file's `user:group` to the status
line, both guarded on `ya.target_family() == "unix"`.

## Elsewhere

`nvim` opens yazi as a picker (`nvim/.config/nvim/lua/plugins/yazi.lua`), and
[`xdg/`](../xdg) makes `ghostty -e yazi` the `inode/directory` handler so
`xdg-open <dir>` lands here instead of in kitty.
