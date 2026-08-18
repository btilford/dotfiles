# nvim — Neovim, plus the vim/IdeaVim leftovers

Stow package. `stow --no-folding nvim` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/nvim/init.lua` | entry point |
| `.config/nvim/lua/{options,mappings,autocommands}.lua` | core settings |
| `.config/nvim/lua/plugins/*.lua` | one file per plugin/topic — ~45 of them |
| `.config/nvim/lazy-lock.json` | plugin lockfile (⚠️ see below) |
| `.config/nvim/filetype.lua`, `ghostty.vim` | filetype + ghostty config syntax |
| `.config/vim/.vimrc`, `.vimrc`, `.ideavimrc` | plain vim and IdeaVim |
| `.markdownlint-cli2.yaml` | user-global markdownlint config |
| `.local/bin/kotlin-lsp.sh` | Kotlin LSP launcher |

Leader is `<space>`. `lazy.nvim` bootstraps itself by cloning into
`stdpath("data")` on first launch, so a fresh machine needs only the package
stowed and network access.

`init.lua` also sources `~/.vimrc` and prepends `~/.vim` to the runtimepath, so
the plain-vim config still applies. Editing `.vimrc` therefore affects **both**.

## Plugins are not metapac-managed, on purpose

Plugin versions come from `lazy-lock.json`; LSP servers and formatters come from
Mason via `mason-tool-installer`. Neither is declared in
[`metapac`](../metapac) — two managers claiming the same tool breaks
sync/clean semantics.

⚠️ **`lazy-lock.json` is meant to be unstowed, and is not.** It is listed in the
repo-root `.stow-local-ignore` — but stow reads that file from the *package*
directory, never from the parent, so the entry has never applied:

```console
$ stow --no-folding -n -v -t /tmp/probe nvim | grep lazy-lock
LINK: .config/nvim/lazy-lock.json => .../nvim/.config/nvim/lazy-lock.json
```

So `:Lazy update` writes through the symlink into the repo. In practice that is
survivable — the lockfile *is* something this repo wants to track — but it means
plugin bumps land as an unrequested diff on whatever branch is checked out.

Moving the entry into an `nvim/.stow-local-ignore` fixes it, with one catch: a
package-local ignore file **replaces** stow's built-in list rather than adding to
it, so it would also have to name `README.*` and `CLAUDE.md`.

## AI plugins are gated OFF by default — and that is deliberate

`lua/plugins/ai.lua` reads `DOTFILES_PROFILE` and defaults it to **`work`**. Only
`DOTFILES_PROFILE=personal` (in `~/.config/dotfiles/local.env`) loads the local-AI
adapters. Work machines get no local AI: the homelab gateway, its models and its
hostnames must not be reached from — or named on — a work laptop.

The gate is explicit rather than inferred because the inferred version was
actively harmful:

```lua
local litellm = vim.env.LITELLM_GATEWAY or "http://localhost:4000"
```

With `LITELLM_GATEWAY` unset — exactly the work-machine case — that disabled
nothing. Every adapter loaded pointed at localhost, so the plugins looked
installed and failed only at the moment of use, with an error that reads like a
network fault rather than a machine that was never meant to have them. **Absence
of a value must mean OFF, not "try somewhere else."**

The API key is not read from the environment at config load either. It is fetched
when an adapter actually needs it, through `dotfiles-secrets` — which resolves
environment → session cache → network. The old form,
`vim.env.NEOVIM_API_KEY or "missing-NEOVIM_API_KEY"`, sent the literal string
`missing-NEOVIM_API_KEY` as a credential whenever nvim started outside a shell.

Anything launched from a desktop entry or a systemd unit needs the
`environment.d` link for `vim.env` to see these at all:

```sh
ln -s ~/.config/dotfiles/local.env ~/.config/environment.d/50-local.conf
```

## Testing a branch

```sh
nvim -u ~/dotfiles/nvim/.config/nvim/init.lua
```

## Related

`dict/` supplies the harper-ls dictionary that stops tool names being flagged as
misspellings — separate package because harper is editor-independent.
