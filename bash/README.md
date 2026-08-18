# bash — bash shell configuration

Stow package. `stow --no-folding bash` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.bashrc`, `.bash_profile` | `~/` |
| `.config/bashrc/*` | `~/.config/bashrc/` — numbered drop-ins |
| `.bash_completions/grype.bash` | `~/.bash_completions/` |

## The loader

`.bashrc` is a loop, not configuration — **don't put settings in it.** It sources
every file in `~/.config/bashrc/` in name order, then `~/.bashrc_local`, then the
sdkman / envman / cargo tails that must run last.

Drop-ins, in load order:

| File | Does |
|------|------|
| `00-init` | `EDITOR=nvim`, PATH, `YARN_ENABLE_SCRIPTS=false` |
| `01-macos` | macOS-only branches |
| `05-local-env` | reads `~/.config/dotfiles/local.env` — **values, must be early** |
| `06-secrets` | reads the session secret cache; defines `secrets-load` / `secrets-refresh` |
| `10-aliases` | aliases |
| `15-mise`, `16-bun`, `17-chrome-bin`, `18-git-spice` | tool init |
| `30-autostart` | fastfetch and friends |
| `50-custom` | interactive-only: history sizes/dedup, `shopt`s, then direnv / zoxide / fzf / carapace init |
| `55-grype`, `60-atuin` | completions / history; `60-` is above `50-custom` so atuin rebinds Ctrl+R after fzf |

## Two reserved slots, ordered opposite ways

- **`05-local-env`** — *values*, must load **early**, because configs that
  self-default use "set only if unset".
- **`99-local`** — *behaviour* overrides, must load **last** to win.

Unlike fish, bash's numbered drop-ins really do load in the order the numbers
imply.

## The `custom/` escape hatch

```sh
[[ -f $c ]] && source $c || source $f
```

A file at `~/.config/bashrc/custom/<same-name>` **replaces** the stowed drop-in
outright. That is the clean way to neutralise one file on one machine — e.g. a
Linux-only drop-in on a Mac — with no repo change and no unstowing. The directory
does not exist yet.

## The `metapac` wrapper is load-bearing

`16-bun` defines a `metapac` wrapper setting `FORCE_COLOR=0`. `bun pm ls -g`
colorizes even when piped and ignores `NO_COLOR`, so metapac's bun backend
captures ANSI escapes into package names and then treats **every** bun package as
unmanaged. Drop the wrapper and `metapac clean` will offer to remove them.

## Machine-local, never here

`~/.bashrc_local` (sourced by `.bashrc`) is the slot for `$DOTFILES_SCREENSHOT_ARCHIVE`
and anything else that points into a notes vault only some hosts have.
