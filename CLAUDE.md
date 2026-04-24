# Dotfiles

Stow-managed dotfiles for btilford. Each top-level directory is a stow package mirroring `$HOME`.

## Rules

- No absolute paths in configs — use `~`, `$HOME`, or `$XDG_*` vars
- Local machine-specific config lives outside the repo, not in stow packages
- Cross-platform: macOS + Linux. Platform-specific packages are isolated
- Always stow one package at a time with `--no-folding` to prevent directory symlinking and protect local-only files

## Structure

- **Cross-platform**: `bash`, `fish`, `zsh`, `nvim`, `tmux`, `git`, `starship`, `yazi`, `lazygit`, `helix`, `zellij`, `wezterm`
- **macOS-only**: `ghostty`, `macos`
- **Linux-only**: `hyprland`, `rofi`, `konsole`, `konsole`, `kmonad`, `terminator`, `yakuake`, `brave-linux`
- **Shared base**: `base`

## Branches

- `master` — main
- `macos` — macOS-specific work
