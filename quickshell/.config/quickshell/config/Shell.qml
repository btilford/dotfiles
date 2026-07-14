pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Reads ~/.config/hypr/shell.local.env (the per-machine bar/launcher selection) and exposes
// which backend is active. Lets the bar gate itself so it never doubles up with waybar, and
// live-toggles when the file changes (FileView.watchChanges) with no restart.
//
// Keys: HYPR_BAR=waybar|quickshell  HYPR_LAUNCHER=rofi|quickshell  HYPR_BAR_DEV=1
//       QS_EFFECTS=full|low|off
// HYPR_BAR_DEV renders the qs bar at the BOTTOM (no exclusive zone) for side-by-side testing
// against waybar during development.
// QS_EFFECTS=off swaps every shader (energy borders, fills, shimmer, reflections) for static
// themed fallbacks via Loaders — the shader pipeline is never instantiated, for lower-spec
// machines. "low" is reserved and currently behaves as "full".
Singleton {
    id: root

    property string barBackend: "waybar"
    property string launcherBackend: "rofi"
    property bool barDev: false
    property string effectsMode: "full"

    // shaders render only when effects aren't switched off; "low" reserved, treated as full
    readonly property bool effectsOn: effectsMode !== "off"

    // bar renders when quickshell is the selected bar, or in dev mode alongside waybar
    readonly property bool barVisible: barBackend === "quickshell" || barDev
    // dev mode = show at bottom with no exclusive zone (waybar keeps the top)
    readonly property bool barDevMode: barDev && barBackend !== "quickshell"

    function parseEnv() {
        const t = envFile.text();
        let bar = "waybar";
        let launcher = "rofi";
        let dev = false;
        let effects = "full";
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
            }
        }
        root.barBackend = bar;
        root.launcherBackend = launcher;
        root.barDev = dev;
        root.effectsMode = effects;
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
