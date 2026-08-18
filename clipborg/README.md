# clipborg — clipboard manager with LLM actions

Stow package. `stow --no-folding clipborg` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/clipborg/config.toml` | `~/.config/clipborg/config.toml` |
| `.config/clipborg/prompts/*.md` | `~/.config/clipborg/prompts/` |
| `.config/systemd/user/clipborg.service.d/10-secrets.conf` | systemd drop-in |

Formerly **clipvault** — same project, renamed. Grep both spellings in old notes;
write new references as clipborg.

## Two-layer config

This file is the **base** layer. clipborg reads
`~/.config/clipborg/config.local.toml` on top of it — a real file, never stowed
and never committed, and the only place API keys and per-machine paths belong.

The local layer **merges** rather than replaces: tables merge key by key, and
`[[actions]]` / `[[llm.prompts]]` / `[[llm.harnesses]]` merge **by `id`**, so a
local file can change one prompt's harness without restating the whole array.
Every other array replaces wholesale.

Strings may use `${VAR}`, expanded from the environment at load (`$${` is a
literal `${`). **An unset variable is a hard error at startup**, not an empty
string — which is exactly why secrets reach the shell environment on this machine
at all (see "Secrets reach the shell from a tmpfs cache" in the root `CLAUDE.md`).

## `10-secrets.conf`

A systemd drop-in pointing the unit at the session secret cache:

```ini
EnvironmentFile=-%t/dotfiles/secrets.env
```

The leading `-` keeps the unit startable on a machine with no secrets at all.
`dotfiles-secrets.service` writes that file once at login into `$XDG_RUNTIME_DIR`
(tmpfs, 0700/0600, gone at logout).

Enable by hand-linking `.wants` — never `systemctl --user enable` a stowed unit,
which deletes the symlink on `disable`/`reenable`.

## Prompts and colours

`prompts/*.md` are the LLM action bodies (summarize, explain-code, research-url,
implement-plan, vault-ingest, …), referenced by `id` from `config.toml`.

`~/.config/clipborg/colors.json` is written by [`wallust`](../wallust) on every
wallpaper switch — generated, not tracked.

The quickshell clipboard dialog fetches clipborg's capabilities over IPC; it never
reads this file.
