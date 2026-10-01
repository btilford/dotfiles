# continue

[Continue](https://continue.dev) — chat and inline completion, pointed at this
machine's own Ollama. One global `~/.continue/config.json` serves IntelliJ,
VS Code and Continue's own nvim plugin.

## Why the config is IDE-agnostic

Continue reads `~/.continue/config.json` regardless of which editor loads it, so
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

### JetBrains 2026.2+: patch the plugin or nothing works

**Continue 1.0.67 does not run on IntelliJ 2026.2 unpatched.** Redo this on every
machine and after every plugin update. Symptom, in `idea.log`:

```console
SEVERE - ToolWindowManagerImpl - Cannot init toolwindow ContinuePluginToolWindowFactory
Caused by: java.lang.ClassNotFoundException: com.intellij.ui.jcef.JBCefApp
  PluginClassLoader(plugin=Continue 1.0.67)
```

JCEF moved out of the core platform classpath into the `com.intellij.modules.jcef`
module, and IntelliJ shows a module's classes only to plugins that declare a
dependency on it. Continue's `plugin.xml` declares `modules.platform`,
`plugins.terminal` and optional `modules.json` — not jcef — so its classloader
cannot see `JBCefApp`. Its whole UI and its config handshake are JCEF, so the
plugin is inert: no core process, no autocomplete, and the sidebar cannot draw.

Fix by adding the one missing line to the installed jar:

```sh
# IntelliJ must be CLOSED — it holds the jar open.
jar=~/"Library/Application Support/JetBrains/IntelliJIdea2026.2/plugins/continue-intellij-extension/lib/continue-intellij-extension-1.0.67.jar"
cp "$jar" "$jar.bak"
work=$(mktemp -d) && cd "$work" && mkdir -p META-INF
unzip -p "$jar" META-INF/plugin.xml \
  | sed 's|\(  <depends>org.jetbrains.plugins.terminal</depends>\)|\1\n  <depends>com.intellij.modules.jcef</depends>|' \
  > META-INF/plugin.xml
zip -q "$jar" META-INF/plugin.xml
unzip -p "$jar" META-INF/plugin.xml | grep depends    # must list modules.jcef
```

Revert with `cp "$jar.bak" "$jar"`. Adjust the IDE directory per product and
version; the plugin path is otherwise identical for GoLand, PyCharm and the rest.

**The runtime is a red herring, so do not chase it.** JetBrains Toolbox installs
a `-nomod` JBR here, and the missing-class error looks like a runtime fault. It
is not: the bundled `Web Browser (JCEF)` plugin loads fine on nomod, and swapping
to a `jbr_jcef` runtime does not clear the error. Verify with
`grep 'Loaded bundled plugins' idea.log | tr ',' '\n' | grep -i jcef`. Avoid the
`-fd` builds entirely — those are fastdebug, and the IDE is barely usable on one.

### Telemetry is ON by default, and the toggle is not where you would look

The plugin bundles `posthog` and `sentry` jars and ships with anonymous
telemetry **enabled** (`"default": true` in its own `config_schema.json`).

**It is not in the IDE's settings dialog.** Settings → Tools → Continue has six
controls and none of them is telemetry:

```text
Remote Config Server URL:                  blank is correct
Remote Config Sync Period (in minutes):    60
User Token:                                blank is correct
[ ] Enable Tab Autocomplete
[ ] Display Editor Tooltip
[ ] Show IDE completions side-by-side
```

The first and third belong to Continue's **remote config sync** — pulling
the config from a Continue-hosted or enterprise server. Fill either one and the
plugin stops reading your local file. They are not the model endpoint; that is
`apiBase` in `config.json`.

The telemetry toggle is rendered by the plugin's **webview**, in Continue's own
settings page:

> Continue sidebar → settings (gear) → **Telemetry** section, just above
> **Appearance** → turn off **Allow Anonymous Telemetry**

It can be shown disabled when an org or hub policy controls it.

`allowAnonymousTelemetry: false` **is** set in `config.json`, which the flag
belongs to — it is absent from the YAML schema, which is one more reason this
package is on JSON. Do not trust it on its own: upstream has had the flag
reported as ineffective
([continuedev/continue#2082](https://github.com/continuedev/continue/issues/2082)),
so turn the webview toggle off as well.

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

### This package uses config.json, and that is the whole reason

`tabAutocompleteOptions` is a **`config.json` key with no `config.yaml`
equivalent**. Tested 2026-09-04: set in `config.yaml`, core restarted so the file
was re-read, and the effective value did not move.

```console
$ tail -1 ~/.continue/dev_data/0.2.0/autocomplete.jsonl | jq -c '{maxPromptTokens}'
{"maxPromptTokens":1024}          # after setting 4096 in config.yaml
```

It is **ignored, not rejected** — no validation error, completions keep working —
so a value set there looks applied and never is. The plugin's own
`~/.continue/config_schema.json` self-identifies as `config.json`, which is what
makes this easy to get wrong: the schema sitting beside the config does not
describe it.

That knob is worth the format. Continue's default budget of 1024 tokens at
`prefixPercentage 0.3` gives the model about 1200 characters, and at that size a
3B does not complete code, it repeats the line above or redeclares a variable
that already exists further up the file. Measured on a 115-line Kotlin file,
same model and temperature, with the true continuation removed from the suffix:

| prefix given | completion |
| --- | --- |
| ~1200 chars | `val storeHash = "abc123"` — redeclares an existing val |
| ~2900 chars | `stubGetStoreSuccess(storeHash = storeHash)` — correct call, reuses the val |

**Cost of raising it is latency, and it is roughly linear.** Prompt eval
dominates, so a bigger window is paid on every keystroke. Measured against a
26 KB file with the cursor three quarters in:

| `maxPromptTokens` | prefix | latency |
| --- | --- | --- |
| 1024 | 2 KB | 891 ms |
| 2048 | 4 KB | 2.4 s |
| 4096 | 8 KB | 3.6 s |
| 6144 | 12 KB | 4.7 s |

`2048` is the setting here. `4096` was tried first and produced a 6.25 s
round trip on a real file — long enough that every suggestion was cancelled by
the next keystroke. Drop to `1024` if it feels slow: with
`prefixPercentage 0.5` that is still 2 KB of prefix, which is above the point
where the completions stopped being wrong, at the latency the old config had.

**Re-measure rather than trusting this table.** Every completion appends its
effective options, prompt, completion and accepted flag to
`~/.continue/dev_data/0.2.0/autocomplete.jsonl`, so the answer for your file and
your hardware is one keystroke away.

### The config file holds no comments

JSON has no comment syntax, so the reasoning that used to live beside each key is
in this README instead: [why 127.0.0.1 is hardcoded](#why-127001-is-hardcoded-here),
[models are roles](#models-are-roles), and
[no embedding model](#no-embedding-model-is-declared). Keep them in step — a key
changed here without its paragraph is a key nobody can explain later.

`context` in the old YAML is `contextProviders` in JSON, and the chat model's
`roles:` list has no JSON equivalent: `models` are the chat, edit and apply
models, and `tabAutocompleteModel` is a separate single entry.

### Dead autocomplete is an Ollama fault, not a config fault

Both checks above can pass while inline completion returns nothing, so a silent
autocomplete is not evidence that the IDE missed this file. Read the status
codes rather than the request paths:

```sh
grep -a '/v1/chat/completions' ~/.local/state/ollama/server.log \
  | awk -F'|' '{gsub(/ /,"",$2); print $2}' | sort | uniq -c
```

A wall of **499** means Continue cancelled each request before Ollama answered —
the cold-load deadlock described in [`ollama/README.md`](../ollama/README.md).
The fix is `ollama-warm-roles`, which the LaunchAgent runs at login. Check that
the model is pinned before you read anything else in this file:

```sh
curl -s http://127.0.0.1:11434/api/ps | jq -c '.models[] | {name, expires_at}'
```

## Why 127.0.0.1 is hardcoded here

Every other machine-specific endpoint in this repo resolves from the
environment, because a private hostname must not be published. This file is the
exception, deliberately:

- a loopback address names no host but this one, so it is not infrastructure
  disclosure
- Continue's local config has no dependable env-var interpolation, so the
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
