# grype — vulnerability scanner defaults

Stow package. `stow --no-folding grype` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/grype/config.yaml` | `~/.config/grype/config.yaml` |

User-level defaults for every invocation; per-scan flags still override. Feeds
`mise run lint:vuln`.

Shell completions ship with the shell packages, not here:
`bash/.bash_completions/grype.bash`, `zsh/.zfunc/_grype`,
`fish/.config/fish/completions/grype.fish`, plus a `55-grype` bash drop-in.

## Why this file is found on macOS without a bridge symlink

grype searches (verified against source — grype 0.116.1 / fangs / adrg-xdg):

1. `./.grype.<ext>`
2. `./.grype/config.<ext>`
3. `~/.grype.<ext>`
4. `$XDG_CONFIG_HOME/grype/config.<ext>`
5. each of `$XDG_CONFIG_DIRS` as `<dir>/grype/config.<ext>`

Step 5 is the load-bearing one. `adrg/xdg` does **not** define `XDG_CONFIG_HOME`
as `~/.config` on darwin — its config dirs end with `~/.config`, so this stowed
file is found via the *last* `configDirs` entry, not via `configHome`. Unlike
`metapac`, which has no such fallback and silently loads an empty default.

Confirm on a Mac with `grype config locations`.

The one way this breaks: exporting `XDG_CONFIG_DIRS` **replaces** the default list
rather than prepending to it, so a value that omits `~/.config` takes this file
out of the search path on macOS. Nothing here sets it.
