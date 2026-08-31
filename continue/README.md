# continue

[Continue](https://continue.dev) — chat and inline completion, pointed at this
machine's own Ollama. One global `~/.continue/config.yaml` serves IntelliJ,
VS Code and Continue's own nvim plugin.

## Why the config is IDE-agnostic

Continue reads `~/.continue/config.yaml` regardless of which editor loads it, so
nothing here depends on where the IDE is installed — which matters on a machine
where IntelliJ comes from JetBrains Toolbox and its path is not fixed. Only the
plugin install is per-IDE, and that is a marketplace click.

## Per-machine bootstrap

Install the plugin from the IDE's marketplace, then **turn its telemetry off**.
The config itself arrives by stow.

- IntelliJ: Settings → Plugins → Marketplace → "Continue"
- VS Code: the `Continue.continue` extension

One `~/.continue` serves every JetBrains IDE on the machine — IntelliJ, GoLand,
DataGrip, PyCharm and WebStorm all read the same file.

### Telemetry is ON by default, and the toggle is not where you would look

The plugin bundles `posthog` and `sentry` jars and ships with anonymous
telemetry **enabled** (`"default": true` in its own `config_schema.json`).

**It is not in the IDE's settings dialog.** The plugin's IntelliJ settings class
holds exactly two fields, `shownWelcomeDialog` and `displayEditorTooltip`, so
there is nothing to find under Settings → Tools. The toggle is rendered by the
plugin's **webview**, in Continue's own settings page:

> Continue sidebar → settings (gear) → **Telemetry** section, just above
> **Appearance** → turn off **Allow Anonymous Telemetry**

It can be shown disabled when an org or hub policy controls it.

Not set in `config.yaml` here on purpose: `allowAnonymousTelemetry` is a key of
the `config.json` and `.continuerc.json` schemas, both of which the plugin ships;
neither is the YAML schema. An unknown key risks failing validation for the whole
file, and upstream has had the flag reported as ineffective anyway
([continuedev/continue#2082](https://github.com/continuedev/continue/issues/2082)),
so the toggle is the honest instruction.

This matters more here than it normally would: the point of pointing Continue at
127.0.0.1 is that nothing leaves the machine, and the plugin's own reporting is a
separate channel from the model traffic.

### Confirming the YAML is actually in use

Continue 1.x can also load assistants from its hub, so "is it reading this file"
is a fair question. Two checks that answer it without guessing:

```sh
jq .selectedModelsByProfileId ~/.continue/index/globalContext.json
grep -a '/v1/chat/completions' ~/.local/state/ollama/server.log | tail
```

The first should name the `name:` values from this file — `Local chat`,
`Local autocomplete` — under a `local` profile. The second should show Ollama
serving requests from 127.0.0.1. If the first shows hub assistant names instead,
the profile picker in the sidebar is on a hub assistant, not `local`.

## Why 127.0.0.1 is hardcoded here

Every other machine-specific endpoint in this repo resolves from the
environment, because a private hostname must not be published. This file is the
exception, deliberately:

- a loopback address names no host but this one, so it is not infrastructure
  disclosure
- Continue's local `config.yaml` has no dependable env-var interpolation, so the
  alternative is an untracked file holding a value that is safe to publish
- hardcoding it means the file cannot quietly be repointed at a remote endpoint

## Models are roles

`role/chat` and `role/completion` are Ollama aliases, not model tags — see
`commands/.local/bin/ollama-role-aliases`. Each host decides what they resolve
to, so this file does not change when the weights do.

`role/completion` is deliberately the small model. It sits behind a keystroke,
so time to first token beats capability: measured 171 ms warm on this host
against 213 ms for the 7B.

## No embedding model is declared

Continue falls back to its bundled local embedder, which keeps indexing on this
machine. Naming a remote embedding model here would ship repository content off
the host on every index — the exact thing this setup exists to avoid.
