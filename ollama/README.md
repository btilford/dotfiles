# ollama — local model server (systemd user unit)

Stow package. `stow --no-folding ollama` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/systemd/user/ollama.service` | `~/.config/systemd/user/ollama.service` |
| `.local/share/ollama/keep.txt` | `~/.local/share/ollama/` (placeholder so the dir exists) |

Runs `ollama serve` as a **user** unit with `WorkingDirectory=%h/.local/share/ollama`,
so models land in the user's home rather than under `/usr/share/ollama`.

## Enabling it — do NOT use `systemctl enable`

`systemctl disable`/`reenable` on a stowed unit **deletes the unit file itself** —
that is the stow symlink, not a copy. Wire the `.wants` link by hand:

```sh
ln -s ~/.config/systemd/user/ollama.service \
      ~/.config/systemd/user/default.target.wants/ollama.service
systemctl --user daemon-reload
systemctl --user start ollama
```

The same rule applies to every unit in this repo (`llama-swap`, `clipborg`,
`dotfiles-secrets`).

## Consumers

`OLLAMA_HOST` (default `localhost`) is read by `nvim`'s `plugins/ai.lua` for
gen.nvim; `OLLAMA_URL` (default `localhost:11434`) by
`commands/.local/bin/sync-litellm-models`. Both come from
`~/.config/dotfiles/local.env`.

On this machine [`llama-swap`](../llama-swap) is the primary serving layer —
ollama is kept for the models and tooling that only speak its API.
