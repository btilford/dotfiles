# envman — envman PATH file

Stow package. `stow --no-folding envman` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/envman/PATH.env` | `~/.config/envman/PATH.env` |

**The file is empty, and that is the point.** Several installers (webi and
friends) source `~/.config/envman/PATH.env` from shell rc files and *create* it
with their own `export PATH=...` lines on first run. Tracking an empty one keeps
the path a repo-owned file so an installer's machine-specific PATH edit shows up
as a diff instead of appearing out of nowhere.

If a real value ends up here, it is machine-local by definition — move it to
`~/.config/dotfiles/local.env` (see the root README) rather than committing it.
