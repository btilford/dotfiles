# helix — modal editor (secondary to nvim)

Stow package. `stow --no-folding helix` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/helix/config.toml` | `~/.config/helix/config.toml` |

Theme `base16_transparent` so the terminal background (and its opacity) shows
through. Relative line numbers, a ruler at 120, whitespace and indent guides
rendered, soft-wrap off, inline diagnostics on.

No language config here — `languages.toml` is absent, so helix uses its built-in
language servers as-is. `nvim` is the primary editor; this exists for quick edits
and for machines where the nvim plugin set has not been installed yet.
