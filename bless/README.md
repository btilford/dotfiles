# bless — GTK hex editor preferences

Stow package. `stow --no-folding bless` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/bless/preferences.xml` | `~/.config/bless/preferences.xml` |

Hex default number base, insert edit mode, 100 undo actions kept after save,
pattern-match highlighting, statusbar and toolbar shown.

## Session state is excluded, and why it had to be

```text
history.xml
last.session
```

Both are in the package `.stow-local-ignore` **and** `.gitignore`. bless records
the last-opened file path in them, and they had already leaked a client project
directory and an absolute home path. Config is repo-owned; state stays local.

That split is the general rule for this repo — see "Files the repo does not own"
in the root `CLAUDE.md`. bless is the case where the leak was real rather than
theoretical.
