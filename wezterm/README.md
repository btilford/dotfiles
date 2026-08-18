# wezterm — GPU terminal emulator (cross-platform)

Stow package. `stow --no-folding wezterm` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/wezterm/wezterm.lua` | `~/.config/wezterm/wezterm.lua` |

Eleven lines, three of them commented out. `Darcula (base16)` colour scheme,
`JetBrains Mono`, everything else stock:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()
config.color_scheme = 'Darcula (base16)'
config.font = wezterm.font 'JetBrains Mono'
return config
```

Deliberately minimal — it is the fallback terminal that behaves identically on
macOS and Linux, not the one being tuned. ghostty is the session terminal (see
[`xdg/`](../xdg) for how that is enforced for `xdg-open`), and `tmux` handles
splits, so wezterm's own multiplexer is unused.

Two commented lines are worth knowing about before uncommenting either:

- `config.default_prog = { '/usr/bin/zellij', '-1' }` — an absolute path, so it
  would break on macOS. Use `zellij` unqualified if it comes back.
- `config.enable_wayland = false` — the old workaround for fractional scaling,
  which forces XWayland. Leave it off unless scaling is visibly wrong.

Config is Lua, reloaded live on save; a syntax error leaves the previous config
running rather than blanking the terminal.
