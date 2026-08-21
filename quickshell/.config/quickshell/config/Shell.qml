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
//       QS_SUBMAP_HINTS=1|0  QS_SUBMAP_HINTS_DELAY=<ms>  QS_SUBMAP_HINTS_OPACITY=<0.05..1>
//       QS_NOW_PLAYING=1|0  QS_NOW_PLAYING_TIMEOUT=<ms>  QS_NOW_PLAYING_MONITOR=<desc|name>
//       QS_LAUNCHER_HISTORY=1|0  QS_LAUNCHER_HALFLIFE_DAYS=<days>
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
    // which-key hints for the active submap (components/SubmapHints.qml), and how long a submap
    // must stay active before they appear — a map you pass straight through never flashes.
    property bool submapHintsEnabled: true
    property int submapHintsDelay: 250
    // Surface opacity of the hints slab. Its own knob rather than borrowing
    // NotifyConfig.drawer.opacity, which is what it used to read: the two surfaces have
    // nothing to do with each other, and sharing the value meant tuning the hints for
    // legibility would silently restyle the notification drawer as well.
    //
    // Much lower than the drawer's 0.35, and NOT a legibility setting — that was the
    // misconception that sent this round in circles. The slab colour is a Rectangle fill;
    // its alpha does not touch the child Text items, which stay fully opaque at any value.
    // So this only controls how much tint sits between you and the background, and raising
    // it does not make the hints more readable — it just tints everything behind them with
    // Theme.surface until the panel reads as a solid brown slab rather than glass.
    property real submapHintsOpacity: 0.05

    // MPRIS now-playing cluster in the bar (components/bar/NowPlaying.qml).
    property bool nowPlayingEnabled: true
    // How long a PAUSED track stays on the bar before the cluster hides. Hiding the instant
    // something is paused makes the bar jump on every pause/resume, which is the jitter this
    // exists to avoid; resuming cancels it.
    property int nowPlayingTimeoutMs: 45000
    // Which monitor shows it — media is one stream, not per-screen state, so it is not
    // duplicated across every bar the way Audio/Network/Clock are. A monitor DESCRIPTION
    // (substring, case-insensitive) or a bare connector name; description is preferred because
    // connector names shuffle across reconnects.
    //
    // Empty by DEFAULT and it stays that way in this repo: a real description carries the
    // panel's hardware serial, which is exactly what mise run lint:private blocks from a
    // publicly mirrored tree. It belongs in the untracked shell.local.env. Empty means every
    // bar, which is also the fallback when the configured monitor is not connected.
    property string nowPlayingMonitor: ""

    // Launcher selection history and usage ranking (config/LauncherStore.qml). Off means the
    // store is never opened and nothing is recorded, and the launcher sorts alphabetically
    // exactly as it did before the feature existed.
    property bool launcherHistoryEnabled: true
    // How long a selection keeps half its weight. A week is eager and forgetful, a quarter is
    // stubborn; 30 days is a starting value, and it lives in config so that adjusting it is not
    // a code change. Floored at one day — a 0 makes every decay factor NaN and turns ranking
    // into noise rather than switching it off, which is what QS_LAUNCHER_HISTORY=0 is for.
    property real launcherHalfLifeDays: 30

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
        let hints = "1";
        let hintsDelay = "250";
        let hintsOpacity = "0.05";
        let nowPlaying = "1";
        let nowPlayingTimeout = "45000";
        let nowPlayingMonitor = "";
        let launcherHistory = "1";
        let launcherHalfLife = "30";
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
                else if (m[1] === "QS_SUBMAP_HINTS")
                    hints = m[2];
                else if (m[1] === "QS_SUBMAP_HINTS_DELAY")
                    hintsDelay = m[2];
                else if (m[1] === "QS_SUBMAP_HINTS_OPACITY")
                    hintsOpacity = m[2];
                else if (m[1] === "QS_NOW_PLAYING")
                    nowPlaying = m[2];
                else if (m[1] === "QS_NOW_PLAYING_TIMEOUT")
                    nowPlayingTimeout = m[2];
                else if (m[1] === "QS_NOW_PLAYING_MONITOR")
                    nowPlayingMonitor = m[2];
                else if (m[1] === "QS_LAUNCHER_HISTORY")
                    launcherHistory = m[2];
                else if (m[1] === "QS_LAUNCHER_HALFLIFE_DAYS")
                    launcherHalfLife = m[2];
            }
        }
        // environment overrides the file, key by key — an unset var leaves the file's value alone
        root.barBackend = envOr("HYPR_BAR", bar);
        root.launcherBackend = envOr("HYPR_LAUNCHER", launcher);
        const devRaw = envOr("HYPR_BAR_DEV", dev ? "1" : "0");
        root.barDev = (devRaw === "1" || devRaw === "true");
        root.effectsMode = envOr("QS_EFFECTS", effects);
        root.notifyBackend = envOr("HYPR_NOTIFY", notify);
        const hintsRaw = envOr("QS_SUBMAP_HINTS", hints);
        root.submapHintsEnabled = !(hintsRaw === "0" || hintsRaw === "off" || hintsRaw === "false");
        // a garbage delay must not mean "never show" — fall back rather than trust it
        const delay = parseInt(envOr("QS_SUBMAP_HINTS_DELAY", hintsDelay), 10);
        root.submapHintsDelay = (isNaN(delay) || delay < 0) ? 250 : delay;
        // Same guard as the delay, plus a floor: 0 is a valid float and would render the
        // slab fully invisible while the text still drew, which reads as a broken overlay
        // rather than as a setting. Clamped to something still recognisably a surface.
        const hOpacity = parseFloat(envOr("QS_SUBMAP_HINTS_OPACITY", hintsOpacity));
        root.submapHintsOpacity = (isNaN(hOpacity) || hOpacity < 0.05 || hOpacity > 1) ? 0.05 : hOpacity;
        const npRaw = envOr("QS_NOW_PLAYING", nowPlaying);
        root.nowPlayingEnabled = !(npRaw === "0" || npRaw === "off" || npRaw === "false");
        // Same guard as the hints delay, with a floor: a 0 here would hide the cluster the
        // frame a track pauses, which reads as the bar flickering rather than as a setting.
        const npTimeout = parseInt(envOr("QS_NOW_PLAYING_TIMEOUT", nowPlayingTimeout), 10);
        root.nowPlayingTimeoutMs = (isNaN(npTimeout) || npTimeout < 1000) ? 45000 : npTimeout;
        root.nowPlayingMonitor = envOr("QS_NOW_PLAYING_MONITOR", nowPlayingMonitor);
        const lhRaw = envOr("QS_LAUNCHER_HISTORY", launcherHistory);
        root.launcherHistoryEnabled = !(lhRaw === "0" || lhRaw === "off" || lhRaw === "false");
        const halfLife = parseFloat(envOr("QS_LAUNCHER_HALFLIFE_DAYS", launcherHalfLife));
        root.launcherHalfLifeDays = (isNaN(halfLife) || halfLife < 1) ? 30 : halfLife;
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
