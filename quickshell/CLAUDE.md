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

## Submap hints (which-key)

`components/SubmapHints.qml` — entering a Hyprland submap pops a translucent slab at the bottom
of the focused monitor listing that map's binds. Complements the bar badge
(`components/bar/Submap.qml`), which stays: the badge is persistent ambient state ("you are in a
submap") and survives the show-delay; the overlay is the transient detail.

- **The surface is passive, and that is the whole design.** `WlrKeyboardFocus.None` *and*
  `mask: Region {}`. Hyprland owns the keys while a submap is active — a grab would stop the
  submap's own binds firing, and an exclusive grab resets the live submap outright (that is why
  `KeymapOverlay` has to snapshot `Keymap.filterSubmap`). Keyboard focus is only half of it: a
  layer surface with a default input region swallows every pointer event over its area, and this
  one lies across the bottom of the screen. Nothing in it is clickable, so nothing is carved out.
- **Binds are cached, invalidated on `configreloaded`** in `Keymap.qml`'s existing `onRawEvent`
  block — not a TTL, which is either too short (pointless subprocesses) or too long (stale
  hints). `Keymap.load()` runs `hyprctl binds -j`, a subprocess round trip that the fullscreen
  cheatsheet can afford on every `open()` and this surface cannot, since it must appear the
  instant a submap is entered. Belt-and-braces: an empty `binds` when a submap opens loads on
  demand.
- Borderless glass at `Shell.submapHintsOpacity` (0.35), depth from `Elevation` — so it
  carries the same **compositor-blur dependency as the drawer**: the layer rule for
  `quickshell-submap-hints` in `hypr/lua/windowrules.lua` is what makes 0.35 frosted rather
  than unreadable. It read `NotifyConfig.drawer.opacity` until 2026-08-04; that coupled two
  unrelated surfaces, so tuning the hints for legibility restyled the notification drawer too.
- **Wide and short, and lifted off the bottom edge.** Layout is driven by width — as many
  columns as fit across 94% of the monitor, rows falling out of that — because the
  height-driven original rendered a normal map as one tall narrow column, the shape which-key
  exists to avoid. `ExclusionMode.Ignore` means nothing reflows out of the way, so
  `margins.bottom` also clears ~6 text rows: at `Theme.pad` the slab landed on top of a
  full-height terminal's prompt and tmux status line. Both the margin and the cell widths are
  expressed in `textSize` units so a font change cannot silently break either.
- Binds entering a *nested* submap are rendered as which-key `+prefix` groups via
  `Keymap.submapEntry(b)`.
- Config: `QS_SUBMAP_HINTS` / `QS_SUBMAP_HINTS_DELAY` in `shell.local.env` (see below).

## Notifications

`org.freedesktop.Notifications` server (story: notif-dbus-server, first of the notifications
epic). Everything that isn't pixels lives in the `Notifications` singleton; `NotificationOverlay`
is a view over `Notifications.popups` and holds no state. Keep that split — the SQLite store and
the terminal clients need the model to exist without a window.

- **Opt-in per machine:** `HYPR_NOTIFY=quickshell` in `~/.config/hypr/shell.local.env`. The
  `NotificationServer` sits in a `Loader` gated on it, so a machine that hasn't opted in never
  claims the D-Bus name. Only one process can own that name — start order decides, and while qs
  holds it swaync cannot be D-Bus activated back. Swap backends: set the key, run
  `~/.config/hypr/scripts/StartNotify.sh`, then restart `qs`.
- **The other half of the switch is in the `hyprland` package.** `autostart.lua` used to exec
  `swaync` unconditionally next to the qs daemon, so on a host set to quickshell the two raced
  every login and swaync won by ~1s (observed 2026-08-03): the qs server never got the name and
  popups silently disappeared, while swaync's own drawer kept working and hid the fault.
  `scripts/StartNotify.sh` now dispatches on `HYPR_NOTIFY` and, for quickshell, **stops and masks
  `swaync.service`** — swaync ships a D-Bus activation file pointing at that unit, so killing the
  process alone lets the next `notify-send` start it again.
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
  one place — hover-pause, burst shortening and collapse all hang off it (see Timing below).
  `rulesHook` is the rules-engine seam and **fails open**: a throwing hook logs and the
  notification displays with defaults.
- IPC: `qs ipc call notifications` → `dismissAll`, `dismiss <id>`, `count`, `unread`, `markRead`,
  `history <limit>`, `dbPath` (the seam the `notifctl` CLI grows from).
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

### Timing (story: notif-timing)

One duration vocabulary everywhere — config `timing.low/normal/critical`, a rule's
`presentation.durationMs`, and `entry.durationMs`:

| value | meaning |
|-------|---------|
| `> 0` | show for that many ms |
| `0` | sticky: stays until dismissed (also what `expire_timeout = 0` means on the wire) |
| `< 0` | drawer-only: recorded, counted unread, never popped |

- **The Timer's interval is not the clock.** `remainingMs` + `startedAt` on the entry are, because
  hover pause has to stop mid-count and re-arm from what is left. `Notifications.pause()` /
  `resume()` are the only things that touch them, and `runToken` ticks whenever the clock is
  re-armed — that is the card's cue to restart its remaining-time bar. The bar is **display only**;
  a dropped frame can never change when a card actually expires.
- **Burst shortening**: once a stack holds `timing.burstAt` cards (0 = `placement.maxVisible`),
  further non-critical durations are capped at `burstMs`. Critical is never shortened.
- **Shrink-to-icon**: any *sticky* entry (not just critical — a sticky urgency has the same
  problem) collapses to an icon pill after `criticalCollapseMs`. `NotificationSlot` narrows the
  card to `collapsedWidth` and slides it to `restX`, the anchored edge, so the pill keeps its place
  in the stack without covering the screen. One click on it calls `Notifications.expand()`, which
  restarts the collapse clock.
- **Drawer-only entries stay in `popups`** but are skipped by `reflow`, by `visibleCount` and by
  the overlay's stack keys — they take no slot and run no timer. Until the store/drawer stories
  land they are capped at `drawerRetention` (100), oldest closed as expired.

### History store (story: notif-store)

`config/NotifyStore.qml` — SQLite at `${XDG_DATA_HOME:-~/.local/share}/quickshell/notifications.db`
(`QS_NOTIFY_DB` overrides the path; the capture harness sets it so a run never writes into the
user's real history). **The file, not the daemon, is the public interface** every other frontend is
built against:

```sh
sqlite3 -readonly ~/.local/share/quickshell/notifications.db \
  "SELECT received_at, app_name, summary, state FROM notifications ORDER BY received_at DESC LIMIT 20;"
```

- **Why the `sqlite3` CLI and not `QtQuick.LocalStorage`**: LocalStorage is the only SQL binding in
  QML and it stores the database under a *hashed* filename in the offline-storage path. A store
  whose point is "readable from a tmux popup or over SSH" cannot live at a path nobody can name.
- **Writes never block a popup.** Statements queue and flush through a subprocess (one transaction
  per batch, ~one process per burst). A failure logs once, sets `healthy = false`, and the shell
  carries on purely in memory — verified by pointing `QS_NOTIFY_DB` at an unwritable path: the
  popup still displayed and only the store went quiet.
- **One escaping rule.** Values reach SQL as a JSON document inside a single quoted string and are
  unpacked with `json_extract`. `JSON.stringify` has already escaped every quote and control
  character, so doubling `'` is sufficient and there is no second escaping context to get wrong.
  Don't reintroduce per-column quoting.
- **Rows left `active` at startup are reconciled to `orphaned`** — their D-Bus notifications died
  with the previous process, so nothing could ever close them. They stay unread, which is how the
  bell count survives a `qs` restart (`unreadAtStart` → `Notifications.unread`).
- **IPC reads come from a 200-row cache**, refreshed after each write batch: an `IpcHandler`
  function must return a value immediately and cannot wait on a subprocess. Anything larger or more
  selective is a query against the file.
- Retention is age **and** count (`store.retentionDays` / `retentionCount`, 30d / 2000), run at
  startup, hourly, and on config save.
- `group_key` and `actions` columns exist and stay empty until the grouping and actions stories
  fill them.

### Keyboard control (story: notif-keyboard-control)

`config/NotifyFocus.qml` owns focus mode; `components/NotificationOverlay.qml` holds the key
handler. Entered with `qs ipc call notifications toggleFocus` (SUPER + n).

- **A popup never grabs the keyboard on arrival.** `WlrKeyboardFocus.None` is still the resting
  state of every notification window; the grab is bound to `NotifyFocus.active` and nothing on the
  ingest path can set it. Verified by typing into a terminal while a notification arrived — the
  typed string was unbroken.
- **Exactly one window takes the grab**: the one whose stack contains the selection
  (`focusedKey`). Two exclusive layer surfaces on one output fight, and the loser stops receiving
  keys with no error anywhere.
- **The selection is a notification id, not an index.** The model reorders under it (a card
  expires, a `replaces_id` lands); an index would quietly slide onto a different notification.
- **The overflow queue is navigable** because `Notifications.scrollOffsets` moves the window onto
  each stack while `placement.maxVisible` stays put — `j` past the last visible card scrolls the
  queue rather than growing the stack.
- **Focus freezes every clock** (`Notifications.holdAll`, `keyboardHold`). While it is set, the
  pointer leaving a card must not restart its countdown, and a card arriving mid-session starts
  paused like the rest.
- `Esc` releases and re-focuses the toplevel that was focused when the grab was taken — tracked
  from the `activewindowv2` event, not polled, because after the grab `hyprctl activewindow` is
  already answering about the wrong thing. Layer-shell does not specify where the keyboard goes on
  release, so we put it back by hand rather than trusting the compositor.
- Keys whose stories are not built (`s` snooze, `r` remind, `o` drawer, `D` dismiss-group) are
  **bound now and report what they need** — the scheme must not change under the user's fingers
  when notif-actions / notif-drawer / notif-grouping land. `dismiss-group` falls back to
  same-app, which is the key grouping will use first anyway.
- Action hints by number belong to notif-actions: the server still advertises
  `actionsSupported: false`, so no action ever reaches the model to hint at.

### Surface language: shadow, not stroke (story: notif-presentation)

Notification popups and the drawer **panel** carry no border. They are paper that landed on the
desktop, not powered surfaces, so depth comes from `components/Elevation.qml` (a `MultiEffect`
that re-renders the target blurred and offset behind itself) and the glass comes from the same
`Shimmer` the bar sections and launcher use. The drawer **modal** keeps its `EnergyBorder` — it
is a dialog, and it should read like the launcher and session overlay.

- Keyboard selection is marked by the accent-tinted shadow plus the widened urgency stripe.
  There is no border left to thicken, and adding one back for selection would undo the point.
- `Elevation` needs an opaque-enough target: the duplicate it draws sits directly under the
  original, hidden by it.
- The pill tray uses **one** Elevation for the whole row, not one per pill — per-chip effects
  each rasterize their own layer for something a few pixels tall.

### Opacity is layered, not global (story: notif-presentation)

Three separate knobs, because these surfaces answer different questions:

| surface | default | why |
|---|---|---|
| popup card / pill (`surface.cardOpacity`, `surface.pillOpacity`) | 0.80 / 0.85 | lands over whatever you are working in for a few seconds; must be readable instantly |
| drawer slab (`drawer.opacity`) | 0.35 | glass — you opened it deliberately, and it covers a third of the screen |
| drawer rows (`drawer.itemOpacity`) | 0.82 | the content inside the glass; a row over a terminal still has to be legible |

The drawer's translucency only works because Hyprland blurs its namespace — the layer rule for
`quickshell-notification-drawer` lives in `hypr/lua/windowrules.lua`. Without it, 0.35 is not
frosted glass, it is unreadable.

### Collapsed stickies dock in the bar (story: notif-presentation)

A folded sticky card leaves the popup stack entirely and becomes a floating pill in the bar,
between the workspaces and the status cluster (`components/bar/NotificationPills.qml`,
`collapse.home = "bar"`). It is deliberately **not** inside a `Section`: these are notifications
that shrank, not bar modules, so they carry their own pill surface and no bar background.

- The stack filter is `entry.collapsed && Notifications.dockCollapsed` in NotificationOverlay
  **and** in `NotifyFocus.order` — a pill in the bar must not be selectable by the stack's
  keyboard, since it is not on screen there.
- `dockCollapsed` also requires `Shell.barVisible`: with no bar there is nowhere to dock, and
  the pill stays in the stack rather than vanishing.
- Past `collapse.maxPills` the rest are one "+N" chip that opens the drawer. The bar is not a
  queue.
- **The tray adapts to the gap it is given**, because a PORTRAIT bar is ~1440 logical wide and
  the space between the workspaces and the status cluster is a few hundred pixels:
  `full` (icon + summary) → `compact` (icon only, summary on hover) → `chip` (one "N" bubble).
  Thresholds are conservative ESTIMATES on purpose — measuring the laid-out row and feeding
  that back into the mode that sets the row's width is a binding loop.

### Copy and expand

- `y` yanks summary + body, `Y` the body alone — vim's verb, in the popup stack and the
  drawer, where a group header yanks every row under it. `c` stays clear-filters in the drawer;
  one key may not mean two things depending on which surface has the keyboard. `wl-copy` rather than a QML clipboard API: the text
  has to outlive the popup, and wl-copy forks a daemon that keeps serving the selection.
- Substitutions go in as **argv, never a shell string**. Any app on the session bus can set a
  summary; `sh -c` here would be command injection with extra steps.
- `Enter` unfolds: a shrunk pill becomes a card, a card whose body was elided shows the rest
  (`Text.truncated` is what decides whether the "more" hint appears at all), and a drawer row
  expands in place. Expanded bodies are still line-capped so a hostile client cannot push a
  card past the screen edge.

### Hyprland dispatch has two dialects (bit us live)

`Hyprland.dispatch("focuswindow address:0x…")` — the classic hyprlang form — is **evaluated as
Lua** on a machine whose config is `hypr/lua/` (this repo's), and dies with `')' expected near
'address'`. The failure only appears in the quickshell log, so the focus restore silently did
nothing on the live desktop while every headless test passed (the harness runs sway, which has
no Lua layer to trip over).

- Lua config: `hyprctl dispatch 'hl.dsp.focus({ window = "address:0x…" })'`
- hyprlang config: `hyprctl dispatch focuswindow address:0x…`
- Same trap for submaps: `hyprctl dispatch submap foo` is eaten; use
  `hyprctl dispatch 'hl.dsp.submap("foo")'`. Inside the Lua config itself, use the API
  (`hl.dispatch(hl.dsp.submap("reset"))`) and none of this applies.

`NotifyFocus` therefore keeps a `dialect` property, tries one form, reads hyprctl's answer
(it prints `ok` or a parser error while still exiting 0 — the text is the only signal), and
flips on failure. Don't "simplify" that back to a single string.

### Drawer (story: notif-drawer)

`config/NotifyDrawer.qml` (state) + `components/NotificationDrawer.qml` (view). Opens with
`SUPER + i`, the bar bell, `qs ipc call notifications drawer`, or `o` from popup focus mode.

- **A view over the store, not over the popup list.** The drawer's entire claim is that a popup
  you already let expire is still reachable, so its rows come from SQLite. The only thing read
  from `Notifications` is whether a row is still on screen, so clearing it also closes the card.
- **Clearing is a row state (`cleared_at`), never a delete.** A history you can erase by holding
  `d` in a list is not a history — `sqlite3 <db> "SELECT …"` still returns every cleared row.
  That is schema v2; the migration is a bare `ALTER TABLE` whose failure ("duplicate column
  name") is the success case on an already-migrated database.
- **Filters push down to SQL, fuzzy matching stays client-side** on the returned page. LIKE is
  not fuzzy, and a subsequence matcher in SQL would need a stored function we do not have.
- **Search does not re-rank.** Matching is a subsequence test, not a score: ranking would
  reorder the list under the user as they type, and this list is chronological on purpose.
- **Selection is a key, not an index** (`"g:<app>"` / `"r:<row_id>"`), because the list is
  rebuilt on every refresh, filter change and keystroke — the same rule as the popup stack.
- **Panel and modal are one code path**, differing only in geometry (`drawer.mode`). Which one
  survives is a question to answer by living with both, per the story.
- The panel steps around the bar by hand (`barInset`): `ExclusionMode.Ignore` means the bar
  does not push it off its strip.
- Taking the keyboard here is not an exception to AD-011 — focus follows *intent*, and the
  drawer is something the user deliberately opened. Focus mode releases its grab before the
  drawer takes one, because two exclusive surfaces on an output fight.

### Lua rules (story: notif-lua-rules)

`config/NotifyRules.qml` hosts `rules/engine.lua` as a **subprocess**; user rules live at
`~/.config/quickshell/notifications.lua` (`QS_NOTIFY_RULES` overrides; see
`notifications.example.lua`).

- **Out of process, not in it.** Quickshell 0.3.0 has no Lua binding, and an in-process VM would
  put user code on the shell's thread — one `while true` in a predicate would freeze the bar and
  the launcher, not just a notification.
- **A rule can never drop a notification.** No rules file, a syntax error, a throwing predicate, a
  wedged interpreter, no `lua` installed: every path ends with the notification shown using the
  defaults it already had. The strongest thing a rule can say is `durationMs < 0` (drawer-only).
- **Protocol**: one JSON line each way, `seq` echoed. The `seq` check exists because several
  notifications can be in flight and applying one's answer to another would be worse than no rules.
- **Deadline** (`rules.timeoutMs`, default 50ms) fails open *and restarts the interpreter* — a
  missed deadline means it is wedged, and every later notification would queue behind it.
- **Accumulate, last write wins.** Every matching rule runs in file order; `stop = true` ends
  evaluation. That is what lets "mute this app" be layered with "…except criticals" instead of
  duplicating matchers.
- **`resolved` gates the view.** An entry waiting on the engine is in the model but on no screen,
  so a card never appears at the default anchor and then jumps to the one a rule chose. With no
  rules the callback is synchronous and this is the same single frame it always was.
- Hot reload restarts the subprocess rather than re-reading in place: atomic, and it cannot leave
  half an edited file loaded.
- The engine carries its own ~150-line JSON codec on purpose — lua-cjson is not installed
  everywhere this config lands, and a rules engine that fails to start over a missing rock would
  take notifications with it.

### Actions — design settled, not built (story: notif-actions)

The shape is decided (spike `notif-actions-config-spike`, AD-012, design note
`Projects/hyprland-dotfiles/features/notification-actions-design` in the notes vault). Build to
it rather than re-deciding:

- **Custom actions carry their own matchers** — a flat list of
  `match = { app, category, urgency, summary, body, hint.* } → label, key, run | prompt`, read
  like the hyprland keybind table. The Lua rules engine may **veto** actions
  (`presentation.actions = false`); it never defines them.
- **Spec actions and custom actions render identically** and share one key-hint sequence, spec
  actions first, so a client's own "Reply" never loses its key to a config rule.
- **Substitutions are argv elements** (`{id}`, `{summary}`, `{input}`, `{hint:NAME}`) — no
  `sh -c`, ever. Any app on the session bus can set a summary, so this is a security boundary.
- **Prompts** are inline on the card, offered only for a client inline-reply hint, an allowlisted
  category (`im.received`, `email.arrived`, `x-vault.reminder`), or an action that declares one.
- **Snooze is a store row**, not a second scheduler: `state = 'snoozed'` + `wake_at`, one armed
  timer, elapsed rows fired at startup beside the existing `orphaned` sweep.
- `actionsSupported` / `inlineReplySupported` flip true **in that story and not before** —
  advertising a capability we don't render makes clients send content we display as garbage.

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
| `QS_SUBMAP_HINTS` | `1` (default) \| `0` | which-key hints for the active submap (`components/SubmapHints.qml`) |
| `QS_SUBMAP_HINTS_DELAY` | ms (default `250`) | how long a submap must stay active before the hints appear |
| `QS_SUBMAP_HINTS_OPACITY` | `0.05`–`1` (default `0.1`) | hints slab surface opacity. Its own knob, not the drawer's. Out-of-range falls back to the default — `0` is a valid float that would leave the slab invisible while the text still drew |
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
