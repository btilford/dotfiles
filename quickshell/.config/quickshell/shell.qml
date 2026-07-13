// Default quickshell config (loaded by bare `qs` / targeted by `qs ipc`).
// Increment 1: launcher only. Bar, notifications, lock, OSD, dashboard get added here
// as their own components on this same daemon.
import Quickshell
import Quickshell.Io
import "components"
import "config"

ShellRoot {
    Bar {}

    Launcher {
        id: launcher
    }

    // fullscreen session/power dialog (replaces wlogout); state lives in the Session singleton
    SessionOverlay {}

    // fullscreen keymap cheatsheet; state lives in the Keymap singleton
    KeymapOverlay {}

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
