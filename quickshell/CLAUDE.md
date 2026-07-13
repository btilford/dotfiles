# quickshell package

Context for AI agents working on this stow package. Not stowed (excluded by `.stow-local-ignore`).

## What this package manages

A DIY quickshell desktop shell, built incrementally to replace the waybar/rofi stack (and
later swaync/hyprlock/OSD). Targets **stable quickshell 0.3.0** (Arch repo) — NOT
`quickshell-git`. One persistent `qs` process hosts every component.

Installs to `~/.config/quickshell/` (the default config, so bare `qs` and `qs ipc` target it
with no `-c` flag).

| Path | Purpose |
|------|---------|
| `shell.qml` | Root `ShellRoot`. Instantiates components + the `launcher` `IpcHandler`. |
| `components/Launcher.qml` | Multi-mode launcher (combi/drun/run/files), replaces rofi. |
| `components/ClipboardDialog.qml` | **Thin wrapper** over the dialog shipped by the clipvault repo (`examples/quickshell/Clipvault`). Host glue only. State in the `Clipboard` singleton; IPC `qs ipc call clipboard toggle`; bound to `SUPER+V`. |
| `config/Theme.qml` + `config/qmldir` | `Theme` singleton: terminal-flavored tokens; reads the wallust palette. |
| `wallust/.gitkeep` | Runtime `colors.json` lands here (generated, gitignored). |

## Increments

launcher (done) → bar → notifications → lock → OSD → dashboard. Each new component is added
to `shell.qml`. Per-monitor widgets use `Variants { model: Quickshell.screens }` (goal:
clock on the vertical monitors).

## Launcher

- Modes: **combi** (default: apps + `run: <query>` fallback), **drun** (apps), **run**
  (`$PATH` autocomplete via `compgen -c`), **files** (`FolderListModel` browse).
- Launch: apps → `DesktopEntry.execute()`; run → `Quickshell.execDetached(["sh","-lc",cmd])`
  (detached/disowned); files → `xdg-open`.
- Prefixes: `>` run, `/` or `~` files. `Tab` cycles modes.
- Shown/hidden via IPC: `qs ipc call launcher toggle [mode]` (from `hypr/scripts/Launcher.sh`).
- Placed on `Hyprland.focusedMonitor`.

## ClipboardDialog

clipvault history dialog (clipvault daemon over `$XDG_RUNTIME_DIR/clipvault.sock`).
Search + flat/tree list + preview pane + actions/llm/pin/delete/bulk-delete. State lives in the
`Clipboard` singleton (`config/Clipboard.qml`).

- **The clipvault repo is canonical; this package holds a wrapper.** The dialog lives at
  `<clipvault>/examples/quickshell/Clipvault/ClipboardDialog.qml` as a `Clipvault` QML module.
  `components/ClipboardDialog.qml` subclasses it and supplies host glue only: `shown` /
  `closeRequested` (the `Clipboard` singleton), `targetScreen` (`Hyprland.focusedMonitor`),
  `theme` (the wallust `Theme` singleton), and the shader decorations
  (`boxEffect`/`boxUnderlay`/`highlightEffect` → EnergyBorder/Shimmer/Reflection/EnergyFill).
  **Fix dialog behaviour upstream in clipvault, not here** — if a change doesn't fit those
  seams, widen the seams upstream rather than forking the QML back into dotfiles.
- **How the module is found:** `QML_IMPORT_PATH` in `hypr/lua/environments.lua`, defaulting to
  `~/Projects/public/clipvault/examples/quickshell` and overridable with `CLIPVAULT_QML_PATH`.
- **Why `shell.qml` loads it through a `LazyLoader`:** `import Clipvault` is fatal if the clone
  isn't on the machine, and an inline component's failed import aborts the *entire* shell config
  (no bar, no launcher). Inside a LazyLoader the blast radius is just the dialog. Don't inline it.

- **Actions vs LLM are separate clipvault concepts.** `actions` (`Ctrl+A`) are fire-and-forget
  spawns (`act` op). `[llm]` prompts (`Ctrl+L`) are a different op family: `llm_prompts` lists the
  prompts whose categories match the entry, `llm_harnesses` lists the harnesses plus the one this
  prompt resolves to (the `h` key's override list), `llm` runs one (`{id, prompt, harness?, mode?}`;
  omit `mode` to honour the `[llm]`/per-prompt default — `foreground` is rejected over IPC since
  it needs a terminal), and `llm_insert` stores a result after the fact. The `llm` op runs the
  harness **synchronously and blocks its connection**, so it is fired on a dedicated `llmSocket`,
  never the main list/get socket.
- **Keep this dialog in sync with the clipvault TUI.** They are two front-ends over the same IPC;
  a feature landing in one belongs in the other. Current llm parity: `Enter` run, `t` background
  tmux, `h` harness override, result view with `c` copy / `i` store / Esc discard. (`T`/foreground
  is TUI+CLI only — exec-replace needs a terminal.)

- Toggle: `qs ipc call clipboard toggle` — bound to **SUPER+V** (and `SUPER+o` `v` in the
  `open-cmd` submap), both with a `|| clipvault tui` fallback for hosts with no qs daemon.
  Launcher's clip mode (the `,` prefix, its clipvault sockets, tree/pin/bulk UI and popups) is
  **removed** — this dialog is the only clipboard UI. Don't re-add clip mode to Launcher.
- **LLM results are displayed, not lost.** The `llm` reply carries the harness text as `output`
  (clipvault ≥ the llm-v2 work), so the result view renders it directly — no `get` round-trip, and
  it works with `insert_result = false` (now clipvault's default: nothing is stored unless the user
  presses `i`, which fires `llm_insert`). `entry_id` in the reply is set only when an
  `insert_result = true` prompt auto-inserted it. tmux-mode prompts are background: it notify-sends
  `tmux attach -t <session>` rather than stranding them.
- **A dead quickshell Socket never re-dials.** When clipvault restarts, the peer close surfaces via
  `onError` but `connected` stays true; writes then vanish ("QIODevice::write: device not open") and
  the dialog opens empty (0 results) until `qs` itself restarts. Re-asserting `connected = true` and
  re-setting `path` both do nothing (verified against a real daemon restart). The fix: each Socket
  lives in a `Loader`, and `onError` schedules a respawn that cycles `Loader.active` to build a NEW
  Socket. Don't "simplify" the Loaders away.
- URL prompts need a fetch-capable harness: plain `claude -p` has no tool grants and just refuses.
  `claude-web` (`claude -p --allowedTools WebFetch`) exists for that; `summarize-url` uses it,
  while plain `summarize` is scoped to local content (code/file-path/files).
- Fullscreen `WlrLayer.Overlay` on `Hyprland.focusedMonitor`, `WlrKeyboardFocus.Exclusive`.
- **Never shadow Item's built-in `data` property (load-bearing lesson):** the dialog once declared
  `property var data` for its socket results. `data` is Item's *default property* (children +
  resources); shadowing it corrupted the window's content tree so the layer surface never gained
  keyboard activation — `Window.active` stayed false, Qt dropped every key, and under the Exclusive
  grab the physical keyboard was held with nothing able to release it = whole-session lockout
  (killall/logout). Mouse kept working (pointer events don't need activation). Fixed by renaming to
  `clipData`. Avoid `data`/`children`/`resources`/`state`/`visible` as property names.
  Belt-and-suspenders also kept: window-scope `Shortcut { StandardKey.Cancel → Clipboard.close() }`
  and `activeFocusOnPress: false` on the preview `TextEdit`, plus the click-away backdrop.
  Diagnostics: throwaway `qs -p harness.qml` with `WlrKeyboardFocus.None` (never grabs → safe);
  probe `item.Window.active`; `qs log -f -i <id> -r "*=true"` to see qml debug; `wtype -k Escape`
  injects real keys into an exclusive layer (`hyprctl send_shortcut` can't). See the
  `quickshell-exclusive-grab-lockout` memory.

## Daemon lifecycle

The single `qs` daemon must run whenever `$HYPR_BAR` or `$HYPR_LAUNCHER` = quickshell (see the
`hyprland` package: `hypr/scripts/StartShell.sh`, `Launcher.sh`, `autostart.lua`). Toggle the
active bar/launcher per machine in `~/.config/hypr/shell.local.env` (not stowed).

## Theming

`Theme.qml` fallback constants come from `ghostty/.config/ghostty/config` and `.tmux.conf`
(bg `#1a0808`, fg `#cdd6f4`, accent `#ff6600`, JetBrains Mono, translucent + blur). The live
palette is read from `~/.config/quickshell/wallust/colors.json`, generated by the `wallust`
package template `colors-quickshell.json` on every wallpaper switch (`WallustSwww.sh`), and
hot-reloads via `FileView.watchChanges`. Orange `#ff6600` is pinned as accent by default
(`Theme.pinAccent`); set false to follow the wallpaper.

## Runtime dependencies

The shell shells out to / reads from several system services and apps. All are packages, not
Hyprland plugins — nothing needs `hyprpm`. Hyprland's lua config + `scrolling` layout are
**mainline** (this host: `hyprland` 0.55.4), so no fork/plugin is required for LayoutMode.

| Need | Package (Arch) | Used by |
|------|----------------|---------|
| `qs` binary | `quickshell` (stable 0.3.0 — **not** `-git`) | everything |
| Bar glyphs | `ttf-jetbrains-mono-nerd` (JetBrainsMono Nerd Font) | all icons; missing → tofu/blank |
| Hyprland lua API + `scrolling` layout + `hyprctl` | `hyprland` ≥ 0.55 (mainline) | LayoutMode (`hl.workspace_rule`), Keymap (`hyprctl binds -j`), Workspaces/WindowList dispatch |
| Audio | `pipewire` (+ `wireplumber`) running | Audio (`Quickshell.Services.Pipewire`) |
| Network | `networkmanager` running | Network (`Quickshell.Networking`) |
| Bluetooth | `bluez` + `bluez-utils` running | Bluetooth (`Quickshell.Bluetooth`) |
| Battery | `upower` running | Battery (laptop only) |
| Session actions | `systemd` (`systemctl`/`loginctl`) | SessionOverlay |

Right-click "manage" launchers (each a configurable `manageCmd` on the module — swap freely):
`pavucontrol` (Audio), `nm-connection-editor` from `network-manager-applet` (Network),
`blueman` → `blueman-manager` (Bluetooth).

Optional: `wlogout` — fallback for `SUPER+Escape` when the qs daemon isn't running (see
`hyprland` `lua/keybindings.lua`).

Modules degrade gracefully when a daemon is absent (icon hidden / "No adapter" / empty popout);
they don't hard-fail.

## Rules

- No absolute paths in QML — use `Quickshell.env("HOME")`.
- Stow with `--no-folding` so `wallust/` stays a real dir and the runtime `colors.json` coexists.
- Do not commit `wallust/colors.json`.
- Keep working on **stable** qs 0.3.0; do not introduce `quickshell-git`-only APIs.
