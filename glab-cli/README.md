# glab-cli — GitLab CLI aliases

Stow package. `stow --no-folding glab-cli` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/glab-cli/aliases.yml` | `~/.config/glab-cli/aliases.yml` |

Two aliases: `ci` → `pipeline ci`, `co` → `mr checkout`.

## `config.yml` is deliberately absent, with no template

`glab auth login` writes **auth tokens** into `~/.config/glab-cli/config.yml`, so
it is excluded three ways — package `.stow-local-ignore`, `.gitignore`, and an
allowlist in `.betterleaks.toml` (needed because `betterleaks dir` walks the working
directory without honouring `.gitignore`, and would otherwise fail the local scan
on a real token forever).

There is deliberately **no tracked template** of it: `glab auth login` writes the
file itself, and `mise run glab:config` applies every setting worth
version-controlling.

```sh
glab auth login --hostname <your-gitlab-host>
mise run glab:config
```

`mise run glab:config` reads `DOTFILES_GITLAB_HOST` from
`~/.config/dotfiles/local.env` and skips the per-host `git_protocol` setting when
it is unset — the hostname identifies private infrastructure and never lands here.

Never commit a `config.yml` that contains a real token.
