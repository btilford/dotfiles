import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../config"

// Fans three energy connector lines from the bar's section feet (published by Bar.qml
// into Connectors.sectionAnchors) down to a dialog surface: left foot → the surface's
// LEFT edge at ⅓ height (edge-routed bezier arriving perpendicular), center → top-center
// (straight), right foot → RIGHT edge at ⅓ height. Rendered IN the dialog's own window —
// above any dim scrim, which the separate lower-layer ConnectorOverlay can't manage —
// so instantiate it inside the dialog window ABOVE the scrim, and drive `active` from
// the shown state:
//
//     ConnectorFan { box: panel; active: win.visible }
//
// Registration waits out the dialog's entrance animation so endpoints land on settled
// geometry; the lines then spike and decay to `steady` like the Popout connector.
// Endpoints are computed in this item's coordinate space (mapFromItem / mapToItem), and
// the bar feet — published in screen coords — are corrected for windows that shrink
// below the bar's exclusive zone, so the fan also works in windows without
// ExclusionMode.Ignore (e.g. the clipborg dialog).
Item {
    id: root

    //! the dialog surface the fan feeds
    property Item box
    //! drive from the dialog's shown/visible state
    property bool active: false
    //! settle level after the open spike
    property real steady: 0.55
    //! px before the endpoint where the side lines turn into the edge — the run from the
    //! foot is a near-straight diagonal, only the last stretch corners to arrive
    //! perpendicular (a full sweeping curve ate too much screen)
    property real elbow: 40

    visible: Shell.effectsOn

    property var _links: []
    property real _energy: 0
    property bool _live: false

    on_EnergyChanged: {
        if (!_live)
            return;
        root._links = root._links.map(l => Object.assign({}, l, {
            energy: _energy
        }));
    }

    onActiveChanged: {
        if (active) {
            settleTimer.restart();
        } else {
            settleTimer.stop();
            if (_live)
                fade.restart();
        }
    }

    Timer {
        id: settleTimer
        interval: Theme.animMed + 30
        onTriggered: root._register()
    }

    function _register() {
        if (!root.active || !root.box || !Shell.effectsOn)
            return;
        const w = QsWindow.window;
        const sn = w && w.screen ? w.screen.name : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "");
        const feet = Connectors.sectionAnchors[sn];
        if (!feet || feet.length < 3)
            return;
        // feet are screen coords; if this window sits below the bar's exclusive zone,
        // window coords are shifted up by the difference
        const offY = w && w.screen ? w.screen.height - w.height : 0;
        const f = feet.map(p => root.mapFromItem(null, p.x, p.y - offY));
        // surface corners in local space
        const tl = root.box.mapToItem(root, 0, 0);
        const tr = root.box.mapToItem(root, root.box.width, 0);
        const third = root.box.height / 3;
        root._links = [
            // left foot → left edge at ⅓ height. Control point just OUTSIDE the endpoint
            // on its horizontal: the run is a near-straight diagonal that corners in the
            // last `elbow` px to hit the edge at a right angle
            {
                x1: f[0].x, y1: f[0].y - 2,
                x2: tl.x - 2, y2: tl.y + third,
                cx: tl.x - 2 - root.elbow, cy: tl.y + third,
                energy: 1.0
            },
            // center → top-center, straight drop
            {
                x1: f[1].x, y1: f[1].y - 2,
                x2: (tl.x + tr.x) / 2, y2: tl.y + 2,
                energy: 1.0
            },
            // right foot → right edge at ⅓ height, mirrored
            {
                x1: f[2].x, y1: f[2].y - 2,
                x2: tr.x + 2, y2: tr.y + third,
                cx: tr.x + 2 + root.elbow, cy: tr.y + third,
                energy: 1.0
            }
        ];
        _live = true;
        decay.restart();
    }

    function _unregister() {
        if (!_live)
            return;
        _live = false;
        decay.stop();
        root._links = [];
    }

    SequentialAnimation {
        id: decay
        NumberAnimation {
            target: root
            property: "_energy"
            from: 1.0
            to: root.steady
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    SequentialAnimation {
        id: fade
        NumberAnimation {
            target: root
            property: "_energy"
            to: 0
            duration: Theme.animFast
        }
        ScriptAction {
            script: root._unregister()
        }
    }

    ConnectorLines {
        links: root._links
        // dialog fan lines are the main event — double the popout stub's weight
        thickness: Theme.connectorThickness * 2
    }
}
