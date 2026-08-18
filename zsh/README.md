# zsh — zsh shell configuration

Stow package. `stow --no-folding zsh` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.zshrc` | `~/.zshrc` |
| `.config/zshrc/*` | `~/.config/zshrc/` — numbered drop-ins |
| `.zfunc/_grype`, `.zfunc/_workmux` | `~/.zfunc/` — completion functions |

Same loader shape as [`bash/`](../bash): `.zshrc` sources every file in
`~/.config/zshrc/` in name order, then `~/.zshrc_local`, then the tails that must
run last.

Drop-ins: `00-init`, `01-macos`, `05-local-env`, `06-secrets`, `15-mise`,
`16-bun`, `17-chrome-bin`, `18-git-spice`, `20-starship`, `25-aliases`,
`30-autostart`, `50-custom`, `60-atuin`.

The `custom/` escape hatch works the same way — a file at
`~/.config/zshrc/custom/<same-name>` **replaces** the stowed drop-in.

## Why some completions are in `.zfunc` and git-spice's is not

`_grype` and `_workmux` are ordinary fpath functions, committed.

git-spice's is `eval`'d from `.zshrc` **after** `compinit`, for two reasons that
both matter:

- What `git-spice shell completion zsh` emits is **imperative code needing
  `bashcompinit`**, not an fpath function — so it cannot live in `~/.zfunc`.
- Drop-ins are sourced *before* `compinit`, so it cannot be a `~/.config/zshrc`
  file either.

It is `eval`'d rather than committed because the generated output **hardcodes the
absolute path of the binary**, which differs between Arch (`/usr/bin`) and macOS
(brew).

Write `git-spice`, never `gs`: `/usr/bin/gs` is ghostscript. `gs` exists only as
an interactive alias (`18-git-spice`) and does not exist in a script.

## Reserved slots

`05-local-env` loads **early** (values); `99-local` loads **last** (behaviour
overrides). Numbers order correctly here, unlike in fish.

## sdkman must stay at the end

The comment in the file is not decoration — sdkman's init rewrites `PATH` and
must run after everything that sets it.
