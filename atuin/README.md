# atuin — shell history, sync, and search

Stow package. `stow --no-folding atuin` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/atuin/config.toml` | `~/.config/atuin/config.toml` |

Shell integration is **not** in this package. Each shell package carries its own
drop-in: `fish/.config/fish/keybinds.fish`, `bash/.config/bashrc/60-atuin`,
`zsh/.config/zshrc/60-atuin`. nushell is not wired up yet.

## The profile seam

Config varies by **profile** — personal vs work — not by OS, so there is no
second stow package. atuin has no include mechanism, and **the config file beats
the environment** (verified on 18.18.1): a key present in `config.toml` cannot be
overridden by `ATUIN_*`. Every profile-varying key is therefore *deliberately
absent* from the tracked file:

`sync_address`, `auto_sync`, `ai.enabled`, `ai.endpoint`, `ai.model`.
`ai.api_token` is a credential and is in neither place.

Writing a "sensible default" for one of these here silently switches its override
off forever.

## These do NOT go in `local.env`

An empty `ATUIN_*` value is not read as unset — it is parsed, it fails, and it
takes settings loading down for the whole binary:

```console
$ ATUIN_SYNC_ADDRESS= atuin status
Error: could not load client settings
Caused by: failed to deserialize: relative URL without a base: "" for key `sync_address`
```

`gen-local-env.sh` emits an empty placeholder for every variable in the manifest,
so listing these in `required-env` would break atuin on every freshly provisioned
machine. They live in the untracked `99-local` shell drop-in instead. The tracked
drop-ins unset any set-but-empty `ATUIN_*` before init as a second guard.

## The AI assistant, and `how`

`how size disk` proposes the `df`/`du` command. It is a thin wrapper over
`atuin ai inline`, defined in `fish/.config/fish/functions/how.fish` and in the
bash and zsh `60-atuin` drop-ins.

Two details that are easy to get wrong:

- **The query is ONE positional argument.** bash/zsh use `"$*"`, not `"$@"`, and
  fish quotes `"$argv"` — otherwise only the first word is sent and the rest is
  dropped silently.
- **`inline` proposes and does not execute**, matching `enter_accept = false` in
  the config.

### The client cannot talk to an LLM directly

atuin speaks the Atuin AI protocol, not OpenAI, so `ai.endpoint` points at an
[atuin-ai-server](../atuin-ai-server), which translates to a plain
OpenAI-compatible endpoint:

```text
atuin ai / how  ->  atuin-ai-server  ->  Ollama        ->  role/chat
                    127.0.0.1:8080       127.0.0.1:11434
```

`ai.model` is a **server-side alias** from that server's `[[models]]` table, not
a model name. `endpoint_protocol` is set to `oss` explicitly — `auto` would infer
it correctly from a non-Atuin address, but an inference is not something to rest
a no-egress guarantee on.

### Capabilities on, yolo off

All five capabilities and `send_cwd` are enabled; `ai.yolo` is `false`. yolo is
what makes the rest safe — the assistant proposes and asks instead of acting.

The nested keys do override from the environment
(`ATUIN_AI__CAPABILITIES__ENABLE_FILE_TOOLS` and so on). Verify with
**`atuin config get --resolved <key>`** — a bare `atuin config get` reads the
config *file* only and will report "not set in config file" for a value the
environment is supplying perfectly well.

None of the `[ai]` keys appear in `atuin default-config`; the full surface is
listed in the header of `config.toml`.

### The work profile no longer means "no AI"

The tracked drop-ins used to `unset ATUIN_AI__ENABLED ATUIN_AI__ENDPOINT` for any
non-personal profile, conflating AI with sync. They now test the **endpoint**: a
remote one is refused on a work profile, loopback is fine on any profile. Sync is
still forced off. See the local-inference section of the repo `CLAUDE.md`.

## fish: no `conf.d` file can win Ctrl+R

fish sources all of `conf.d` *before* `config.fish`, whose first line sources
`env.fish` → `fzf --fish | source`, which binds Ctrl+R. atuin's init therefore
lives in `keybinds.fish`, sourced late from `config.fish`. Numbered names do not
help: fish loads `conf.d` in byte order and digits sort before letters.

Two fzf integrations bind Ctrl+R here — the fisher plugin (`_fzf_search_history`,
released via `fzf_configure_bindings --history=`) and upstream `fzf --fish`
(`fzf-history-widget`, simply rebound over). fzf keeps Ctrl+T, Alt+C and its
Alt+Ctrl widgets.

## Agent hooks

`atuin hook install <agent>` records every Bash tool call an agent makes into the
same history the shell writes to. Per machine, per agent, and **not tracked here**
— it writes generated files into `~/.claude/`, `~/.codex/` and `~/.pi/`:

```sh
atuin hook install claude-code
atuin hook install codex
atuin hook install pi
```
