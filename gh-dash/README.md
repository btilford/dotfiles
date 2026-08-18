# gh-dash — GitHub PR / issue dashboard

Stow package. `stow --no-folding gh-dash` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/gh-dash/config.yml` | `~/.config/gh-dash/config.yml` |

Sections for PRs (mine / needs my review / involved), issues, and notifications.

## Not managed by metapac

gh-dash ships **only** as a `gh` extension — no brew formula, no crates.io or npm
package, and metapac has no gh-extension backend. Bootstrap it per machine:

```sh
gh extension install dlvhdr/gh-dash
```

The stow package supplies the config either way.

## Keybinding worth knowing

`keybindings.prs` defines **`R`** = open the selected PR in [`tuicr`](../tuicr):

```text
tuicr pr {{.PrNumber}} --repo-url https://github.com/{{.RepoName}}
```

Built from `RepoName`, so no local clone is required.

Launch from a tmux popup with `prefix + G` (cwd-pinned, guarded by `command -v`).
