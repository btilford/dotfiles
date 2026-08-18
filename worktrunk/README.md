# worktrunk — git worktree manager (`wt`)

Stow package. `stow --no-folding worktrunk` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/worktrunk/config.toml` | `~/.config/worktrunk/config.toml` |

Heavily commented — most of the file is upstream's documented default, with the
live settings uncommented.

```toml
worktree-path = "~/worktrees/{{ repo }}/{{ branch | sanitize }}"
```

## Same layout as workmux, deliberately

[`workmux`](../workmux) builds `<worktree_dir>/<handle>` and its template accepts
only `~` and `{project}`, so repo-first is the only shape **both** tools can
express. worktrunk is the one that moved. Keep the two templates in sync —
changing one splits the tree silently, and `wt list` / `wt-prune-branch-dir` only
understand paths worktrunk made.

## `[pre-switch]` fetches; workmux cannot

worktrunk's `[pre-switch]` hook runs before the branch and worktree exist, so it
refreshes `origin/*` first. Pair it with `-b origin/master` to branch from the
fresh tip. (workmux has no such hook, which is why `commands/.local/bin/wm`
exists.)

## The `wt` shell function is NOT tracked here

worktrunk installs **both** `functions/wt.fish` and `completions/wt.fish` itself,
and its copies are the authoritative ones — the repo shipped a fork of the first
that had drifted a full feature behind, missing the `COMPLETE` recursion guard
that stops a stale Homebrew completion re-entering the stub. Both are excluded in
`fish/.stow-local-ignore`. Racing a tool for a path it reinstalls on every upgrade
is unwinnable.

## Not used for this repo

`~/dotfiles` and `~/private-dotfiles` are worked **in place** on one checkout —
see "One checkout" in the root `CLAUDE.md`. worktrunk stays installed for other
repos. Sessions it creates are named `<branch>-<repo>`.

One hazard that applies wherever you *do* use worktrees: `git-spice`'s
`up`/`down`/`restack` cannot touch a branch checked out in another worktree. It
**skips it with a warning and still reports success**, leaving a stale base
behind. One worktree per *stack*, not per branch.
