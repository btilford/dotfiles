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
| `config/Notifications.qml` | `Notifications` singleton: the `org.freedesktop.Notifications` server, live popup model, expiry, and the epic's config/rules/store seams. |
| `components/NotificationOverlay.qml` + `components/notifications/` | Popup stack view. Pure view over `Notifications.popups`. |
| `components/ClipboardDialog.qml` | **Thin wrapper** over the dialog shipped by the clipborg repo (`examples/quickshell/Clipborg`). Host glue only. State in the `Clipboard` singleton; IPC `qs ipc call clipboard toggle`; bound to `SUPER+V`. |
| `config/Theme.qml` + `config/qmldir` | `Theme` singleton: terminal-flavored tokens; reads the wallust palette. |
| `wallust/.gitkeep` | Runtime `colors.json` lands here (generated, gitignored). |

## Increments

launcher (done) → bar → notifications → lock → OSD → dashboard. Each new component is added
to `shell.qml`. Per-monitor widgets use `Variants { model: Quickshell.screens }` (goal:
clock on the vertical monitors).

## Launcher

- Modes: **combi** (default: apps + `run: <query>` fallback), **drun** (apps), **run**
  (`$PATH` autocomplete via `compgen -c`), **files** (`FolderListModel` browse),
  **wallpaper** (thumbnails from `scripts/list-wallpapers.sh`; Enter applies via the
  `hyprland` package's `WallpaperApply.sh` — awww/mpvpaper + wallust + live hypr colors;
  `. random` first row for rofi parity).
- Launch: apps → `DesktopEntry.execute()`; run → `Quickshell.execDetached(["sh","-lc",cmd])`
  (detached/disowned); files → `xdg-open`.
- Prefixes: `>` run, `/` or `~` files, `:` emoji, `;` glyphs, `#` icons, `!` wallpaper.
  `Tab` cycles modes.
- Shown/hidden via IPC: `qs ipc call launcher toggle [mode]` (from `hypr/scripts/Launcher.sh`).
- Placed on `Hyprland.focusedMonitor`.

## ClipboardDialog

clipborg history dialog (clipborg daemon over `$XDG_RUNTIME_DIR/clipborg.sock`).
Search + flat/tree list + preview pane + actions/llm/pin/delete/bulk-delete. State lives in the
`Clipboard` singleton (`config/Clipboard.qml`).

- **The clipborg repo is canonical; this package holds a wrapper.** The dialog lives at
  `<clipborg>/examples/quickshell/Clipborg/ClipboardDialog.qml` as a `Clipborg` QML module.
  `components/ClipboardDialog.qml` subclasses it and supplies host glue only: `shown` /
  `closeRequested` (the `Clipboard` singleton), `targetScreen` (`Hyprland.focusedMonitor`),
  `theme` (the wallust `Theme` singleton), and the shader decorations
  (`boxEffect`/`boxUnderlay`/`highlightEffect` → EnergyBorder/Shimmer/Reflection/EnergyFill).
  **Fix dialog behaviour upstream in clipborg, not here** — if a change doesn't fit those
  seams, widen the seams upstream rather than forking the QML back into dotfiles.
- **How the module is found:** `QML_IMPORT_PATH` in `hypr/lua/environments.lua`, defaulting to
  `~/Projects/public/clipborg/examples/quickshell` and overridable with `CLIPBORG_QML_PATH`.
- **Why `shell.qml` loads it through a `LazyLoader`:** `import Clipborg` is fatal if the clone
  isn't on the machine, and an inline component's failed import aborts the *entire* shell config
  (no bar, no launcher). Inside a LazyLoader the blast radius is just the dialog. Don't inline it.

- **Actions vs LLM are separate clipborg concepts.** `actions` (`Ctrl+A`) are fire-and-forget
  spawns (`act` op). `[llm]` prompts (`Ctrl+L`) are a different op family: `llm_prompts` lists the
  prompts whose categories match the entry, `llm_harnesses` lists the harnesses plus the one this
  prompt resolves to (the `h` key's override list), `llm` runs one (`{id, prompt, harness?, mode?}`;
  omit `mode` to honour the `[llm]`/per-prompt default — `foreground` is rejected over IPC since
  it needs a terminal), and `llm_insert` stores a result after the fact. The `llm` op runs the
  harness **synchronously and blocks its connection**, so it is fired on a dedicated `llmSocket`,
  never the main list/get socket.
- **Keep this dialog in sync with the clipborg TUI.** They are two front-ends over the same IPC;
  a feature landing in one belongs in the other. Current llm parity: `Enter` run, `t` background
  tmux, `h` harness override, result view with `c` copy / `i` store / Esc discard. (`T`/foreground
  is TUI+CLI only — exec-replace needs a terminal.)

- Toggle: `qs ipc call clipboard toggle` — bound to **SUPER+V** (and `SUPER+o` `v` in the
  `open-cmd` submap), both with a `|| clipborg tui` fallback for hosts with no qs daemon.
  Launcher's clip mode (the `,` prefix, its clipborg sockets, tree/pin/bulk UI and popups) is
  **removed** — this dialog is the only clipboard UI. Don't re-add clip mode to Launcher.
- **LLM results are displayed, not lost.** The `llm` reply carries the harness text as `output`
  (clipborg ≥ the llm-v2 work), so the result view renders it directly — no `get` round-trip, and
  it works with `insert_result = false` (now clipborg's default: nothing is stored unless the user
  presses `i`, which fires `llm_insert`). `entry_id` in the reply is set only when an
  `insert_result = true` prompt auto-inserted it. tmux-mode prompts are background: it notify-sends
  `tmux attach -t <session>` rather than stranding them.
- **A dead quickshell Socket never re-dials.** When clipborg restarts, the peer close surfaces via
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

## Notifications

`org.freedesktop.Notifications` server (story: notif-dbus-server, first of the notifications
epic). Everything that isn't pixels lives in the `Notifications` singleton; `NotificationOverlay`
is a view over `Notifications.popups` and holds no state. Keep that split — the SQLite store and
the terminal clients need the model to exist without a window.

- **Opt-in per machine:** `HYPR_NOTIFY=quickshell` in `~/.config/hypr/shell.local.env`. The
  `NotificationServer` sits in a `Loader` gated on it, so a machine that hasn't opted in never
  claims the D-Bus name. Only one process can own that name — start order decides, and while qs
  holds it swaync cannot be D-Bus activated back. Swap backends: set the key, then
  `pkill swaync` (or `systemctl --user stop swaync`) and restart `qs`.
- **Capabilities are advertised honestly.** `GetCapabilities` returns `body` + `icon-static` and
  nothing else. Do not flip `actionsSupported` / `bodyMarkupSupported` / `inlineReplySupported`
  until those stories actually render them — clients change what they send based on this.
- **Entry fields are bindings, not copies (load-bearing).** `replaces_id` does *not* re-emit the
  `notification` signal: quickshell mutates the existing `Notification` object in place. An entry
  that copied `summary`/`body`/hints at creation shows the first revision forever (progress bars
  freeze at their opening value). Every field on the entry binds through `entry.notification`.
- **`transient` is a reserved QML keyword** — the entry property is `isTransient`. Declaring
  `property bool transient` fails config load outright.
- Expiry routes through `Notifications.refresh()` → `defaultDurationMs()` → `scheduleExpiry()`,
  one place, because hover-pause and burst-shortening (timing story) land there next. Duration 0
  = sticky. `rulesHook` is the rules-engine seam and **fails open**: a throwing hook logs and the
  notification displays with defaults.
- IPC: `qs ipc call notifications dismissAll` / `count` (the seam the `notifctl` CLI grows from).
- Deliberately **not** here yet: actions, keyboard focus (popups use
  `WlrKeyboardFocus.None` on purpose), drawer/history, DND, grouping.

### Placement & motion (story: notif-placement-motion)

User config, not QML constants: `~/.config/quickshell/notifications.json`, parsed by the
`NotifyConfig` singleton and hot-reloaded on save (`notifications.example.json` in this package
is the annotated template). `QS_NOTIFY_CONFIG=<path>` overrides the path — the seam the capture
harness uses to switch presets without touching the user's file — and `QS_NOTIFY_PRESET=<name>`
overrides the preset alone. **Every key falls back to the constants in `NotifyConfig`**, so a
missing or broken file can never take the shell down; bad values log once and keep the default.

- Presets: `right-center` (default), `bottom-center`, `top-right`. Default is deliberately not a
  top corner — that is where application toolbars and window buttons live.
- `NotificationOverlay` renders **one window per (monitor, anchor) pair** in use. Entries carry
  `screenName`/`anchorH`/`anchorV`, so a rule can pin one source elsewhere; `screenName: ""`
  follows the focused monitor, and a named monitor that is unplugged falls back to it.
- The stack windows are **full-screen with `ExclusionMode.Ignore`**, so window coordinates are
  screen coordinates and a card can fly across the bar. Input is confined to the cards by
  `mask: Region { item: column }` — never remove that mask, or the notification layer swallows
  every click on the desktop.
- **Dwell:** on timeout the card flies into the bar bell (`components/bar/NotificationBell.qml`,
  which publishes its position per monitor into `Notifications.bellAnchors`). The D-Bus close
  fires at the END of the flight — `notification.expire()` drops the entry and would take the
  card with it. With no bell on screen the exit degrades to the plain slide/fade.
- **The exit animation is explicit `ParallelAnimation`s, not `Behavior`s.** A Behavior reads its
  duration and easing when it starts, and bindings feeding those from the same flag that
  triggered it are re-evaluated in no guaranteed order: half the properties animated over the
  dwell duration and half over the entrance one, and the card was invisible for most of a flight
  that was otherwise working. Don't "simplify" these back into Behaviors.
- **A leaving card is reparented into a full-window flight layer.** Its slot collapses to zero
  height so the cards below close the gap, and a card animating out of a zero-height parent
  inside a positioner keeps animating but is never presented.
- Overflow: `placement.maxVisible` per stack, the rest stay in the model as `queued` behind a
  `+N more` indicator. **A queued entry's expiry timer is not running** — its dwell starts when
  it reaches the screen, so nothing expires unseen.
- `expireTimeout` from the wire is **milliseconds** (spec), not seconds.

### Testing notifications without a Hyprland session

Popups need a compositor, and the D-Bus name is per-session-bus, so the test rig is a nested
headless sway on a **private** bus:

```sh
env -u WAYLAND_DISPLAY -u DISPLAY WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
  dbus-run-session -- sway -c /tmp/sway.conf   # sway.conf: exec <your test script>
# inside: qs -p <config>/shell.qml, notify-send ..., grim -o HEADLESS-1 shot.png
```

**Always force the headless backend and never point a compositor at the real seat.** A compositor
started without `WLR_BACKENDS=headless` (Hyprland: also `AQ_HEADLESS_ONLY=1`) grabs DRM master and
kills the live session and every app in it.

## Daemon lifecycle

The single `qs` daemon must run whenever `$HYPR_BAR` or `$HYPR_LAUNCHER` = quickshell (see the
`hyprland` package: `hypr/scripts/StartShell.sh`, `Launcher.sh`, `autostart.lua`). Toggle the
active bar/launcher per machine in `~/.config/hypr/shell.local.env` (not stowed).

### `shell.local.env` keys (parsed by `config/Shell.qml`, live-reload on save)

| Key | Values | Effect |
|-----|--------|--------|
| `HYPR_BAR` | `waybar` \| `quickshell` | which bar renders |
| `HYPR_LAUNCHER` | `rofi` \| `quickshell` | which launcher `Launcher.sh` targets |
| `HYPR_BAR_DEV` | `1` | qs bar at the bottom, no exclusive zone, alongside waybar |
| `HYPR_NOTIFY` | `swaync` (default) \| `quickshell` | which process owns `org.freedesktop.Notifications` |
| `QS_EFFECTS` | `full` (default) \| `low` \| `off` | `off` = shaders never instantiated (Loader-gated); static themed fallbacks: accent Rectangle/Shape borders, flat accent fills, no shimmer/reflection/glyph lava. `low` reserved, currently = `full`. |

Border weights are Theme tokens: `Theme.borderThickness` (energy borders) and `Theme.borderThin`
(static hairlines). Don't hardcode border thickness in components.

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
