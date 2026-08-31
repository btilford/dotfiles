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

### Telemetry is ON by default, and it is not in this file

The plugin bundles `posthog` and `sentry` jars and ships with anonymous
telemetry **enabled**. That is an IDE-level setting, not a `config.yaml` key, so
this repo cannot turn it off for you:

> Settings → Tools → Continue → uncheck **Allow Anonymous Telemetry**

It lands in `ContinueExtensionSettings.xml` in the IDE's own options directory,
which the IDE rewrites on exit — so it is not a file to hand-edit or track.

`allowAnonymousTelemetry: false` is the equivalent key in the older
`config.json`. It is deliberately **not** set in `config.yaml` here: it is not a
documented key of that schema, an unknown key risks failing validation for the
whole file, and upstream has had it reported as ineffective anyway
([continuedev/continue#2082](https://github.com/continuedev/continue/issues/2082)).
Use the checkbox.

This matters more here than it normally would: the point of pointing Continue at
127.0.0.1 is that nothing leaves the machine, and the plugin's own reporting is a
separate channel from the model traffic.

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
