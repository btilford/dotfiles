import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../config"

// Fans three energy connector lines from the bar's section feet (published by Bar.qml
// into Connectors.sectionAnchors) down to a dialog surface: left foot → the surface's
// LEFT edge at ¼ height (edge-routed bezier arriving perpendicular), center → top-center
// (straight), right foot → RIGHT edge at ¼ height. Rendered IN the dialog's own window —
// above any dim scrim, which the separate lower-layer ConnectorOverlay can't manage —
// so instantiate it inside the dialog window ABOVE the scrim, and drive `active` from
// the shown state:
//
//     ConnectorFan { box: panel; active: win.visible }
//
// Line-first open: on activation the fan TRAVELS from the bar feet to the box over
// `travelMs`, then flips `landed` — gate the dialog's entrance on it so the energy
// arrives before the content materializes. Lines then spike and decay to `steady`
// like the Popout connector.
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
    property real elbow: 50
    //! line-first open: the fan travels from the bar feet to the box over this many ms.
    //! Dialogs gate their entrance on `landed` so the energy arrives BEFORE the content.
    property int travelMs: 170
    //! progress fraction at which `landed` flips — the entrance overlaps the last leg of
    //! the travel so the content is already rising as the lines strike home
    property real revealAt: 0.75
    //! true once the fan has landed on the box — set instantly when effects are off or
    //! no bar feet are published, so a gated dialog can never be stranded hidden
    property bool landed: false

    visible: Shell.effectsOn

    property var _links: []
    property var _finalLinks: []
    property real _energy: 0
    property bool _live: false
    //! 0..1 travel progress; drives the partial links during the fly-in
    property real _progress: 0

    on_EnergyChanged: {
        if (!_live)
            return;
        root._links = root._links.map(l => Object.assign({}, l, {
            energy: _energy
        }));
    }

    onActiveChanged: {
        if (active) {
            landed = false;
            if (!Shell.effectsOn) {
                landed = true; // no lines to wait for
                return;
            }
            prepTimer.restart();
        } else {
            prepTimer.stop();
            travelAnim.stop();
            landed = false;
            if (_live)
                fade.restart();
        }
    }

    // one short beat so the freshly-mapped window has laid the box out before we
    // measure endpoints (the content itself stays hidden until `landed`)
    Timer {
        id: prepTimer
        interval: 30
        onTriggered: root._beginTravel()
    }

    // point at parameter t of a quadratic bezier p0→(cx,cy)→p2, and the sub-curve up to
    // it (de Casteljau): control = lerp(p0,c,t), end = lerp(lerp(p0,c,t), lerp(c,p2,t), t)
    function _partial(l, t) {
        if (l.cx !== undefined) {
            const qx = l.x1 + (l.cx - l.x1) * t, qy = l.y1 + (l.cy - l.y1) * t;
            const mx = l.cx + (l.x2 - l.cx) * t, my = l.cy + (l.y2 - l.cy) * t;
            return { x1: l.x1, y1: l.y1, cx: qx, cy: qy,
                     x2: qx + (mx - qx) * t, y2: qy + (my - qy) * t, energy: l.energy };
        }
        return { x1: l.x1, y1: l.y1,
                 x2: l.x1 + (l.x2 - l.x1) * t, y2: l.y1 + (l.y2 - l.y1) * t, energy: l.energy };
    }

    on_ProgressChanged: {
        if (!_live || !travelAnim.running)
            return;
        root._links = root._finalLinks.map(l => root._partial(l, _progress));
        if (!landed && _progress >= revealAt)
            landed = true;
    }

    function _beginTravel() {
        if (!root.active || !root.box || !Shell.effectsOn) {
            root.landed = true;
            return;
        }
        const w = QsWindow.window;
        const sn = w && w.screen ? w.screen.name : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "");
        const feet = Connectors.sectionAnchors[sn];
        if (!feet || feet.length < 3) {
            root.landed = true; // no bar feet published (e.g. waybar) — don't strand the dialog
            return;
        }
        // feet are screen coords; if this window sits below the bar's exclusive zone,
        // window coords are shifted up by the difference
        const offY = w && w.screen ? w.screen.height - w.height : 0;
        const f = feet.map(p => root.mapFromItem(null, p.x, p.y - offY));
        // surface corners in local space — measured through the box's PARENT so a hidden
        // entrance scale (cards at 0.92 while gated) doesn't skew the resting geometry
        const tl = root.box.parent.mapToItem(root, root.box.x, root.box.y);
        const tr = root.box.parent.mapToItem(root, root.box.x + root.box.width, root.box.y);
        const drop = root.box.height / 4; // how far down the side edge the lines land
        root._finalLinks = [
            // left foot → left edge at ¼ height. Control point just OUTSIDE the endpoint
            // on its horizontal: the run is a near-straight diagonal that corners in the
            // last `elbow` px to hit the edge at a right angle
            {
                x1: f[0].x, y1: f[0].y - 2,
                x2: tl.x - 2, y2: tl.y + drop,
                cx: tl.x - 2 - root.elbow, cy: tl.y + drop,
                energy: 1.0
            },
            // center → top-center, straight drop
            {
                x1: f[1].x, y1: f[1].y - 2,
                x2: (tl.x + tr.x) / 2, y2: tl.y + 2,
                energy: 1.0
            },
            // right foot → right edge at ¼ height, mirrored
            {
                x1: f[2].x, y1: f[2].y - 2,
                x2: tr.x + 2, y2: tr.y + drop,
                cx: tr.x + 2 + root.elbow, cy: tr.y + drop,
                energy: 1.0
            }
        ];
        root._energy = 1.0;
        root._links = root._finalLinks.map(l => root._partial(l, 0));
        _live = true;
        _progress = 0;
        travelAnim.restart();
    }

    SequentialAnimation {
        id: travelAnim
        NumberAnimation {
            target: root
            property: "_progress"
            from: 0
            to: 1
            duration: root.travelMs
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                root._links = root._finalLinks;
                root.landed = true;
                decay.restart();
            }
        }
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
        // dialog fan lines are the main event — heavier than the popout stub
        thickness: Theme.connectorFanThickness
    }
}
