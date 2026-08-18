# tuicr — code review TUI for local diffs and remote PRs/MRs

Stow package. `stow --no-folding tuicr` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/tuicr/config.toml` | `~/.config/tuicr/config.toml` |

Only setting: `diff_view = "side-by-side"` (toggle in-app with `:diff`).

The forge is auto-detected from the git remote, so **one config serves GitHub and
the self-hosted GitLab** — there is no forge block to keep out of this repo. Auth
comes from `gh`/`glab`, which tuicr shells out to itself.

Installed via the `cargo` backend in `metapac`'s `core.toml`.

## Where it gets launched from

| Binding | Where |
|---------|-------|
| `prefix + P` | tmux popup, cwd-pinned (`.tmux.conf`) |
| `R` | on the selected PR in `gh dash` (`gh-dash/.config/gh-dash/config.yml`) |

The gh-dash binding builds the URL from `RepoName`, so it needs no local checkout.
