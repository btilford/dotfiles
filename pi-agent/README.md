# pi-agent — Pi Coding Agent Configs

Stow package for the Pi terminal AI agent.

## Quick Start (New Machine)

1. **Stow the package** (non-folding):
   ```bash
   cd ~/dotfiles
   stow --no-folding pi-agent
   ```

2. **Create your local `models.json`** with your real API key:
   ```bash
   cat > ~/.pi/agent/models.json << 'EOF'
   {
     "providers": {
       "litellm": {
         "name": "LiteLLM (homelab)",
         "baseUrl": "https://litellm.example.net/v1",
         "api": "openai-completions",
         "apiKey": "YOUR_API_KEY_HERE",
         "models": [
           { "id": "cachyos-fwd/Qwen3.6-35B-A3B-MTP-GGUF", "name": "Qwen3.6-35B-MTP (Lemonade)" },
           { "id": "x870eglacial/qwen2.5-coder:7b", "name": "Qwen2.5-Coder-7B (Ollama)" },
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
| `.pi/agent/settings.json` | ✅ Yes | Safe to share across machines. Default model: `cachyos-fwd/Qwen3.6-35B-A3B-MTP-GGUF`. |
| `.pi/agent/models.json` | ❌ No | **Contains API keys.** Ignored by git. Each machine maintains its own copy. |
| `.pi/agent/models.json.example` | ✅ Yes | Template with placeholder key. |

## Secrets Policy

Any file containing `apiKey`, `token`, `secret`, or `password` must remain untracked.
The repo's `models.json` is a placeholder with `!printenv PI_API_KEY`.

## Adopting on a Machine with Existing Configs

If you already have a local `~/.pi/agent/models.json` with a real key:
```bash
cd ~/dotfiles
# Adopt existing configs (copies local files into the repo)
stow --adopt --no-folding pi-agent

# IMMEDIATELY revert the repo's models.json to the placeholder
git checkout HEAD -- pi-agent/.pi/agent/models.json

# Break the symlink so the local file stays local
rm ~/.pi/agent/models.json
# (re-create your local file with the real key if needed)
```

## Example `models.json` (for reference)

See `models.json.example` in this directory for the full template.
