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

    // org.freedesktop.Notifications popups. The D-Bus server itself lives in the Notifications
    // singleton and only claims the name when HYPR_NOTIFY=quickshell, so it never fights swaync.
    NotificationOverlay {}

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
        function dbPath(): string {
            return NotifyStore.dbPath;
        }
        // sqlite3's own `-json` rows, newest first, served from the cache the store refreshes
        // after every write — an IPC call cannot wait on a subprocess, and a client that wants
        // an arbitrary query has the database file and its documented schema.
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
