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
            if (e.queued || e.drawerOnly || !e.resolved)
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
            if (!e.queued && !e.drawerOnly && e.resolved && scope.keyOf(e) === key)
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

            // This window holds the keyboard: focus mode is on and the selected card is in THIS
            // stack. Exactly one window at a time, because two exclusive layer surfaces on one
            // output fight over the grab and the loser silently stops receiving keys.
            readonly property bool focused: NotifyFocus.active && NotifyFocus.focusedKey === win.modelData

            WlrLayershell.layer: WlrLayer.Overlay
            // Popups never take the keyboard on arrival — that would eat keystrokes out of
            // whatever is being typed. The grab happens only while focus mode is on, which only
            // the explicit `notifications focus` bind turns on (story: notif-keyboard-control).
            WlrLayershell.keyboardFocus: win.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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

            // Vim-style key handling for focus mode. It lives on the window rather than on a card
            // because the selection moves between cards (and between stacks) while the grab has
            // to stay put — a per-card handler would lose the keyboard the moment its card left.
            //
            // The scheme is the KeymapOverlay's: j/k move, gg/G ends, Esc leaves. The verbs that
            // belong to unbuilt stories (snooze, drawer, dismiss-group) are bound HERE and NOW so
            // the muscle memory does not change when those stories land; each one reports what it
            // still needs instead of silently doing nothing.
            Item {
                id: keys
                anchors.fill: parent
                focus: true
                property bool pendingG: false

                Keys.onPressed: event => {
                    let g = false;
                    if (event.key === Qt.Key_Escape)
                        NotifyFocus.close();
                    else if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                        NotifyFocus.move(1);
                    else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                        NotifyFocus.move(-1);
                    else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier))
                        NotifyFocus.last();
                    else if (event.key === Qt.Key_G) {
                        if (keys.pendingG)
                            NotifyFocus.first();
                        else
                            g = true;
                    } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ShiftModifier))
                        NotifyFocus.dismissGroup();
                    else if (event.key === Qt.Key_D || event.key === Qt.Key_X)
                        NotifyFocus.dismissSelected();
                    else if (event.key === Qt.Key_A && (event.modifiers & Qt.ShiftModifier))
                        NotifyFocus.dismissAll();
                    else if (event.key === Qt.Key_S)
                        NotifyFocus.snoozeSelected(15 * 60 * 1000);
                    else if (event.key === Qt.Key_R)
                        NotifyFocus.snoozeSelected(0); // "remind me at ___" — prompt is notif-actions
                    else if (event.key === Qt.Key_O || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (event.key === Qt.Key_O)
                            NotifyFocus.openDrawer();
                        else
                            NotifyFocus.activateSelected();
                    } else
                        return; // unhandled: don't accept it, and don't clear the pending g
                    keys.pendingG = g;
                    event.accepted = true;
                }
            }

            // The grab is a compositor-level thing; Qt still has to be told which item reads it.
            onFocusedChanged: if (win.focused)
                keys.forceActiveFocus()

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

            // Key legend, only while this stack holds the keyboard. It sits outside `column` on
            // purpose: inside, it would be part of the input mask and would make the strip under
            // the stack swallow desktop clicks.
            Rectangle {
                id: legend
                visible: win.focused
                width: legendText.implicitWidth + Theme.pad * 2
                height: legendText.implicitHeight + 8
                radius: Theme.radius
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity)
                border.width: Theme.borderThin
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)

                // centred under the stack, but never past the screen edge: the legend is wider
                // than a card, so a right-anchored stack would push half of it off the output
                x: Math.max(scope.placement.margin, Math.min(win.width - width - scope.placement.margin, column.x + (column.width - width) / 2))
                // below the stack, except when the stack is already against the bottom edge
                y: win.anchorV === "bottom" ? column.y - height - scope.placement.spacing : column.y + column.height + scope.placement.spacing

                Text {
                    id: legendText
                    anchors.centerIn: parent
                    text: (NotifyFocus.indexOfSelected() + 1) + "/" + NotifyFocus.order.length + " · [j/k] move · [d] dismiss · [D] app · [A] all · [s] snooze · [o] drawer · [Esc] release"
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
}
