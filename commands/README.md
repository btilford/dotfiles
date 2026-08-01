# commands — personal scripts on `$PATH`

Stow package. Installs `commands/.local/bin/*` to `~/.local/bin/` (must be on
`$PATH`). Stow non-folding:

```bash
cd ~/dotfiles
stow --no-folding commands
```

| Script | Purpose |
|--------|---------|
| `sync-litellm-models` | Sync real provider models into LiteLLM + agents (see below) |
| `wt-setup-worktree` / `wt-sync-primary` | git worktree helpers |
| `edit-output.sh`, `kde-virtual-screens.sh`, `mount-library.sh (moved to private repo)`, `seshls` | misc desktop/session helpers |

---

## `sync-litellm-models`

Single source of truth for which models the homelab LiteLLM gateway routes, and
for the model pickers in pi and opencode.

### What it does

1. Fetches the **real** model list from each provider's native `/models`
   endpoint (Venice, OpenCode Zen, Lemonade, Ollama).
2. **Gateway** — reconciles the LiteLLM DB (`STORE_MODEL_IN_DB=true`) to exactly
   those real ids, deleting the `openai/*` wildcard routes.
3. **pi / opencode** — regenerates the catalogs in `~/.pi/agent/models.json` and
   `~/.config/opencode/opencode.json` from the same fetch.

Targets are auto-detected per machine (not every box has pi/opencode) and, when
run interactively without flags, confirmed before any change.

### Why explicit ids instead of `provider/*` wildcards

A wildcard like `cachyos-fwd/*` → `openai/*` routes any suffix, but it makes
`GET /v1/models` return the **entire OpenAI model registry** stamped under each
prefix — ~621 junk entries (`venice/dall-e-3`, `cachyos-fwd/gpt-4o`, …). Anything
that lists models from the gateway (Hermes, dynamic clients) then sees garbage.

Registering the real ids gives a clean, accurate list everywhere (~148 models).
Trade-off: a brand-new model on a provider isn't routable until this re-runs —
which is one command. Offline providers keep their existing routes (the script
only touches providers it can reach this run).

### Usage

```bash
sync-litellm-models                 # detect targets, confirm, sync
sync-litellm-models --yes           # sync all detected targets, no prompt
sync-litellm-models --only gateway  # just reconcile the LiteLLM DB
sync-litellm-models --only pi,opencode
sync-litellm-models --dry-run       # show planned changes, touch nothing
```

Run it after a provider gains/loses models, or after downloading a new model on
Lemonade. No more hand-editing model lists.

### Requirements

- `infisical` CLI logged in — secrets (`VENICE_API_KEY`, `ZEN_API_KEY`,
  `LITELLM_MASTER_KEY`) come from Infisical project
  `$INFISICAL_PROJECT`, env `prod`.
- Network reach to the gateway (`$LITELLM_GATEWAY`) and to whichever
  providers are local (Lemonade `$LEMONADE_URL`, Ollama `$OLLAMA_URL`).

### Provider → prefix map

| Prefix | Provider | LiteLLM model | api_base |
|--------|----------|---------------|----------|
| `cachyos-fwd/` | Lemonade (cachyos-fwd) | `openai/<id>` | `$LEMONADE_URL/v1` |
| `x870eglacial/` | Ollama (x870eglacial) | `ollama/<id>` | `$OLLAMA_URL` |
| `zen/` | OpenCode Zen | `openai/<id>` | `https://opencode.ai/zen/v1` |
| `venice/` | Venice.ai | `openai/<id>` | `https://api.venice.ai/api/v1` |

### Notes

- `model: venice/*` (native Venice provider) does **not** work in LiteLLM
  v1.88.1 — Venice is wired as openai-compatible passthrough.
- API keys are passed to `/model/new` as **literal values**, not
  `os.environ/...` refs — env refs added via the admin API are stored verbatim
  and sent as the bearer (→ 401). Keyless local backends use `api_key: none`.
- pi's active model subset is its `enabledModels` in
  `pi-agent/.pi/agent/settings.json`; this script writes the full catalog, not
  the active subset.
