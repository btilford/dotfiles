pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Reads ~/.config/hypr/shell.local.env (the per-machine bar/launcher selection) and exposes
// which backend is active. Lets the bar gate itself so it never doubles up with waybar, and
// live-toggles when the file changes (FileView.watchChanges) with no restart.
//
// Keys: HYPR_BAR=waybar|quickshell  HYPR_LAUNCHER=rofi|quickshell  HYPR_BAR_DEV=1
//       QS_EFFECTS=full|low|off  HYPR_NOTIFY=swaync|quickshell
// HYPR_BAR_DEV renders the qs bar at the BOTTOM (no exclusive zone) for side-by-side testing
// against waybar during development.
// QS_EFFECTS=off swaps every shader (energy borders, fills, shimmer, reflections) for static
// themed fallbacks via Loaders — the shader pipeline is never instantiated, for lower-spec
// machines. "low" is reserved and currently behaves as "full".
// HYPR_NOTIFY selects the notification daemon. It defaults to swaync because only one process
// can own org.freedesktop.Notifications: the qs server is not created at all unless this says
// quickshell, so a machine that hasn't opted in can never contest the name with swaync.
//
// Every key can also be set in the ENVIRONMENT, which wins over the file. The file is per-machine
// state at a fixed $HOME path, so without this a nested session (the visual-capture harness, a
// throwaway `qs -p` rig, CI) inherits whatever the host happens to be set to and cannot select a
// backend of its own — the shell would be untestable in isolation. See "Worktrees, and why config
// needs a path seam" in the repo CLAUDE.md. Nothing exports these in a normal login session, so
// the live desktop keeps reading the file exactly as before.
Singleton {
    id: root

    property string barBackend: "waybar"
    property string launcherBackend: "rofi"
    property bool barDev: false
    property string effectsMode: "full"
    property string notifyBackend: "swaync"

    // shaders render only when effects aren't switched off; "low" reserved, treated as full
    readonly property bool effectsOn: effectsMode !== "off"

    // bar renders when quickshell is the selected bar, or in dev mode alongside waybar
    readonly property bool barVisible: barBackend === "quickshell" || barDev
    // dev mode = show at bottom with no exclusive zone (waybar keeps the top)
    readonly property bool barDevMode: barDev && barBackend !== "quickshell"

    // the qs notification server owns the D-Bus name only when explicitly selected
    readonly property bool notificationsEnabled: notifyBackend === "quickshell"

    function parseEnv() {
        const t = envFile.text();
        let bar = "waybar";
        let launcher = "rofi";
        let dev = false;
        let effects = "full";
        let notify = "swaync";
        if (t) {
            for (const line of t.split("\n")) {
                const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
                if (!m)
                    continue;
                if (m[1] === "HYPR_BAR")
                    bar = m[2];
                else if (m[1] === "HYPR_LAUNCHER")
                    launcher = m[2];
                else if (m[1] === "HYPR_BAR_DEV")
                    dev = (m[2] === "1" || m[2] === "true");
                else if (m[1] === "QS_EFFECTS")
                    effects = m[2];
                else if (m[1] === "HYPR_NOTIFY")
                    notify = m[2];
            }
        }
        // environment overrides the file, key by key — an unset var leaves the file's value alone
        root.barBackend = envOr("HYPR_BAR", bar);
        root.launcherBackend = envOr("HYPR_LAUNCHER", launcher);
        const devRaw = envOr("HYPR_BAR_DEV", dev ? "1" : "0");
        root.barDev = (devRaw === "1" || devRaw === "true");
        root.effectsMode = envOr("QS_EFFECTS", effects);
        root.notifyBackend = envOr("HYPR_NOTIFY", notify);
    }

    // Quickshell.env returns undefined for an unset variable and "" for an empty one; treat both
    // as absent so `HYPR_NOTIFY= qs` doesn't silently select a nameless backend.
    function envOr(key: string, fallback: string): string {
        const v = Quickshell.env(key);
        return (v === undefined || v === null || v === "") ? fallback : v;
    }

    FileView {
        id: envFile
        path: Quickshell.env("HOME") + "/.config/hypr/shell.local.env"
        watchChanges: true
        onLoaded: root.parseEnv()
        onFileChanged: {
            reload();
            root.parseEnv();
        }
    }

    Component.onCompleted: parseEnv()
}
