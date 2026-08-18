# lazygit — git TUI

Stow package. `stow --no-folding lazygit` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/lazygit/config.yml` | `~/.config/lazygit/config.yml` |

**The config file is empty** — lazygit runs on its defaults. The package exists so
the path is repo-owned: lazygit writes this file itself when a setting is changed
in the UI, and an empty tracked file turns that into a visible diff instead of an
untracked surprise.

On Linux this is *not* `~/.config/lazygit` by lazygit's own reckoning on every
platform — it uses the XDG dir on Linux and `~/Library/Application Support/lazygit`
on macOS. Confirm with `lazygit --print-config-dir` before assuming a Mac reads
this file; if it does not, symlink it the way `metapac` is bridged (see the root
`CLAUDE.md`).

## Overlaps

`git-spice` owns branch and stack operations here (see the root `CLAUDE.md`) —
using lazygit's branch/rebase/push actions on a tracked branch leaves the stack
metadata stale. Use it for staging, hunk selection and log browsing.
