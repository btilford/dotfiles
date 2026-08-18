# nushell — structured-data shell

Stow package. `stow --no-folding nushell` from `~/dotfiles`.

| Path | Installs to | Tracked? |
|------|-------------|----------|
| `.config/nushell/config.nu`, `env.nu` | `~/.config/nushell/` | yes |
| `.config/nushell/local-env.nu` | reads `local.env` | yes |
| `.config/nushell/secrets.nu` | reads the session secret cache | yes |
| `.config/nushell/starship.nu` | prompt | yes |
| `.config/nushell/{mise,carapace,.zoxide,local}.nu` | generated | **no** — gitignored |
| `.config/nushell/history.txt` | | excluded from stow |

## Four generated files, and why they are gitignored

`env.nu` regenerates `mise.nu`, `carapace.nu` and `.zoxide.nu` on **every shell
start**, with the generating host's absolute paths baked in — `mise.nu` carried
`/Users/btilford` on macOS while Arch rewrote it to `/usr/bin/mise`, and it
ping-ponged between machines forever.

`local.nu` is untracked so a secret written there cannot be committed. `env.nu`
creates the stub because `config.nu` sources all four **at parse time**: a missing
file is a parse error, not a warning, and takes the whole shell down.

## `secrets.nu` uses `export-env`, and it has to

Reading the secret cache into the caller's scope only works from an `export-env`
block — the one construct in a nushell module that runs at `use` time *and* whose
environment changes reach the caller. A plain `def` would set variables inside its
own scope and lose them on return.

Keep it in step with the other three shells' `06-secrets` drop-ins. fish diverged
for a while as the only shell that auto-loaded, which left bash, zsh and nushell
fetching over the network in `secrets-load` and never touching the cache at all.

## Not wired up

`atuin init nu` **is** supported and is not configured here yet — nushell is the
one shell without atuin history.

The `metapac` `FORCE_COLOR=0` wrapper *is* present (in `config.nu`); without it
metapac's bun backend reads ANSI escapes as package names and treats every bun
package as unmanaged.
