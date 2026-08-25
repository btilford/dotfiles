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
| `config/Clocks.qml` + `config/Weather.qml` + `components/ClockDrawer.qml` | Clock drawer: weather, world clocks, month calendar. `SUPER+c`, the bar clock, or `qs ipc call clock drawer`. |
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

## Clock drawer (weather, world clocks, calendar)

`config/Clocks.qml` + `config/Weather.qml` (state) + `components/ClockDrawer.qml` (view). Opens
with **`SUPER + c`**, by clicking the bar clock, or `qs ipc call clock drawer`
(`drawerShow`/`drawerHide`/`refresh`/`weather`).

- **The singleton is `Clocks`, not `ClockDrawer`.** The view is `components/ClockDrawer.qml`,
  and a singleton of the same name would shadow it in every file importing both directories.
- **`Clock.qml`'s two Popouts are gone.** The world-clock list and the calendar moved here; the
  bar clock is now a button. The `TZ=… date` mechanism moved unchanged — quickshell 0.3.0's JS
  engine has **no `Intl` timezone support**, so `new Date()` is only ever local time. One shell
  call per minute produces every zone's time *and weekday* (a zone list without the weekday
  lies by omission: 07:12 in Tokyo is tomorrow). Do not "modernise" this to `Intl`.
- **Both minute and second timers run only while the drawer is `shown`.** Nothing reads them
  with no window on screen.
- Its own layer namespace `quickshell-clock-drawer` and its own rule in
  `hypr/lua/windowrules.lua`, with the same values as the notification drawer but **stated
  separately** — the surfaces are unrelated, and sharing one knob is how tuning the submap
  hints once restyled the notification drawer. Same reason `slabOpacity`/`cardOpacity` are
  constants on the window rather than reads of `NotifyConfig.drawer`.
- Widgets are a plain `Column` of cards inside a `Flickable`, so a fourth one is an insertion
  and a short monitor scrolls instead of clipping.
- Keys: `h`/`l` (or arrows) month, `t` today, `r` refetch, `Esc` close. **No `j`/`k`** — nothing
  here is a list, and rebinding them would break the habit the other two keyboard surfaces build.
- The bind goes through `keybindings.lua`'s `notif_run` even though it is not a notification
  verb: that helper resets the submap *before* running, and the reason is the keyboard grab, not
  notifications. The name is now narrower than what it does.

### Weather: provider is config, and the location never lands in this repo

`~/.config/quickshell/weather.json` (`QS_WEATHER_CONFIG` overrides — the seam the capture
harness uses; see `weather.example.json`). Three providers answer the same question:
`open-meteo` (**default**, no key, global lat/lon), `home-assistant` (LAN-only), `wttr.in`
(fallback proxy).

- **A home lat/lon is private infrastructure**, exactly like a LAN IP. Only the example ships;
  the real file is gitignored and provisioned from `private-dotfiles`, and `mise run
  lint:private` fails a commit that leaks one. **`visual-capture.sh` must keep pointing
  `QS_WEATHER_CONFIG` at a rig-owned file** — without it a capture destined for the notes vault
  photographs the user's coordinates. Its fixture uses the Royal Observatory, Greenwich.
- **An HA token is never in the JSON.** The config names a SECRET (`[A-Za-z0-9_]+`, validated
  before it reaches a shell) and `dotfiles-secrets --get` resolves it inside the same subprocess
  that makes the request, so the value exists in no file, no QML string and no environment. The
  URL and the name are positional parameters, never interpolated into the script text.
- `curl` in a `Process`, not `XMLHttpRequest`, precisely so that token handling is possible.
- **Failure is a state, never a blank.** idle/loading/ok/error with a human-readable reason,
  and the last good reading stays on screen marked `stale`. `qs ipc call clock weather` reports
  it without a screenshot.
- **A reading carries the units it was fetched in** (`readingTempUnit`/`readingWindUnit`).
  `units` is live config and `current` is a cached number: editing the file re-labelled a
  cached 19°C as 19°F, which is a wrong number on screen, not a cosmetic bug.
- HA forecasts: `attributes.forecast` was removed from weather entities in HA 2024.4 (it needs
  the `weather.get_forecasts` service now). It is read when a legacy integration still publishes
  it; otherwise the strip is empty and current conditions still render.

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

## Now playing (MPRIS)

`components/bar/NowPlaying.qml` — the current track plus transport, floating in the gap between
the window list and the workspace centre. `Quickshell.Services.Mpris` is a NEW dependency for the
shell; nothing else in the config imports it.

- **Not a bar module, and not in a `Section`.** `Section.qml` is what draws the slanted bar
  surface; this is text and icons only, no Rectangle, no border, no `Theme.surface` fill. It is
  the mirror of `NotificationPills` on the other side of the centre and follows the same rule.
- **The centre section must not move.** It is anchored to the screen's `horizontalCenter`, so
  every pixel this takes is absorbed by ELIDING the title, never by pushing. Widths are derived
  from `root.width` (the gap the item is anchored across) and never from the laid-out row —
  measuring a row and feeding that back into the properties that size it is a binding loop, the
  same trap `NotificationPills` documents.
- **Previous is dropped before the title is.** `showPrev` tests the space available WITHOUT it,
  which is also what keeps that test out of the loop. Below `minTitle` the whole cluster hides,
  which is the answer for a PORTRAIT bar too — it falls out of the width test rather than needing
  a portrait flag.
- **Every control is guarded on the player's capability flag** and hidden, not greyed: players
  advertise a subset, and calling an unsupported control is a silent no-op behind a button that
  looks enabled.
- **Both `trackArtist` and `trackArtists` are QString off the same bindable** on stable 0.3.0 —
  they are not a joined/array pair, so a `trackArtist || trackArtists` fallback is dead code.
- **One player, never a stack.** A browser tab and a music app are both registered most of the
  time. The pick prefers whatever is `Playing` and otherwise HOLDS the player it was already
  showing, which is what makes the pause grace period describe the track you just paused. The
  set only changes when a player appears or disappears, so an `Instantiator` of `Connections`
  re-picks on any `playbackStateChanged` — without it the choice freezes and switching apps never
  registers.
- **A pause does not hide it immediately.** `QS_NOW_PLAYING_TIMEOUT` (45s) starts on pause and is
  cancelled by resume, so a pause-and-resume does not make the bar jump. The player disappearing
  hides at once — there is nothing left to describe.
- **The grace belongs to ONE player, keyed by `dbusName`.** Quitting a playing app while a paused
  browser tab is still registered promotes the browser (`pickPlayer` falls through to `ps[0]`),
  and without an owner check that promotion inherited the grace: the bar advertised someone
  else's stale paused track for the full 45s. Two traps sit inside that fix, both found by
  screenshot rather than by reading:
  - **`uniqueId` is per-TRACK, not per-player.** It changed `1` -> `4` on one player when only
    the title changed, so an ordinary pause looked like a stranger claiming a grace it had not
    earned and the paused track vanished on the spot. `dbusName` is `isPropertyConstant` and is
    the identity to compare. It is also a *string*, which matters: the player that armed the
    grace may already be destroyed when the comparison runs — a stale QObject reference reads
    back as `undefined`, which `pickPlayer` has to handle anyway.
  - **Do not read `root.playing` inside the handler for a player CHANGE.** `onPlayerChanged` can
    run before the `playing` binding has re-evaluated, and that stale `true` made the newly
    promoted browser stamp *itself* as the grace owner — the first version of the fix looked
    right and reproduced the bug exactly. Read `player.playbackState` directly instead.
- **One monitor, pinned by description.** Media is one stream, not per-screen state, so unlike
  Audio/Network/Clock it is not duplicated across every bar. `QS_NOW_PLAYING_MONITOR` takes a
  monitor description (substring, case-insensitive) or a bare connector name; description is
  preferred because connector names shuffle across reconnects, the same reason
  `hypr/lua/monitors.lua` addresses displays by `desc:`. **The default is empty and must stay
  empty in this repo** — a real description carries the panel's hardware serial, which
  `mise run lint:private` blocks from a publicly mirrored tree. Both fallbacks go toward showing:
  unset shows on every bar, and so does a configured monitor that is not currently connected.
- `Hyprland.focusedMonitor` is deliberately NOT used. Every use of it in this config is a
  transient surface; a persistent element that hops monitors on focus change is visual noise.
- Click on the text raises the player when `canRaise` (mpd/playerctld have no window). Scroll is
  unbound on purpose: it means volume on `Audio.qml`, and one gesture meaning two different
  volumes a few hundred pixels apart is worse than no gesture.

### Testing it without a media player

`mise-scripts/visual-capture.sh` has **no mpris scene**, deliberately for now: every other scene
drives a surface through quickshell IPC, and this one needs a *media player on the bus*, which
means shipping a D-Bus service and a python bus library the capture script does not otherwise
depend on. Until that is worth paying for, this surface is captured by a throwaway rig.

The headless rig on a private bus (see "Testing notifications without a Hyprland session") has no
media player on it, and pointing it at the live session bus would make the test depend on whatever
you happen to be listening to. Publish a stub instead — an `org.mpris.MediaPlayer2.*` name whose
`PlaybackStatus`, metadata and `CanGoNext`/`CanGoPrevious` come from a control file the rig
rewrites between screenshots. Publish **two** of them — an app that plays and a browser tab that
stays paused for the whole run — because one player cannot exercise either the pick or the
stale-player transition, which is where the real bugs were. Capture at a NARROW output (1600px,
not 2560): at desktop width the gap swallows any title and the elision path is never exercised.

**Read `Mpris.players` through a BINDING, in the harness too.** An imperative read reported zero
players forever while the bar beside it was showing the track — the service initializes when
something binds to it, the same lazy shape `DesktopEntries` has. The list is also empty at
`Component.onCompleted` and fills in asynchronously, so a probe needs both a binding and a wait.

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
- **Capabilities are advertised honestly**, but `actions` is now among them. `GetCapabilities`
  returns `body` + `actions` + `icon-static`. Do not flip `bodyMarkupSupported` /
  `inlineReplySupported` / `actionIconsSupported` until those stories render them — clients
  change what they send based on this.
- **`actions` is load-bearing for every Chromium client, and its absence fails silently.**
  Chromium (Brave, Chrome) calls `GetCapabilities` **once at startup** and, if `actions` is
  missing, refuses the system notifier for the whole process lifetime and uses its internal
  message centre instead. No error, no log, no retry. On Hyprland those internal windows have
  **no class and no title**, so no window rule matches and they tile full-screen, one per
  monitor — which reads as "notifications broke" and points nowhere near a capability string.
  Confirmed 2026-08-05 by `dbus-monitor`: zero `Notify` calls from Brave for days, then
  `GetCapabilities` → `Notify` immediately after `actionsSupported` flipped and Brave was
  restarted. Note that closing Brave's window does **not** restart it (a push service worker
  holds the process group); `pkill -x brave` and check `pgrep -c brave` first.
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
- Deliberately **not** here yet (grown by later stories, see their own sections below):
  actions, keyboard focus (popups use `WlrKeyboardFocus.None` on purpose), drawer/history, DND,
  grouping — only grouping remains unbuilt.

### Placement & motion (story: notif-placement-motion)

User config, not QML constants. **TOML is preferred, JSON is the fallback**, layered lowest
precedence first:

```text
~/.config/quickshell/notifications.toml        base
~/.config/quickshell/notifications.d/*.toml    drop-ins, lexical order
~/.config/quickshell/notifications.local.toml  machine-local, always wins
~/.config/quickshell/notifications.json        used only when no TOML exists
```

`notifications.example.toml` is the annotated template and is generated from the JSON one, so
the two cannot drift while both exist. `QS_NOTIFY_CONFIG_TOML=<path>` / `QS_NOTIFY_CONFIG=<path>`
override the base path — the seam the capture harness uses — and `QS_NOTIFY_PRESET=<name>`
overrides the preset alone.

**Why not JSON any more:** the original argument was that QML parses JSON natively and anything
else meant a build step between the user and a preference. That holds for a *build* step, not
for a converter run at load — the file is still edited directly and still hot-reloads on save.
Meanwhile the cost of JSON was being paid in `_comment` keys, and AD-012 had already written its
action examples in TOML. `tomlq` (from the `yq` package) does the conversion; one call slurps
every layer in order.

**Merge rules:** tables merge key by key recursively; **arrays concatenate**, so `[[actions]]` in
a drop-in ADDS a verb rather than replacing the base's list; scalars are last-wins. The trade is
that a drop-in cannot *remove* a base action — edit the base file for that.

**Fails open on every path.** No `tomlq` (exit 127), a syntax error, or unparseable output each
log one line and fall back to JSON/defaults; verified against a deliberately broken file. Every
key still falls back to the constants in `NotifyConfig`, so a missing or broken file can never
take the shell down.

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
| drawer slab (`drawer.opacity`) | 0.05 | glass — atmosphere only; the rows above carry the legibility |
| drawer rows (`drawer.itemOpacity`) | 0.82 | the content inside the glass; a row over a terminal still has to be legible |

The drawer's translucency only works because Hyprland blurs its namespace — the layer rule for
`quickshell-notification-drawer` lives in `hypr/lua/windowrules.lua`. Without it the slab is not
frosted glass, it is a flat tint.

**Slab alpha is not a legibility control, and treating it as one is the trap this section used
to set.** The slab is a `Rectangle` fill; its alpha does not touch child items, so rows and text
are fully opaque at any value. Raising it never makes content more readable — it only stacks
more tint between you and the desktop, and `Theme.surface` is a warm maroon (`#2a1010` under
`warmBase`), so past a certain point every glass surface reads as a brown wash. Both slabs are
now 0.05 and take their colour from **`Theme.glass()`**, which desaturates `surface` toward its
brightest channel — a luminance mix collapses that colour to near-black — and lifts it toward
white so the blur has contrast to be seen against.

**`ignore_alpha` must sit BELOW a surface's alpha or the compositor silently skips blurring it.**
Both rules keep `ignore_alpha = 0.15` against a 0.05 slab, so the slab itself is deliberately
unblurred and only the shimmer, elevation and text sit over a sharp background. That is a chosen
look, measured: dropping it to 0.02 enables full blur and in-slab detail variance falls from
0.064 to 0.042. Nothing warns either way, and an unblurred glass surface reads as a design
mistake rather than a missing effect.

**Known artifact:** at 0.05 the `Shimmer` sweep reads dark rather than light, and much more
strongly than on the opaque bar sections. Accepted for now — see the
`quickshell-shimmer-inverts-on-glass` task.

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

### Do Not Disturb (story: notif-dnd-core — BUILT)

`config/NotifyDnd.qml` owns the real `s.dnd` value `NotifyRules.state()` used to hardcode as
`false` — every Lua rule written against it since 2026-07-26 had been reading a constant.

- **Two inputs OR together into one `active`.** `manualOn` (the keybind / IPC toggle) and
  `scheduled` (quiet hours, `NotifyConfig.dnd.quietHours`, **off by default**). `qs ipc call
  notifications dnd` toggles, `dndOn`/`dndOff` set a known end state, `dndStatus` reports which
  input is behind the current state ("on (manual)", "on (quiet hours)", "on (manual + quiet
  hours)", "off") — readable without a screenshot. Keybind: `SUPER+n` then `z`, inside the
  `notif-cmd` submap.
- **Quiet hours are its own clock, not a reuse of `state().hour`.** That field is an integer
  hour for rule predicates — too coarse for a schedule crossing midnight or under an hour wide.
  `NotifyDnd` parses `"HH:MM"` itself and ticks a plain 30s `Timer`. `start == end` is defined
  as "no window" rather than "all day", so a copy-pasted typo cannot silence every notification
  permanently; `start > end` wraps past midnight (`23:00` -> `07:00`).
- **Suppression is a DEFAULT, applied before the rules engine, never a wall.** `applySuppression`
  runs in `Notifications.refresh()` right after `Timers.applyPlacement`, and forces
  `entry.durationMs = -1` (drawer-only) when DND is active — reusing the exact mechanism
  notif-timing already built for muting an app, rather than a second suppression path. Because
  it runs before `NotifyRules.evaluate()`, a Lua rule reading `s.dnd == true` gets the last
  word (the engine's usual "accumulate, last write wins" contract) and can restore visibility
  for whatever it decides matters — see the `dnd exception` rule in
  `notifications.example.lua`. **A rule can only let more through, never suppress harder than
  DND already does** — that half needs no rule at all.
- **`allowUrgency` (`NotifyConfig.dnd`, default `"critical"`) is a config-level floor, not a
  rule.** It is checked inside `NotifyDnd.applySuppression` itself, before durationMs is ever
  forced negative — the only escape that works with NO rules file, no `lua`/`luajit`
  interpreter, or a wedged engine (`NotifyRules.evaluate()` answers `null` on all three, so a
  Lua exception never runs). Set to `"none"` to go back to all-or-nothing suppression.
- **An existing rule that sets `durationMs` unconditionally is an IMPLICIT DND exception.**
  Suppression runs before the rules engine and a later write always wins, so any rule not
  written with `s.dnd` in mind will fire regardless of DND — e.g. a pre-existing "chatty app,
  short dwell" rule keeps popping that app during quiet hours. Gate rules that are not meant to
  bypass DND with `not s.dnd` in their `when`, the way `notifications.example.lua` does.
- **Suppressed still means stored.** Drawer-only was already "recorded, counted unread, never
  popped" before this story; DND does not invent a second kind of hiding. A notification DND
  held is in the SQLite store and in the drawer exactly like any other muted source.
- **The exit digest counts only what actually stayed suppressed.** `entry.dndBaseline` marks
  that DND's default applied to this entry; the digest increments in
  `Notifications.finishRefresh()`, guarded by `entry.dndCounted`, only when the entry is BOTH
  `dndBaseline` and still `drawerOnly` after the rules ran — a rule exception that restored
  visibility was never actually suppressed and must not be counted. `NotifyDnd.onActiveChanged`
  resets the tally to zero when a session starts and, on the true->false edge, fires one
  `notify-send` summary ("N notifications were held while DND was on") when the count is
  nonzero — never a replay of every held notification, which is the flood DND exists to
  prevent. **The digest itself is delivered through `notify-send`**, an external dependency:
  with no `libnotify` on the machine it silently never appears, and on a host where swaync
  still owns `org.freedesktop.Notifications` (see `HYPR_NOTIFY`) swaync delivers it while
  this shell's own bell stays hidden.
- **The bar indicator lives on the bell, not a second control**
  (`components/bar/NotificationBell.qml`) — a `cod-bell_slash` glyph, dimmed to
  `Theme.subtext`, with the tooltip appending `· DND <status>`. Per-category badges are still
  their own story; do not grow this widget past DND.
- **Fullscreen-as-DND needed no new mechanism.** `state()` already exposes `fullscreen`
  (`Hyprland.focusedWorkspace.hasFullscreen`), so "quiet while fullscreen" is a one-rule
  addition today (`notifications.example.lua`'s "fullscreen: only criticals pop") — confirmed
  during notif-dnd-core rather than built as a mode. Screenshare/recording awareness,
  redirect-instead-of-suppress and an explicit fullscreen "mode" stay deferred to the parent
  story (`Roadmap/Stories/quickshell-notif-dnd`): the screenshare open question (portal session
  state vs polling for capture clients) is unresolved, and guessing a detection method is out of
  scope for this slice.

### Actions, prompts & snooze (story: notif-actions — BUILT)

Built to AD-012. `actionsSupported` and `inlineReplySupported` are both true;
`GetCapabilities` returns `body, actions, icon-static, inline-reply`.

- **Two kinds, one key scheme.** A *spec* action came in the D-Bus `actions` array and is
  handed back to the client via `invoke()`; a *custom* action is matched from
  `NotifyConfig.actions` and run here as a subprocess. They render identically. Hints are
  assigned spec-first so a client's own "Reply" never loses its key to a config rule.
- **`default` gets no button and no key.** Clicking the card, or Enter in focus mode, IS that
  action — giving it a chip would say otherwise.
- **Hints are `Ctrl+<letter>`, not bare letters or digits.** Focus mode and the drawer are both
  vim-shaped and own the bare alphabet (j/k/d/x/D/y/Y/s/r/o/p/g/G/a/f/c — `p` is compose); losing
  `d` to an action would break dismiss. Resolution order: a declared free letter, else the first free letter *of
  the label* (so "Reply" → `^r` with nothing configured), else the next free letter.
- **Substitutions are argv elements, never a shell string**, and no `sh -c` is added anywhere on
  this path. Any app on the session bus can set a summary, so this is a security boundary.
  A bad matcher regex fails CLOSED — matching everything would fire an action on every
  notification.
- **A failing action raises a critical notification** rather than doing nothing, routed through
  `notify-send` so it lands in the popup stack *and* the store by the same path as everything
  else.
- **Prompts** appear on a client inline-reply hint, an allowlisted category
  (`im.received`, `email.arrived`, `x-vault.reminder`), or an action declaring `prompt`. The
  field is on the card — the reply keeps what it is replying to on screen. Opening one pauses
  the entry through the same path hover-pause uses, so a card cannot expire mid-sentence.
  Taking focus is safe *here only* because a prompt is opened by a deliberate act, never by a
  notification arriving (AD-011 intact).
- **Snooze is a row state**, `wake_at` (schema v3), with ONE armed timer for the earliest wake
  and overdue rows fired at startup — so it survives a restart and a reboot with no second
  scheduler. `s` snoozes for `snooze.defaultMs`; `r` prompts in time mode (`20m`, `2h`, `17:30`)
  and REJECTS what it cannot parse rather than guessing.
- **Nothing may read its own enqueued write.** Store writes batch through a subprocess ~200ms
  later, so `snooze()` and `fireDueSnoozes()` cannot see their own effect. Arming the timer from
  a stale read stopped it (snooze never fired) in one direction and re-fired the same row in a
  tight loop in the other — 100+ duplicate notifications in seconds. Re-arming now happens on
  the writer's exit, guarded by an in-memory set of dispatched row ids, the same ids excluded in
  SQL, and a one-second interval floor.
- **Drawer rows get custom actions only, minus the capturing ones.** A spec action needs a live
  client, and by the time a row is history that process has exited. `capture` actions are
  filtered out of `actionsForRow` for the same reason one step further on: capture means "write
  the output into the reply field", and a row invoked *as a row* has no reply channel — offering
  the verb would spend a model call on text that vanishes. Compose re-associates a live entry
  when one exists and then uses `actionsFor()`, which does offer them.
- **`rowAsEntry` is an adapter, not an entry**, and now says so with `isRow: true`. `pause()`,
  `resume()` and `submitPrompt()` all assumed a live entry; a capturing action invoked from the
  drawer died on `entry.expiryTimer` with a TypeError in the log and no action run. Each of the
  three tests the flag. It is **not** called `stored` — a live entry already has a property of
  that name meaning "a history row exists for this one", true of nearly every card a few hundred
  ms after it appears. The first version reused the word, so `pause()` returned early for every
  live notification and the composed card expired under the compose surface. A one-word name for
  a new flag on a shared object is worth grepping for first.
- Migrations are a LIST run one statement per process: the sqlite3 CLI aborts on first error, so
  a concatenated migration would never reach v3 on a database that already had v2.
- IPC: `qs ipc call notifications snooze <ms>` and `... snoozed`.

**The action object must carry every field `invokeAction` reads.** `actionsFor` built its
entries field by field and simply never copied `capture`, so `action.capture` was `undefined`
everywhere and **every `capture = "draft"` / `"reply"` action ran as fire-and-forget** — the
command ran, exited 0, and its stdout was dropped. Nothing failed, so nothing logged. That is the
shape of bug to expect from hand-built plain objects crossing a module boundary; if you add a
config key to an action, add it to both builders (`actionsFor` and `actionsForRow`) and to
`NotifyConfig`'s validator.

### Timers, pomodoro, stopwatch and alarms (story: notif-timers — BUILT)

`config/Timers.qml` owns the state machine; a card is a pure view over it, the same split
`Notifications` already enforces. Driven by `qs ipc call timers …`: `start <dur> [label]`,
`alarm <hh:mm> [label]`, `pomodoro ["25m/5m/15m x4"] [label]`, `pause|resume|toggle|reset|extend|
cancel <id>`, `cancelAll`, `stopwatch|stopwatchStart [label]`, `lap`, `stop`, `list`.

- **Schema v4** — the `timers` table. It is a `CREATE TABLE IF NOT EXISTS` in `schemaSql` rather
  than a `migrations` entry (a new table needs no `ALTER` and heals itself every start), but
  `schemaVersion` still moves, because that number is what a reader of the file checks to know
  which tables to expect.
- **Nothing here is a second scheduler.** An armed timer is a `timers` row carrying `wake_at`, and
  `NotifyStore.armSnoozeTimer` takes `MIN(wake_at)` across **both** that table and the snoozed
  notifications — one Timer object in the whole file. So a countdown survives a `qs` restart *and*
  a reboot by the mechanism snooze already proved, and a row whose wake passed while the machine
  was off fires on the next start (verified: killed `qs` mid-countdown, restarted 18s later, the
  card was replaced by "time's up" immediately).
- **Nor a second parser.** Durations go through `Notifications.parseDelay` — `20m`, `2h`, `90s`,
  `17:30`. The pomodoro spec `25m/5m/15m x4` is a SHAPE around it, not a vocabulary: each part is
  handed to the same function, so remind-me-at and start-a-timer cannot drift apart.
- **Ticks are never written.** A running countdown is in-memory on the singleton; the store sees
  arm, pause, resume and finish. One finished PHASE = one summary row, which is what makes
  `SELECT COUNT(*) FROM timers WHERE kind='pomodoro' AND phase='work' AND state='done'` answer
  "how many pomodoros today" without a tick ever being stored.
- **Two identities, and the small one is public.** `runId`/`rowId` are epoch-derived (~1e15);
  `handle` is a per-session 1, 2, 3… An `IpcHandler` parameter typed `int` is **32-bit**, so
  handing out a run id truncated it to a negative number that addressed nothing. The same trap bit
  the `timerElapsed` signal, where an `int` row id fired the notification correctly and then
  UPDATEd a row that does not exist — the timer stayed `armed` in the table and in the live list
  for ever, with nothing logged. Every id and every epoch stamp on that signal is `real`.
- **Restore happens before the due sweep, and a raise in flight can be cancelled.** Both are async
  queries; run in parallel, an overdue timer fired against an empty live list and the restore then
  raised its card again, leaving a running card for a finished timer. `restoreTimers(true)` fires
  only from the restore callback, and `dropCard` latches `dropped` so a `notify-send -p` whose id
  arrives late closes its own card (a 2-second countdown does exactly that).
- **A timer that cannot be persisted is refused at START**, with a critical notification saying so.
  The store IS the schedule, so a timer armed with the store off would simply never fire — and a
  countdown that silently does not go off is the one failure this feature must not have.
- **The card is pinned to its own anchor** (`timers.anchorV = "top"`), so a card that will sit
  there for 25 minutes cannot push the notifications you actually need to read out of the default
  stack's overflow window. `Timers.applyPlacement` runs on the ingest path, before the rules, so a
  rule can still move it.
- **A hint is client data, so cards are tokened.** Every card this shell raises carries
  `x-timer-token` (minted once per session); a hint is only believed when it matches. Without it
  any app on the session bus could send `-h string:x-timer-id:1` and be handed a live timer's
  pause/reset/**cancel** verbs, plus the timer anchor to pin itself to. Verified with a spoofed
  `notify-send`: no verbs, no readout, default anchor.
- **`x-timer-id` means "controls this live timer" and only a RUNNING card carries it.** A
  finished/announcement card carries the token alone, which is enough to put it in the timer
  stack. This is not tidiness: a pomodoro keeps ONE handle across every phase, and
  `advancePomodoro` has already armed and added the next phase before `notify-send` delivers — so
  a "Work 1/4 done" card carrying the handle rendered the *break's* countdown and its Ctrl+C
  cancelled the break it was announcing.
- **Nothing on a timer object notifies.** `paused`, `endsAt` and the rest are plain JS fields on a
  plain object, and `stateFor` keeps returning the same object, so no binding re-runs on its own.
  Any view reading them must touch `Timers.revision` (bumped by `publish()`) and/or `Timers.now`.
  The card said "running" beside a frozen clock after a pause, while the chip next to it correctly
  said Resume, because `ActionChips` touches `revision` and that Text did not.
- **Timer identity in a view is `.handle`.** `Timers.resolve` treats a missing/undefined handle as
  "the newest live timer", so `timerState.id` (a field that does not exist) silently paused
  whichever timer started last — invisible with one timer running, wrong with two. Any rig case
  for this needs TWO concurrent timers.
- **`NotificationCard.activate(button)` is a function, not an inline `onClicked`,** because a
  headless rig has no pointer and no keyboard: that is the only way "which timer does this card
  act on" can be exercised at all, and the defect above shipped to review because it could not be.
- **Card verbs are built-in actions, `kind: "timer"`** — Pause/Resume `^p`/`^r`, `+5 min` `^m`,
  Reset `^e`, Cancel `^c` — so they render as chips, answer the same `Ctrl+<letter>` scheme and
  work from focus mode and compose with no second control surface. `invokeAction` calls
  `perform()` in process: routing back out through `qs ipc call` would spawn a process for this
  shell to talk to itself. Clicking a timer card pauses it rather than dismissing it.
- **The stopwatch is deliberately not a card** (decision 2). It counts up, so it has no `wake_at`,
  and a card only re-renders on `replaces_id`. `components/bar/Stopwatch.qml` is its display —
  click pause/resume, middle-click lap, right-click stop — and the notification surface sees it
  only at terminal events: started, lap, stopped. It does NOT survive a restart, because there is
  no armed row to survive with; stopping writes its one summary row.
- A folded timer card keeps counting in the bar pill (`NotificationPills`), because a pill that
  says only "Deep work" has thrown away the thing a running timer is for.
- **Desktop timers are not a front-end onto vault reminders.** AD-012 §4's argument for snooze
  carries over: the vault is right for "remind me Thursday" and wrong for "remind me in 15
  minutes", and routing a pomodoro through it would make the desktop depend on the vault being
  reachable. `x-vault.reminder` stays what it is.
- **Firing is late by up to ~1s, never early.** Qt's coarse timers, plus the write-flush and query
  round trips, put the observed fire ~0.8–0.9s after `wake_at` (measured on 4s and 30s timers).
  The due query re-checks `wake_at <= now`, so an early wake simply finds nothing and re-arms.

### Compose: one notification, centred, with room to write

`config/NotifyCompose.qml` (state) + `components/notifications/ComposeSurface.qml` (view). `p`
opens it, from popup focus mode and from a drawer row; `qs ipc call notifications compose [id]`
does the same, and `composeState` reports what it would send.

- **It is a STATE, not a window.** AD-012 §5 rejected a dedicated centred overlay because it adds
  a third focus-grabbing surface. So the surface is instantiated inside a window that already has
  the grab: the popup stack's `flightHost` layer (the full-window layer the dwell reparents into)
  or the drawer. `NotifyCompose.host` names which, and each host renders it only when named — the
  stack additionally checks the entry belongs to *its* (monitor, anchor) pair.
- **Composing counts as focused.** The stack window takes the keyboard while compose is open even
  with focus mode off, because a text field on a surface with no grab silently eats nothing. It is
  only ever opened by a deliberate act, so AD-011 holds. When focus mode was *not* already
  holding the keyboard, compose remembers and restores the previous toplevel itself.
- **Closed means zero-sized, not just invisible.** The stack window masks input to the items that
  may be clicked, and a full-window item that is merely `visible: false` still contributes its
  geometry to that `Region` — which would make the notification layer swallow every click on the
  desktop.
- **It is not a NotificationCard with a bigger prompt box**, though that was the shorter route. A
  card binds `paused`/`collapsed`/`remainingMs`/`runToken` and the notification behind them, and
  half of compose is a stored SQLite row with none of those. The chips ARE shared, via
  `components/notifications/ActionChips.qml`, so a verb cannot look different on the two surfaces.

**Replying from a stored row: the answer is re-associate, then be honest.** `openRow` looks for a
live entry for that `nid` (rows still `active`), and composing then behaves exactly like composing
from the stack — that is what makes "reply from the drawer" work for something still on screen.
With no live entry there are three routes and the surface says which one it is in:

| route | field | what sending does |
| --- | --- | --- |
| `reply` | shown | `sendInlineReply()` to the client |
| `action` | shown | the text becomes `{input}` in an argv this shell runs — works on a row from last week |
| `none` | **not shown** | nothing; the surface says why, and points at the verbs |

A reply field that silently goes nowhere is worse than no field, so `none` renders a note instead
of a box. The same rule was applied to the path that already existed: a prompt opened on an
**allowlisted category** whose client does not support inline reply used to drop the text in
silence, and now raises a critical "Reply not sent" the same way a failing action does.

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
| `QS_SUBMAP_HINTS_OPACITY` | `0.05`–`1` (default `0.05`) | hints slab surface opacity. Its own knob, not the drawer's. Out-of-range falls back to the default — `0` is a valid float that would leave the slab invisible while the text still drew |
| `QS_NOW_PLAYING` | `1` (default) \| `0` | MPRIS now-playing cluster in the bar (`components/bar/NowPlaying.qml`) |
| `QS_NOW_PLAYING_TIMEOUT` | ms (default `45000`) | how long a PAUSED track stays before the cluster hides; resume cancels it. Floored at 1000 — a 0 would hide it the frame you pause, which reads as the bar flickering |
| `QS_NOW_PLAYING_MONITOR` | monitor description or connector name (default empty) | which single bar shows it. Empty = all bars, which is also the fallback when the named monitor is not connected. Keep the default empty in-tree: a real description carries a hardware serial and `lint:private` blocks it |
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
