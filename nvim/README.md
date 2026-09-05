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

## The AI gate tests the endpoint, not the machine

`lua/plugins/ai.lua` decides on **where the buffer text goes**, not on whose
laptop this is. Three variables, in order of authority:

| Variable | Effect |
| --- | --- |
| `DOTFILES_AI=off` | kill switch. Nothing loads, whatever else is set. |
| `AI_GATEWAY` | this host's OpenAI-compatible endpoint. Falls back to `LITELLM_GATEWAY`. |
| `DOTFILES_PROFILE` | `personal` permits a **remote** gateway; anything else permits **loopback only**. |

So the homelab keeps working, a work laptop can serve its own models over
loopback, and a work laptop cannot reach the homelab gateway. No gateway means
OFF — never "try somewhere else".

This replaced a `DOTFILES_PROFILE == "personal"` check, which answered "whose
laptop is this". That is the wrong question, and it ruled out the case this gate
exists for: **an inference server running on the work machine itself**, which
sends nothing anywhere. Loopback is matched as a literal — a hostname that
resolves to 127.0.0.1 today is not a guarantee, and this decides whether work
code leaves the machine.

The gate is explicit rather than inferred because the inferred version was
actively harmful:

```lua
local litellm = vim.env.LITELLM_GATEWAY or "http://localhost:4000"
```

With the variable unset, that disabled nothing. Every adapter loaded pointed at
localhost, so the plugins looked installed and failed only at the moment of use,
with an error that reads like a network fault rather than a machine that was
never meant to have them. **Absence of a value must mean OFF, not "try somewhere
else."**

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

## `:Cheatsheet` — AI, completion and LSP keys

`<leader>sc`, or `:Cheatsheet` (add `float` for a static window instead of the
telescope picker).

It exists because `:Telescope keymaps` reports these wrongly. blink.cmp runs its
preset from its own layer rather than through a keymap, so a scan cannot see it
and reports only the map blink falls back to. Several keys are shared that way:
`<C-y>` accepts a blink item while the menu is open and asks minuet for a
suggestion otherwise.

`lua/cheatsheet.lua` collects the list from live keymaps, matching the `AI (…):`,
`Luasnip:` and `LSP:` prefixes and Trouble's `(…)` suffix — so a new binding
appears on the sheet with no edit here, provided it carries one of those labels.
blink's preset is the one part it cannot scan, and is listed in the module beside
a note to keep it in step with `plugins/blink.lua`.

Rows marked `(buf)` are buffer-local and beat the global map of the same key
silently. `<leader>ca` is the case that matters: an LSP code action wherever a
server is attached, the CodeCompanion menu everywhere else.

### `<C-k>` and `<C-e>` are layered, not raced

Both keys are LuaSnip's. `plugins/ai.lua` re-maps them when minuet loads, taking
the key only while a suggestion is on screen and calling LuaSnip otherwise —
states that never coincide, so both plugins keep their key.

Two details hold it together. LuaSnip is listed in the minuet spec's
`dependencies` **for keymap precedence, not for any API**, which is what makes
this config reliably the later one. And minuet's branch is gated on
`is_visible`, because bare `action.prev` fires off a completion request when
nothing is showing — so an attempt to expand a snippet would have triggered the
model instead.

Neither key falls through to its native insert-mode meaning when nothing
applies: `<C-k>` opens a digraph prompt and `<C-e>` copies the character from the
line below, and inserting either by accident is worse than the no-op LuaSnip
already did.

A key two plugins map shows once, owned by whichever config ran last — and
lazy.nvim orders unrelated specs arbitrarily, so that is not always the same
plugin from one session to the next. `<C-k>` and `<C-e>` hit this: minuet and
LuaSnip both claim them, and the sheet caught the two disagreeing between runs.
They are now layered rather than raced — see below — but the general hazard is
why the sheet is generated live instead of written down.

## Testing a branch

```sh
nvim -u ~/dotfiles/nvim/.config/nvim/init.lua
```

## Related

`dict/` supplies the harper-ls dictionary that stops tool names being flagged as
misspellings — separate package because harper is editor-independent.
