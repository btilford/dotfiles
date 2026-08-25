// Default quickshell config (loaded by bare `qs` / targeted by `qs ipc`).
// Increment 1: launcher only. Bar, notifications, lock, OSD, dashboard get added here
// as their own components on this same daemon.
import Quickshell
import Quickshell.Io
import "components"
import "config"

ShellRoot {
    Bar {}

    // energy connector lines between components (Popout POC); windows exist only
    // while links are live and effects are on
    ConnectorOverlay {}

    Launcher {
        id: launcher
    }

    // fullscreen session/power dialog (replaces wlogout); state lives in the Session singleton
    SessionOverlay {}

    // fullscreen keymap cheatsheet; state lives in the Keymap singleton
    KeymapOverlay {}

    // which-key hints for the active Hyprland submap. Passive surface: no keyboard focus and
    // an empty input mask, so it can never take a key away from the submap or eat a click.
    SubmapHints {}

    // org.freedesktop.Notifications popups. The D-Bus server itself lives in the Notifications
    // singleton and only claims the name when HYPR_NOTIFY=quickshell, so it never fights swaync.
    NotificationOverlay {}

    // Notification history: the searchable drawer over the SQLite store. Its own window rather
    // than part of the overlay, because it outlives every popup on screen.
    NotificationDrawer {}

    // Clock drawer: weather, world clocks and a calendar, opened from the bar clock or SUPER+c.
    // Sibling of the notification drawer with its own layer namespace and its own blur rule;
    // state lives in the Clocks and Weather singletons.
    ClockDrawer {}

    // fullscreen clipboard-history dialog (clipborg); state lives in the Clipboard singleton.
    // Via LazyLoader, not inline: components/ClipboardDialog.qml imports the `Clipborg` QML
    // module out of the clipborg repo (QML_IMPORT_PATH, see hypr/lua/environments.lua). A
    // failed import inside a LazyLoader costs us the dialog; inline it would abort the whole
    // shell on any machine without the clone.
    LazyLoader {
        loading: true
        source: "components/ClipboardDialog.qml"
    }

    // Driven by SUPER+/ : `qs ipc call keymap toggle`
    IpcHandler {
        target: "keymap"
        function toggle(): void {
            Keymap.toggle();
        }
        function show(): void {
            Keymap.open();
        }
        function hide(): void {
            Keymap.close();
        }
    }

    // `qs ipc call notifications …` — the public interface, and the seam the notifctl CLI story
    // grows from. Reads go through the SQLite store, so a client that cannot reach this daemon
    // (a tmux popup, an SSH session) gets the same answers from `sqlite3 <db>` directly.
    IpcHandler {
        target: "notifications"
        function dismissAll(): void {
            Notifications.dismissAll();
        }
        function dismiss(id: int): void {
            Notifications.dismiss(Notifications.entryForId(id));
        }
        function count(): int {
            return Notifications.count;
        }
        function unread(): int {
            return Notifications.unread;
        }
        function markRead(): void {
            Notifications.markRead();
        }
        // Keyboard control. `focus` is the ONLY path that lets a popup take the keyboard, and it
        // is driven by an explicit Hyprland bind (SUPER + n) — nothing about an arriving
        // notification can reach it.
        function focus(): void {
            NotifyFocus.open();
        }
        function unfocus(): void {
            NotifyFocus.close();
        }
        function toggleFocus(): void {
            NotifyFocus.toggle();
        }
        function focused(): bool {
            return NotifyFocus.active;
        }
        // Drawer (history). `drawer` is the toggle because that is what a bind wants; show and
        // hide exist for scripts that need a known end state.
        function drawer(): void {
            NotifyDrawer.toggle();
        }
        function drawerShow(): void {
            NotifyDrawer.open();
        }
        function drawerHide(): void {
            NotifyDrawer.close();
        }
        // Compose: one notification, centred, with room to write. `id` picks a live popup;
        // with no id (0) it takes the newest. It is hosted by whichever window already holds the
        // keyboard, so this never creates a surface of its own — see config/NotifyCompose.qml.
        //
        // It exists over IPC and not only on a key because that is how it gets TESTED: driving
        // the live session with `wtype` types into whatever has focus, which on a locked screen
        // is the password field.
        function compose(id: int): bool {
            const entry = id > 0 ? Notifications.entryForId(id) : (Notifications.popups.length ? Notifications.popups[0] : null);
            if (!entry)
                return false;
            return NotifyCompose.openEntry(entry, NotifyDrawer.shown ? "drawer" : "stack");
        }
        function composeClose(): void {
            NotifyCompose.close();
        }
        // What the surface would send, and by which route ("reply" over D-Bus to the client,
        // "action" into a command's {input}, or "none"). Readable without a screenshot.
        function composeState(): string {
            if (!NotifyCompose.active)
                return "closed";
            return NotifyCompose.host + " " + NotifyCompose.route + (NotifyCompose.fromHistory ? " history" : " live");
        }
        // Do Not Disturb (story: notif-dnd-core). `dnd` is the toggle a keybind wants; `dndOn`/
        // `dndOff` exist for scripts that need a known end state; `dndStatus` reports which
        // input (manual, quiet hours, both, neither) is behind the current state — readable by
        // the bar and by a test without a screenshot.
        function dnd(): void {
            NotifyDnd.toggle();
        }
        function dndOn(): void {
            NotifyDnd.on();
        }
        function dndOff(): void {
            NotifyDnd.off();
        }
        function dndStatus(): string {
            return NotifyDnd.statusText();
        }
        function dbPath(): string {
            return NotifyStore.dbPath;
        }
        // sqlite3's own `-json` rows, newest first, served from the cache the store refreshes
        // after every write — an IPC call cannot wait on a subprocess, and a client that wants
        // an arbitrary query has the database file and its documented schema.
        // Pending reminders. Cached rather than queried on demand — an IpcHandler function must
        // return immediately and cannot wait on a subprocess, the same constraint history() has.
        // Refreshed whenever the snooze timer re-arms, which is every time the set changes.
        // Snooze the newest live popup for `ms`. Exists so a snooze can be driven without the
        // keyboard — from a script, from a bar button later, and (the immediate reason) so the
        // fire/re-arm cycle can be tested without injecting keystrokes into a live session that
        // may be locked.
        function snooze(ms: int): bool {
            const list = Notifications.popups;
            if (!list.length)
                return false;
            Notifications.snooze(list[0], ms);
            return true;
        }

        function snoozed(): string {
            return NotifyStore.snoozedSummary();
        }

        function history(limit: int): string {
            return NotifyStore.recentJson(limit);
        }
    }

    // `qs ipc call timers …` (story: notif-timers). Same shape as `notifications`: the state
    // lives in the Timers singleton, the schedule lives in the store's `timers` table, and this
    // is only the door. Every call answers immediately — `list` reads the in-memory model, which
    // is the authority while this daemon is up; `sqlite3 <db> "SELECT … FROM timers"` is the
    // answer for anything else, including from a tmux popup with no shell running.
    //
    // An `id` of 0 means "the newest live timer", so a keybind never has to know one. The ids
    // here are the small per-session HANDLES `timers list` prints, not the epoch-derived row ids
    // in the database — an IpcHandler int is 32 bits and would truncate the latter.
    IpcHandler {
        target: "timers"
        // duration vocabulary is Notifications.parseDelay's: "20m", "2h", "90s", "17:30"
        function start(duration: string, label: string): int {
            return Timers.start(duration, label);
        }
        // absolute wall-clock time ("17:30"); survives a qs restart and a reboot, because the
        // row carrying wake_at is what is armed, not anything in this process
        function alarm(at: string, label: string): int {
            return Timers.alarm(at, label);
        }
        // "25m/5m/15m x4", any part optional — defaults come from NotifyConfig.timers
        function pomodoro(spec: string, label: string): int {
            return Timers.pomodoro(spec, label);
        }
        function pause(id: int): bool {
            return Timers.pause(id);
        }
        function resume(id: int): bool {
            return Timers.resume(id);
        }
        function toggle(id: int): bool {
            return Timers.toggle(id);
        }
        function reset(id: int): bool {
            return Timers.reset(id);
        }
        // 0 = NotifyConfig.timers.addMs, the same amount the card's button adds
        function extend(id: int, ms: int): bool {
            return Timers.extend(id, ms);
        }
        function cancel(id: int): bool {
            return Timers.cancel(id);
        }
        function cancelAll(): void {
            Timers.cancelAll();
        }
        // Stopwatch: counts up, so it is a bar pill rather than a card (decision 2). `stopwatch`
        // is the toggle a keybind wants; start/stop exist for scripts that need a known state.
        function stopwatch(label: string): bool {
            return Timers.stopwatchToggle(label);
        }
        function stopwatchStart(label: string): bool {
            return Timers.stopwatchStart(label);
        }
        function lap(): bool {
            return Timers.stopwatchLap();
        }
        function stop(): bool {
            return Timers.stopwatchStop();
        }
        function list(): string {
            return Timers.summary();
        }
    }

    // `qs ipc call clock …` — the clock drawer, mirroring the notifications drawer verbs.
    // `drawer` is the toggle because that is what a bind wants; show and hide exist for scripts
    // that need a known end state, and `weather` reports the fetch state so the degraded path
    // can be checked without a screenshot.
    IpcHandler {
        target: "clock"
        function drawer(): void {
            Clocks.toggle();
        }
        function drawerShow(): void {
            Clocks.open();
        }
        function drawerHide(): void {
            Clocks.close();
        }
        function refresh(): void {
            Weather.refresh();
        }
        function weather(): string {
            return Weather.provider + " " + Weather.status + (Weather.error.length ? " — " + Weather.error : "") + (Weather.current ? " · " + Math.round(Weather.current.temp) + Weather.tempUnit : "");
        }
    }

    // Driven by SUPER+Escape / bar Power button: `qs ipc call session toggle`
    IpcHandler {
        target: "session"
        function toggle(): void {
            Session.toggle();
        }
        function show(): void {
            Session.open();
        }
        function hide(): void {
            Session.close();
        }
    }

    // Driven by SUPER+V (future): `qs ipc call clipboard toggle`
    IpcHandler {
        target: "clipboard"
        function toggle(): void {
            Clipboard.toggle();
        }
        function show(): void {
            Clipboard.open();
        }
        function hide(): void {
            Clipboard.close();
        }
    }

    // Driven by hypr/scripts/Launcher.sh: `qs ipc call launcher toggle [mode]`
    IpcHandler {
        target: "launcher"
        function toggle(mode: string): void {
            launcher.toggle(mode);
        }
        function show(mode: string): void {
            launcher.open(mode);
        }
        function hide(): void {
            launcher.close();
        }
        // What the launcher is showing right now, ranked, as JSON. In-memory read only — an
        // IpcHandler function has to return a value immediately and cannot wait on a
        // subprocess — and the counterpart of `notifications history`: it answers "what did the
        // ranking decide" without a screenshot, and it is what the ranking test asserts on.
        function results(limit: int): string {
            return launcher.resultsJson(limit);
        }
        // Where the selection history lives, so a script can query the file directly.
        function dbPath(): string {
            return LauncherStore.dbPath;
        }
    }
}
