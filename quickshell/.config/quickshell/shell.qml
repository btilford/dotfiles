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
    }
}
