# mise-scripts — task scripts for `mise run`

**Not a stow package.** Nothing here is symlinked into `$HOME`, and no stow
package may reach into it.

Every other top-level directory in this repo *is* a stow package, which is why
this one is named `mise-scripts/` rather than `scripts/` — a bare `scripts/` reads
like config that gets stowed.

| Script | Task | Does |
|--------|------|------|
| `stow-status.sh` | `mise run status` | classify every package: stowed, shadowed, **FOLDED**, missing |
| `stow-pick.sh` | `mise run stow` | interactive package picker |
| `gen-local-env.sh` | `mise run setup:local-env` | build `~/.config/dotfiles/local.env` from the manifest |
| `freeze-generated.sh` | `mise run setup:frozen` | apply (or `--check`) the `skip-worktree` bits in `.stow-frozen` |
| `setup-git-spice.sh` | `mise run setup:git-spice` | git template, forge URL, auth, hook retrofit |
| `no-local-values.sh` | `mise run lint:private` | block private values, patterns and identifiers |
| `shell-files.sh` | — | the **sole** shellcheck file selector |
| `yaml-files.sh` | — | the **sole** yamllint file selector |
| `visual-capture.sh` | `mise run screenshots` | headless desktop capture |
| `visual-archive.sh` | `mise run screenshots:archive` | file captures into the notes vault |
| `render-visual-history.py` | `mise run screenshots:history` | regenerate the archive's pages from the ledger |
| `gen-luacheck-hl-std.sh`, `luacheck-hl-std.lua` | `mise run gen:luacheck-hl-std` | derive a luacheck std from Hyprland's Lua stubs |
| `visuals/` | | the capture harness's own docs — [read this](visuals/README.md) |

## Three scripts have a second caller

`no-local-values.sh` (lefthook **and** CI), `shell-files.sh` and `yaml-files.sh`
(both CI jobs). The directory name says who *owns* them, not who may run them —
when moving or renaming one, grep `lefthook.yml` and `.gitlab-ci.yml` as well as
`mise.toml`.

## Why file selection is shared

`shell-files.sh` and `yaml-files.sh` are the only selectors any surface uses, so
*which* files get linted is structurally identical rather than three lists kept in
step by hand.

Both are POSIX `sh` using only `find`/`grep`, because **the CI images ship no
git** — `git ls-files` is unavailable there, which is why selection is path-based.

`shell-files.sh` selects **by shebang, not by extension**. The previous
`*.sh`/`*.bash` globs silently skipped every extensionless command in
`commands/.local/bin` and `git/.local/bin` — eight scripts, including the `wt-*`
helpers both worktree tools depend on. Those files have no extension by design
(they are on `PATH`), so no glob could ever find them.

## `no-local-values.sh` has three halves, and prints as little as possible

1. **Values** read from `~/.config/dotfiles/local.env` at run time — so no private
   string is ever committed as a denylist. Only the *variable name* is printed.
2. **Generic patterns** — RFC1918 addresses, `/home/<user>`, `desc:` monitor
   serials, US phone numbers. This half is what enforces the rule in CI, which has
   no `local.env`.
3. **Identifiers** from `~/.config/dotfiles/scrub.patterns` — an untracked list of
   extended regexes for things private by *identity* (an employer, a client, an
   internal project). Neither other half can catch these: they are not values any
   config consumes and they have no distinguishing shape.

Two properties to preserve:

- **Only the line number is printed, never the pattern.** The pattern spells out
  the string being kept out.
- **A pattern that does not compile fails the gate.** `grep` exits 2 on a bad
  regex — neither "found" nor "clean". Treated as a pass, one typo switches that
  line off permanently and silently.

It matches against `path:line:text`, so it catches **file names** too. That is how
a kmonad keymap named after a client was found; a plain `grep -ri` missed it,
because that only ever looks at contents.

In `--all` mode (what CI runs) it prints `path:line` and withholds the content —
CI logs are a published surface. Staged mode prints the line, since that runs in
the author's own terminal on content they just wrote. Keep the asymmetry.

A fourth surface: `--message`, run from a `commit-msg` hook, because `pre-commit`
runs before the message exists and commit messages are published exactly like
files.

## Visual capture

See [`visuals/README.md`](visuals/README.md) — **especially its isolation
section**. An agent-launched compositor destroyed the live desktop session on this
machine on 2026-07-26. The backend is forced via environment
(`WLR_BACKENDS=headless`), never via a config file, and a failed compositor start
is never retried in a loop.
