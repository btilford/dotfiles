import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"
import "notifications"

// Notification popup stack. A view and nothing else: every notification, timer and D-Bus
// interaction lives in the Notifications singleton, so this window can be replaced (drawer,
// modal, per-anchor groups) without touching the server.
//
// The window is sized to the cards rather than covering the screen, so there is no invisible
// input-blocking surface over the desktop and the compositor does the centering for us.
PanelWindow {
    id: win

    readonly property var placement: Notifications.placement
    // v1 renders one stack at the configured anchor. Per-notification anchors (entry.anchorH /
    // anchorV, already carried on the model) become additional stacks in the placement story.
    readonly property bool anchorLeft: placement.anchorH === "left"
    readonly property bool anchorRight: placement.anchorH === "right"
    readonly property bool anchorTop: placement.anchorV === "top"
    readonly property bool anchorBottom: placement.anchorV === "bottom"

    visible: Shell.notificationsEnabled && Notifications.count > 0
    color: "transparent"

    // follows the active monitor, like the launcher and session overlay
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    WlrLayershell.layer: WlrLayer.Overlay
    // popups never take the keyboard — that would break typing. On-demand focus is its own story.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-notifications"
    // sit inside the bar's exclusive zone, and never reserve space of our own
    exclusiveZone: 0

    anchors {
        left: win.anchorLeft
        right: win.anchorRight
        top: win.anchorTop
        bottom: win.anchorBottom
    }
    margins {
        left: win.placement.margin
        right: win.placement.margin
        top: win.placement.margin
        bottom: win.placement.margin
    }

    implicitWidth: win.placement.cardWidth
    implicitHeight: Math.max(1, stack.implicitHeight)

    // overflow beyond maxVisible stays in the model and surfaces as slots free up; the
    // "+N more" indicator and the drawer it belongs to are later stories.
    // `popups` is newest-first: "down" shows newest at the top, "up" flips so the newest
    // card sits closest to the bottom edge it grows from.
    readonly property var visiblePopups: {
        const shown = Notifications.popups.slice(0, win.placement.maxVisible);
        return win.placement.stack === "up" ? shown.reverse() : shown;
    }

    Column {
        id: stack
        width: parent.width
        spacing: win.placement.spacing

        Repeater {
            model: win.visiblePopups

            delegate: NotificationCard {
                required property var modelData
                entry: modelData
                width: stack.width
            }
        }
    }
}
