# ollama — local model server (systemd on Linux, launchd on macOS)

Stow package. `stow --no-folding ollama` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/systemd/user/ollama.service` | `~/.config/systemd/user/ollama.service` (Linux) |
| `Library/LaunchAgents/com.dotfiles.ollama.plist` | `~/Library/LaunchAgents/` (macOS) |
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

## macOS — the launchd half

Install the **cask**, whose brew token is `ollama-app`. There is also a formula
called `ollama`, and it has a history of broken MLX packaging on Apple Silicon
(Homebrew #286746). The tokens differ, so metapac cannot pick the wrong one.

```sh
stow -R --no-folding -t ~ ollama
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.dotfiles.ollama.plist
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.dotfiles.ollama-warm.plist
mise run setup:ollama-roles
```

**The agent runs the server; do not also launch Ollama.app.** The app installs
its own login agent and two servers cannot share port 11434. The binary at
`/opt/homebrew/bin/ollama` is a symlink into `Ollama.app/Contents/Resources`,
which is where `mlx_metal_v3` and `mlx_metal_v4` live too, so `ollama serve`
from the agent still resolves the MLX runners — the app is not needed for them.

Unlike systemd, **launchd is fine with a stowed symlink**: the "never
`systemctl enable` a stowed unit" hazard above has no launchd analogue.

Env vars live in the plist's `EnvironmentVariables` rather than in
`launchctl setenv`, which the Ollama docs suggest — setenv does not survive a
reboot and cannot be committed. Values in the plist apply at spawn, so there is
no ordering race and nothing to restart.

Logs go to `~/.local/state/ollama/server.log`; `launchctl print gui/$UID/com.dotfiles.ollama`
shows state.

MLX is not automatic — it is per model, and there are no `-mlx`/nvfp4 tags
published for the small models this host serves, so they run the GGUF path.
Confirm with `ollama ps`: `PROCESSOR` must read `100% GPU`, and any CPU share
means offload and much lower throughput.

## Consumers

`OLLAMA_HOST` (default `localhost`) is read by `nvim`'s `plugins/ai.lua` for
gen.nvim; `OLLAMA_URL` (default `localhost:11434`) by
`commands/.local/bin/sync-litellm-models`. Both come from
`~/.config/dotfiles/local.env`.

**`OLLAMA_HOST` MUST BE A BARE HOST, WITH NO PORT**, because three different
things read it and only the bare form is correct for all of them:

| Reader | Means |
| --- | --- |
| the Ollama server (plist above) | bind address — defaults the port |
| the `ollama` CLI | which server to talk to |
| nvim gen.nvim | a hostname, into which it formats `http://%s:%s` with 11434 |

The documented `OLLAMA_HOST=127.0.0.1:11434` gives gen.nvim
`http://127.0.0.1:11434:11434`. This is not theoretical in the other direction
either: with `OLLAMA_HOST` still pointing at the homelab, a plain `ollama pull`
on the laptop went to the homelab and timed out.

### Roles, not model names

`commands/.local/bin/ollama-role-aliases` (`mise run setup:ollama-roles`)
creates `role/completion` and `role/chat` as `ollama cp` copies. Consumers —
nvim, Continue, atuin-ai-server — name the role, never a tag, which is the same
indirection `sync-litellm-models` gives the homelab.

**Re-run it after any `ollama pull`.** `ollama cp` copies a manifest rather than
pointing at one, so re-pulling a base tag leaves the alias on the old weights
and says nothing.

### role/completion is re-pinned every 15 minutes, and the keep-alive cannot do it

`com.dotfiles.ollama-warm.plist` runs `commands/.local/bin/ollama-warm-roles` at
login and every 900 seconds after. It loads `role/completion` with
`keep_alive: -1`. Without it inline completion never returns one suggestion, and
the failure is invisible from the editor.

A cold load of the 3B takes about **17 seconds** on this host. Continue cancels
an inline-completion request after about **3**, and Ollama aborts a load when
its client disconnects:

```console
level=WARN msg="client connection closed before llama-server finished loading, aborting load"
```

So each keystroke starts a load that dies. The model never becomes resident, and
the next keystroke starts over. Measured 2026-09-04: **46 aborted loads and zero
`llama runner started` lines** in `server.log`, against 164 ms once warm.

`OLLAMA_KEEP_ALIVE` cannot break this. It applies after a load succeeds, and no
load succeeds.

**The interval is what makes it durable, not the `-1`.** Continue's requests omit
`keep_alive`, so Ollama applies the server default and *replaces* the pin —
`api/ps` then reports 30 minutes out, not the far-future date the pin sets. A
one-shot warm at login therefore lapses after the first idle half-hour. Re-pinning
on an interval shorter than `OLLAMA_KEEP_ALIVE` means the model can never unload,
whichever of the two wrote the current timer. Raise the keep-alive freely; do not
drop it below the 900 second interval.

Only `role/completion` is pinned. Chat is user-initiated, so it can pay a cold
load. A pin on chat as well would hold about 5 GB more.

Check it:

```sh
cat ~/.local/state/ollama/warm.log        # "ok  role/completion pinned"
launchctl print gui/$UID/com.dotfiles.ollama-warm | grep -E 'runs|interval'
curl -s http://127.0.0.1:11434/api/ps | jq -c '.models[] | {name, expires_at}'
```

What matters is that `role/completion` is listed at all, not how far out its
`expires_at` is — see the note above on why the pin gets overwritten. If the log
is empty, the `commands` package is not stowed.

On this machine [`llama-swap`](../llama-swap) is the primary serving layer —
ollama is kept for the models and tooling that only speak its API.
