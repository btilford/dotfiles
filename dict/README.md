# dict — harper-ls user dictionary

Stow package. `stow --no-folding dict` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/harper-ls/dictionary.txt` | `~/.config/harper-ls/dictionary.txt` |

One word per line. Stops [harper](https://writewithharper.com/) — the grammar LSP
attached to markdown and comments in `nvim` — from flagging tool and language
names (`nvim`, `jdtls`, `treesitter`, `jsonc`, `lspconfig`, …) as misspellings.

Its own stow package rather than part of `nvim` because harper-ls is an editor-
independent language server: helix and any other LSP client read the same file.

Append to it rather than rewriting — harper's "add to dictionary" code action
writes to this same path, i.e. **through the stow symlink into the repo**, so new
entries show up as an ordinary diff.
