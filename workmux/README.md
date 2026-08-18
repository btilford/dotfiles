# workmux — tmux-native worktree sessions

Stow package. `stow --no-folding workmux` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/workmux/config.yaml` | `~/.config/workmux/config.yaml` |

Nerd Font glyphs on; everything else commented out at defaults.

That `nerdfont: true` line is committed **deliberately**: workmux prompts on first
run and writes the answer to this file itself — which, since `~/.config/workmux`
is a stow symlink, means it appends into the repo. It was moved into its
documented section rather than left at the file's tail where the tool dropped it.

## Shared worktree layout with worktrunk

Both tools are configured to produce the **same** path,
`~/worktrees/<repo>/<branch>` (slashes → dashes):

```yaml
worktree_dir: ~/worktrees/{project}
```

Repo-first is the only shape both can express — workmux builds
`<worktree_dir>/<handle>` and its template accepts only `~` and `{project}`, so
branch-first nesting is impossible here (upstream issue 148 shipped `{project}`
only; issue 161 is open). [`worktrunk`](../worktrunk) is the one that moved to
match. Keep the two in sync — changing one silently splits the tree.

## Use the `wm` wrapper, not bare `workmux`

workmux has no pre-create hook and never fetches: `base_branch: auto` resolves a
**local** ref, so a new worktree branches off whatever your last `git fetch` left
behind. `commands/.local/bin/wm` intercepts `add` only — it fetches and passes
`--base origin/<default>` — and execs straight through for everything else. Opt
out with `--base <ref>` or `WM_NO_FETCH=1`.

## Not used for this repo

`~/dotfiles` and `~/private-dotfiles` are worked **in place** on a single
checkout, no worktrees — see "One checkout" in the root `CLAUDE.md`. workmux stays
installed and configured because it is still the right tool for other repos.

Sessions are named `wm-<handle>`; worktrunk names its `<branch>-<repo>`. Left
divergent on purpose so it stays obvious which tool made a session.

```sh
# check a branch's config without touching anything
workmux add <name> --dry-run --config ~/dotfiles/workmux/.config/workmux/config.yaml
```

`--config` **merges with** the global config rather than replacing it, so a check
reflects the merge, not the branch alone.
