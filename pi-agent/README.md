# pi-agent — Pi Coding Agent Configs

Stow package for the Pi terminal AI agent.

## Quick Start (New Machine)

1. **Stow the package** (non-folding):

   ```bash
   cd ~/dotfiles
   stow --no-folding pi-agent
   ```

2. **Create your local `models.json`** with your real API key.

   > **Preferred:** once the key exists, run [`sync-litellm-models`](../commands/README.md)
   > to auto-populate `models` from the live provider catalogs instead of
   > hand-maintaining the list below. The `models` array is regenerated; your
   > `apiKey`/`baseUrl` are preserved.

   Minimal starter (the `models` array is replaced by the generator on first run):

   ```bash
   cat > ~/.pi/agent/models.json << 'EOF'
   {
     "providers": {
       "litellm": {
         "name": "LiteLLM (homelab)",
         "baseUrl": "https://litellm.example.com/v1",
         "api": "openai-completions",
         "apiKey": "YOUR_API_KEY_HERE",
         "models": [
           { "id": "role/reasoning", "name": "Reasoning (role alias)" },
           { "id": "role/completion", "name": "Fast completion (role alias)" },
           { "id": "zen/kimi-k2.5", "name": "Kimi K2.5 (Zen)" },
           { "id": "zen/claude-opus-4-7", "name": "Claude Opus 4.7 (Zen)" },
           { "id": "zen/claude-sonnet-4-6", "name": "Claude Sonnet 4.6 (Zen)" },
           { "id": "zen/gemini-3.5-flash", "name": "Gemini 3.5 Flash (Zen)" },
           { "id": "zen/gpt-5.1", "name": "GPT-5.1 (Zen)" },
           { "id": "zen/deepseek-v4-flash-free", "name": "DeepSeek V4 Flash Free (Zen)" },
           { "id": "zen/big-pickle", "name": "big-pickle (Zen)" }
         ]
       }
     }
   }
   EOF
   ```

   Replace `YOUR_API_KEY_HERE` with your actual key.

3. **Set the environment variable** (optional, if you want to use the env placeholder):

   ```bash
   export PI_API_KEY="your-real-key"
   ```

## Files

| File | Tracked | Notes |
|------|---------|-------|
| `.pi/agent/settings.json` | ✅ Yes | Safe to share across machines. Default model: `role/reasoning`. |
| `.pi/agent/models.json` | ❌ No | **Contains API keys.** Ignored by git. Each machine maintains its own copy. |
| `.pi/agent/models.example.json` | ✅ Yes | Template with placeholder key. |

## Secrets Policy

Any file containing `apiKey`, `token`, `secret`, or `password` must remain untracked.
`models.json` is gitignored; `models.example.json` is the tracked template, and its
key is the reference `!printenv PI_API_KEY` (pi runs an `apiKey` that starts with
`!` as a command), never a literal value.

## Adopting on a Machine with Existing Configs

Do not use `stow --adopt` for this package: it would pull a real `models.json`
(with its key) into the repo. Move the local copy aside, stow, then put it back
as a plain file:

```bash
mv ~/.pi/agent/models.json /tmp/pi-models.json
cd ~/dotfiles && stow --no-folding -t ~ pi-agent
mv /tmp/pi-models.json ~/.pi/agent/models.json
```

## OpenRig pi seats

OpenRig gives each pi seat its own agent directory
(`~/.openrig/state/pi/<session>/agent`) and never reads `~/.pi/agent`, so a seat
does not see this `models.json` or `settings.json`. It also passes no custom
provider key into the seat's environment. `mise run setup:openrig -- --pi-seat
<session>` writes a seat `models.json` that resolves the key with
`!dotfiles-secrets --get PI_API_KEY`.

## Example `models.json` (for reference)

See `models.example.json` in this directory for the full template.
