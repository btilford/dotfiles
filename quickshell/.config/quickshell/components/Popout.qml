import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../config"

// Reusable slide-out-from-bar panel: a PopupWindow anchored to a bar module whose inner surface
// SLIDES + fades from the bar edge. close() animates out first, then unmaps the window.
//
// Direction: a top bar drops popouts DOWNWARD. In dev mode the bar sits at the screen BOTTOM, so
// popouts open UPWARD instead (otherwise qs flips them back over the anchor, covering it). A small
// gap keeps the surface off the icon so it never steals the hover.
//
// Dismiss: dismissable popouts grab Hyprland focus while open; a click anywhere outside closes them.
// Tooltips set dismissable:false (a tooltip must not steal clicks — it closes on hover-out).
PopupWindow {
    id: pop

    property Item anchorItem
    property int popWidth: 260
    property int slide: 10 // travel distance of the slide-in
    property int gap: 6    // space between the surface and the bar edge
    property bool dismissable: true
    default property alias content: body.data

    readonly property bool upward: Shell.barDevMode

    // open state drives the inner animation; the window stays mapped until the close anim ends
    property bool shown: false
    function open() {
        visible = true;
        shown = true;
    }
    function close() {
        shown = false;
    }
    function toggle() {
        if (shown)
            close();
        else
            open();
    }

    anchor.item: anchorItem
    anchor.edges: upward ? Edges.Top : Edges.Bottom
    anchor.gravity: upward ? Edges.Top : Edges.Bottom

    implicitWidth: popWidth
    implicitHeight: surface.implicitHeight + slide + gap
    color: "transparent"
    visible: false

    // click-anywhere-outside to dismiss (skipped for tooltips)
    HyprlandFocusGrab {
        active: pop.dismissable && pop.shown
        windows: [pop]
        onCleared: pop.close()
    }

    Rectangle {
        id: surface
        width: pop.popWidth
        implicitHeight: body.implicitHeight + Theme.pad * 2
        height: implicitHeight
        // sit at the bar-adjacent edge with a gap; upward popouts hug the bottom of the window
        y: {
            const base = pop.upward ? (pop.height - height - pop.gap) : pop.gap;
            return base + (pop.shown ? 0 : (pop.upward ? pop.slide : -pop.slide));
        }
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity)
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
        border.width: 1

        opacity: pop.shown ? 1 : 0
        Behavior on y {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Easing.OutBack
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
                onRunningChanged: if (!running && !pop.shown)
                    pop.visible = false
            }
        }

        Column {
            id: body
            x: Theme.pad
            y: Theme.pad
            width: parent.width - Theme.pad * 2
            spacing: 8
        }
    }
}
