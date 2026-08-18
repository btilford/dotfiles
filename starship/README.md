# starship — cross-shell prompt

Stow package. `stow --no-folding starship` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/starship.toml` | `~/.config/starship.toml` |

Powerline prompt on the `eyesaver` palette, `add_newline = false`, in five
segments: os · directory · git branch+status · docker context · shell/sudo
character.

Requires a Nerd Font — the segment separators are private-use glyphs and render
as tofu otherwise. JetBrainsMono Nerd Font is what the terminal packages here set.

## Init lives in the shell packages, not here

| Shell | File |
|-------|------|
| zsh | `zsh/.config/zshrc/20-starship` |
| nushell | `nushell/.config/nushell/starship.nu` (generated) |
| fish, bash | via their own rc files |

So unstowing this package leaves the shells calling a starship with no config
(defaults), not a broken prompt.
