# fish — fish shell configuration

Stow package. `stow --no-folding fish` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/fish/config.fish`, `env.fish`, `aliases.fish`, `custom.fish` | `~/.config/fish/` |
| `.config/fish/keybinds.fish` | keybindings — sourced **late** from `config.fish` |
| `.config/fish/conf.d/*` | auto-sourced drop-ins |
| `.config/fish/functions/*`, `completions/*` | functions and completions |
| `.config/fish/fish_plugins` | fisher plugin list |

Primary interactive shell on this machine.

## ⚠️ fish load order is not the one you expect

Two traps, both found the hard way:

1. **fish sources all of `conf.d` *before* `config.fish`.** So anything
   `config.fish` does — including `env.fish` → `fzf --fish | source`, which binds
   Ctrl+R — happens *after* every drop-in and wins.
2. **`conf.d` loads in byte order, and digits sort before letters.** `90-atuin.fish`
   ran *ahead* of `fzf.fish`, not after it. The numbered-drop-in intuition from
   `~/.config/bashrc` does not transfer — and by the same token **the reserved
   `99-local` slot does not load last in fish**, though it does in bash and zsh.

That is why atuin's init lives in `keybinds.fish`, sourced late from
`config.fish`, and not in a drop-in like every other integration here.

## Two fzf integrations, both binding Ctrl+R

The fisher plugin `fzf.fish` (`_fzf_search_history`) and upstream `fzf --fish`
(`fzf-history-widget`). Both had to be dealt with:

- The plugin's binding is released properly via `fzf_configure_bindings --history=`.
  **Do not edit the plugin's own `conf.d` file** — `fisher update` reverts it.
- The upstream one is simply rebound over.

fzf keeps Ctrl+T, Alt+C and its five Alt+Ctrl widgets.

## Files the repo does not own

`.stow-local-ignore` excludes three:

```text
fish_variables                          # fish rewrites its own universal-var store
.config/fish/functions/wt.fish          # worktrunk installs these itself, and its
.config/fish/completions/wt.fish        # copy is newer than the fork we shipped
```

Anything a tool installs into `functions/` or `completions/` belongs to that tool.
Racing it on every upgrade is unwinnable.

Note a package-local `.stow-local-ignore` **replaces** stow's built-in list rather
than adding to it — so repo-meta files (`README.*`, `CLAUDE.md`) must be named in
it explicitly.

## Machine-local

`conf.d/05-local-env.fish` reads `~/.config/dotfiles/local.env`;
`conf.d/06-secrets.fish` reads the session secret cache and defines `secrets-load`
/ `secrets-refresh`. Neither ever calls the network — a fetch in `conf.d` hangs
every new terminal when the gateway is unreachable.

`conf.d/hermes.fish` self-defaults `HERMES_TUI_GATEWAY_URL` with "set only if
unset", which is exactly why `05-local-env` must load before it.
