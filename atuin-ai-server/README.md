# atuin-ai-server

Self-hosted server for Atuin AI, backed by a local OpenAI-compatible endpoint.
Upstream: [atuinsh/atuin-ai-server](https://github.com/atuinsh/atuin-ai-server).

## Why this package exists at all

The atuin client speaks the **Atuin AI protocol**, not OpenAI. It cannot be
pointed at Ollama directly, so `ai.endpoint` in the atuin config is this server,
not the model. This server is the translator, and it is the supported one: it
runs the same engine as the hosted Atuin AI, composed with stateless defaults —
no accounts, no database, no usage limits, no recording.

The chain is:

```text
atuin ai / how  ->  atuin-ai-server  ->  Ollama        ->  role/chat
                    127.0.0.1:8080       127.0.0.1:11434
```

## Files

| File | Purpose |
| --- | --- |
| `.config/atuin-ai-server/config.toml` | Server config: the upstream endpoint, the port, and the `[[models]]` alias table. |
| `.config/atuin-ai-server/compose.yaml` | How it runs. Image pinned by digest, published on loopback only. |

## Running it

```bash
mise run setup:atuin-ai-server      # docker compose up -d
docker logs atuin-ai --tail 20
```

Per machine, not per clone — it starts a container, which is machine state.

## Two things that are load-bearing

**The port publish is the security boundary.** The server has no auth by
default, so `127.0.0.1:8080:8080` is what stops it being an unauthenticated LLM
gateway on the corporate LAN. A bare `8080:8080` publishes on every interface.
`AUTH_TOKEN` exists and is off; on a loopback-only service it is defence in
depth rather than the boundary, and if it is ever enabled the token is a
credential and goes through `dotfiles-secrets`, never `local.env`.

**`host.docker.internal` is how the container reaches a loopback-bound Ollama,
and that is a macOS-runtime behaviour.** Inside the container, `127.0.0.1` is
the container. The Mac runtimes — OrbStack here, Docker Desktop the same way —
resolve this name to the host and originate the connection host-side, so it
reaches an Ollama listening only on 127.0.0.1. Verified here: it returns the
version handshake. **Linux does not behave this way**, so do not copy that line
to the homelab; there the container would need host networking or a bridge
address.

## Aliases, not model names

`[[models]]` maps an alias to a model, and the atuin client asks for the alias
(`ATUIN_AI__MODEL=chat`). What the alias resolves to is `role/chat`, which is
itself an Ollama alias — see `commands/.local/bin/ollama-role-aliases`. So there
are two layers of indirection and no consumer names a concrete model. Changing
the weights is a `mise run setup:ollama-roles`, with nothing else touched.

## Refreshing the pinned image

The tag is deliberately not `:latest` — a tag is mutable and can be repointed at
new code with no commit here. To move it forward:

```bash
docker pull ghcr.io/atuinsh/atuin-ai-server:latest
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/atuinsh/atuin-ai-server:latest
```

Then paste the digest into `compose.yaml` and re-run the mise task.
