# wezterm — GPU terminal emulator (cross-platform)

Stow package. `stow --no-folding wezterm` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/wezterm/wezterm.lua` | `~/.config/wezterm/wezterm.lua` |

Eleven lines of shared config, three of them commented out, plus a Windows-only block. `Darcula (base16)` colour scheme,
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

## Windows: opens straight into WSL

On Windows (`wezterm.target_triple` contains `windows`) the default domain is
the first WSL distro whose name starts with `Ubuntu`, matched by prefix so a
distro upgrade needs no edit and `podman-machine-default` is never picked. New
panes start in the WSL home (`default_cwd = "~"`) rather than the Windows cwd.
PowerShell and cmd are deliberately not configured.

There is no stow on Windows. Point WezTerm at the Windows checkout instead of
linking:

```powershell
setx WEZTERM_CONFIG_FILE "$env:USERPROFILE\dotfiles\wezterm\.config\wezterm\wezterm.lua"
```

Install from the official portable zip into `%LOCALAPPDATA%\Programs\WezTerm`
when winget has no per-user installer (`wez.wezterm` is machine-scope only, so
it needs UAC).
