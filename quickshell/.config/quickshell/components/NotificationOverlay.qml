import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"
import "notifications"

// Notification popup stacks. A view and nothing else: every notification, timer and D-Bus
// interaction lives in the Notifications singleton, and placement/motion come from NotifyConfig —
// this file turns that data into windows and pixels and holds no state of its own.
//
// One window per (monitor, anchor) pair that currently has cards, because entries carry their own
// anchor and monitor: the default stack follows the focused monitor at the configured anchor, and
// a rule (or the config's screenName) can put another source somewhere else entirely.
Scope {
    id: scope

    readonly property var placement: Notifications.placement
    readonly property var motion: Notifications.motion

    readonly property var focusedScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    // "" = follow focus. A named monitor that is not connected right now falls back to the focused
    // one: a notification pinned to an unplugged screen must still be seen.
    function screenFor(name) {
        if (!name)
            return scope.focusedScreen;
        for (const s of Quickshell.screens)
            if (s.name === name)
                return s;
        return scope.focusedScreen;
    }

    function keyOf(entry) {
        return entry.screenName + "|" + entry.anchorH + "|" + entry.anchorV;
    }

    // The window model is the set of stack KEYS, not the entries: keys are stable strings, so a
    // card arriving or leaving updates an existing window instead of tearing one down and building
    // another (which would flash the whole stack).
    readonly property var stackKeys: {
        const keys = [];
        for (const e of Notifications.popups) {
            if (e.queued)
                continue;
            const k = scope.keyOf(e);
            if (keys.indexOf(k) < 0)
                keys.push(k);
        }
        return keys.sort();
    }

    function entriesFor(key) {
        const out = [];
        for (const e of Notifications.popups)
            if (!e.queued && scope.keyOf(e) === key)
                out.push(e);
        return out;
    }

    Variants {
        model: scope.stackKeys

        PanelWindow {
            id: win

            required property var modelData

            readonly property var parts: win.modelData.split("|")
            readonly property string stackScreen: win.parts[0]
            readonly property string anchorH: win.parts[1]
            readonly property string anchorV: win.parts[2]

            // `Notifications.popups` is referenced so these re-evaluate when the model changes;
            // the per-entry `queued` flags read inside entriesFor register their own dependencies.
            readonly property var entries: {
                Notifications.popups;
                return scope.entriesFor(win.modelData);
            }
            readonly property int overflow: {
                Notifications.popups;
                return Notifications.overflowFor(win.stackScreen, win.anchorH, win.anchorV);
            }
            // `popups` is newest-first: "down" shows newest at the top, "up" flips so the newest
            // card sits closest to the bottom edge the stack grows from.
            readonly property var ordered: scope.placement.stack === "up" ? win.entries.slice().reverse() : win.entries

            screen: scope.screenFor(win.stackScreen)
            visible: Shell.notificationsEnabled && win.entries.length > 0
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            // popups never take the keyboard — that would break typing. On-demand focus is its own story.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-notifications"

            // The window covers the whole output, INCLUDING the bar's exclusive zone, so window
            // coordinates are screen coordinates and the dwell can fly a card into the bar bell.
            // The cost of a full-screen surface is that it would swallow every click on the
            // desktop, so input is masked to the cards themselves — everything outside `column` is
            // click-through, and the stack reserves no space of its own either.
            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            mask: Region {
                item: column
            }

            // ExclusionMode.Ignore also means the bar no longer pushes us off its strip, so a
            // top-anchored stack has to step around it by hand. The hub height is used for both
            // bar sizes: overshooting a minimal bar by a few pixels is invisible, colliding with a
            // hub bar is not.
            readonly property int barInset: Shell.barVisible ? Theme.barHeightHub : 0
            readonly property int topMargin: scope.placement.margin + (Shell.barDevMode ? 0 : win.barInset)
            readonly property int bottomMargin: scope.placement.margin + (Shell.barDevMode ? win.barInset : 0)

            // Leaving cards are reparented here for their exit: a full-window layer above the
            // stack, so a card can travel to the bar bell without being confined to (or hidden
            // by) the collapsing slot it came from. It is never part of the input mask.
            Item {
                id: flightHost
                anchors.fill: parent
                z: 1
            }

            Column {
                id: column

                width: scope.placement.cardWidth
                spacing: scope.placement.spacing

                x: win.anchorH === "left" ? scope.placement.margin : (win.anchorH === "right" ? win.width - width - scope.placement.margin : (win.width - width) / 2)
                y: win.anchorV === "top" ? win.topMargin : (win.anchorV === "bottom" ? win.height - height - win.bottomMargin : (win.height - height) / 2)

                // cards closing the gap after one leaves, and the whole stack re-centering when it
                // grows or shrinks — the same easing as everything else in the shell
                move: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: scope.motion.reflowMs
                        easing.type: Theme.easing
                    }
                }

                Behavior on y {
                    NumberAnimation {
                        duration: scope.motion.reflowMs
                        easing.type: Theme.easing
                    }
                }

                // the overflow tail sits at the far end from the newest card, so a growing stack
                // never pushes the "+N more" line under the card the user is reading
                OverflowIndicator {
                    width: column.width
                    overflow: scope.placement.stack === "up" ? win.overflow : 0
                }

                Repeater {
                    model: win.ordered

                    delegate: NotificationSlot {
                        required property var modelData
                        entry: modelData
                        width: column.width
                        anchorH: win.anchorH
                        anchorV: win.anchorV
                        bell: win.screen ? (Notifications.bellAnchors[win.screen.name] || null) : null
                        flightLayer: flightHost
                    }
                }

                OverflowIndicator {
                    width: column.width
                    overflow: scope.placement.stack === "up" ? 0 : win.overflow
                }
            }
        }
    }
}
