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
    property int gap: Theme.popoutGap // stand-off from the bar; the connector arc spans it
    property bool dismissable: true
    // Animated energy border around the surface (off for tiny tooltips)
    property bool energyBorder: true
    // Energy connector line from the anchor item to the surface (off for tooltips)
    property bool connector: true
    // Water-mirror reflection under the surface (off for tooltips). Downward popouts only —
    // upward (dev-mode) popouts have no room below the surface.
    property bool reflection: true
    default property alias content: body.data

    readonly property bool upward: Shell.barDevMode
    readonly property int reflH: reflection && !upward && Shell.effectsOn ? Math.ceil(surface.implicitHeight * 0.3) + 2 : 0

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
    implicitHeight: surface.implicitHeight + slide + gap + reflH
    color: "transparent"
    visible: false

    // click-anywhere-outside to dismiss (skipped for tooltips)
    HyprlandFocusGrab {
        active: pop.dismissable && pop.shown
        windows: [pop]
        onCleared: pop.close()
    }

    // --- energy connector: anchor item → surface top (bottom in dev mode) ---
    // Endpoints in screen coords: the bar window is anchored to the full screen edge, so
    // anchor-item scene coords == screen coords (same assumption Shimmer relies on). The
    // popup itself is centered under the anchor by the compositor; near screen edges it
    // may slide and the computed endpoint drifts — accepted, the line stays near-vertical.
    readonly property string _connId: "popout-" + pop.toString()
    property real _connEnergy: 0
    property bool _connLive: false
    on_ConnEnergyChanged: if (_connLive)
        Connectors.update(_connId, { energy: _connEnergy })

    // POC screen identity: popouts open from a click on the focused monitor's bar.
    // (PopupWindow has no reliable screen of its own; revisit for the dialog fan-out.)
    function _connScreenName() {
        const m = Hyprland.focusedMonitor;
        return m ? m.name : "";
    }

    function _registerConn() {
        if (!connector || !anchorItem || !Shell.effectsOn)
            return;
        const p1 = anchorItem.mapToItem(null, anchorItem.width / 2, pop.upward ? 0 : anchorItem.height);
        const y2 = pop.upward ? (p1.y - pop.gap - 1) : (p1.y + pop.gap + 1);
        Connectors.register({
            id: _connId,
            screenName: _connScreenName(),
            x1: p1.x,
            y1: pop.upward ? p1.y + 2 : p1.y - 2, // inset into the icon so the arc joins it
            x2: p1.x,
            y2: y2,
            energy: 1.0
        });
        _connLive = true;
        connDecay.restart();
    }

    function _unregisterConn() {
        if (!_connLive)
            return;
        _connLive = false;
        connDecay.stop();
        connFade.stop();
        Connectors.unregister(_connId);
    }

    // spike on open, settle to a steady shimmer
    SequentialAnimation {
        id: connDecay
        NumberAnimation {
            target: pop
            property: "_connEnergy"
            from: 1.0
            to: 0.55
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    // fade out on close, then drop the link
    SequentialAnimation {
        id: connFade
        NumberAnimation {
            target: pop
            property: "_connEnergy"
            to: 0
            duration: Theme.animFast
        }
        ScriptAction {
            script: pop._unregisterConn()
        }
    }

    onShownChanged: {
        if (shown)
            _registerConn();
        else if (_connLive)
            connFade.restart();
    }
    Component.onDestruction: _unregisterConn()

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
        // static fallback border when the energy border is disabled (tooltips)
        border.color: pop.energyBorder ? "transparent" : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
        border.width: pop.energyBorder ? 0 : Theme.borderThin

        // animated energy border tracing the rounded surface
        EnergyBorder {
            anchors.fill: parent
            visible: pop.energyBorder
            radius: parent.radius
            thickness: Theme.borderThickness
            energy: pop.shown ? 0.7 : 0.0
        }

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

        // cursor-lit glimmer over the surface
        Shimmer {
            anchors.fill: parent
            radius: parent.radius
        }
    }

    // water-mirror reflection under the surface (slides + fades with it)
    Reflection {
        visible: pop.reflection && !pop.upward
        sourceItem: surface
        anchors.top: surface.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: surface.horizontalCenter
        ratio: 0.3
        opacity: surface.opacity
    }
}
