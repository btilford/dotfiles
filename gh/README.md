# gh — GitHub CLI

Stow package. `stow --no-folding gh` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/gh/config.yml` | `~/.config/gh/config.yml` |

## `hosts.yml` is untracked, with no example

`gh` writes an `oauth_token:` into `~/.config/gh/hosts.yml` whenever no OS keyring
is available, so tracking it is a standing leak risk even when it currently looks
clean. Excluded in both `.gitignore` and the package `.stow-local-ignore`, and
excluded from `mise-scripts/yaml-files.sh` so a provisioned machine's lint run
agrees with CI's (which sees a fresh clone where the file does not exist).

No template: `gh auth login` writes it.

```sh
gh auth login
```

## Wired into git

The `git` package routes GitHub credentials through this CLI:

```ini
[credential "https://github.com"]
    helper = !~/.local/bin/gh-git-credential
```

See [`git/`](../git) — the `!` prefix is load-bearing.
