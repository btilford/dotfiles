pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Motion policy for the animated shaders (EnergyBorder, Shimmer, EnergyFill, EnergyGlyph).
//
// Why this exists: every effect animated its `u_time` forever while visible, so each bar redrew
// at the display's refresh rate on every monitor even when nothing changed. On a GPU-scanned
// output that is cheap. On a DisplayLink (evdi) output every changed frame is compressed in
// software by DisplayLinkManager: two 1440p bars cost it about one CPU core, around the clock
// (measured 2026-11-25: 125% with qs running, 1% with qs stopped).
//
// The policy is read by components/MotionClock.qml, which drives each effect's time uniform.
//
// Modes:
//   always     every visible effect animates (the old behaviour)
//   focus      only effects on the focused monitor animate
//   proximity  only effects the pointer is near animate
//   hybrid     focus OR proximity, and proximity also speeds the effect up and brightens it
//   still      nothing animates; effects hold their last frame
//
// Independently of the mode, screens whose connector name matches `capScreens` tick their
// effects at `capFps` instead of every frame (0 = no cap).
//
// Startup values come from Shell (shell.local.env / environment). Change them live with
//   qs ipc call motion mode <mode>
//   qs ipc call motion cap <fps>
//   qs ipc call motion screens <regex>
//   qs ipc call motion status
Singleton {
    id: root

    readonly property var modes: ["always", "focus", "proximity", "hybrid", "still"]

    property string mode: Shell.motionMode
    property int capFps: Shell.motionCapFps
    property string capScreens: Shell.motionCapScreens

    //! How close (px, any side) the pointer must be for an effect to count as "near".
    property real proximityPx: 64
    //! Extra speed at full proximity in hybrid/proximity mode (0.75 = 1.75x speed).
    property real boostSpeed: 0.75
    //! Extra shimmer strength at full proximity (1.0 = twice as bright).
    property real boostStrength: 1.0
    //! Extra border thickness at full proximity (1.0 = twice as thick). The band grows
    //! inward from the edge, so the item's geometry never changes.
    property real boostThickness: 1.0

    readonly property string focusedScreen: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    readonly property bool usesProximity: mode === "proximity" || mode === "hybrid"
    readonly property bool usesBoost: mode === "hybrid" || mode === "proximity"

    // A bad regex from the env or IPC must not throw inside every effect's binding.
    readonly property var _capRe: {
        try {
            return root.capScreens ? new RegExp(root.capScreens) : null;
        } catch (e) {
            console.warn("Motion: bad cap screen pattern", root.capScreens, e);
            return null;
        }
    }

    //! True when effects on this screen should tick at capFps instead of every frame.
    function capped(screenName: string): bool {
        return root.capFps > 0 && root._capRe !== null && screenName !== "" && root._capRe.test(screenName);
    }

    //! Whether an effect on `screenName` should animate. `near` = pointer proximity.
    function wants(screenName: string, near: bool): bool {
        switch (root.mode) {
        case "always":
            return true;
        case "focus":
            return screenName === root.focusedScreen;
        case "proximity":
            return near;
        case "hybrid":
            return near || screenName === root.focusedScreen;
        default:
            return false;
        }
    }

    function status(): string {
        return "mode=" + root.mode + " cap=" + root.capFps + "fps screens=/" + root.capScreens + "/ focused=" + root.focusedScreen;
    }
}
