import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../config"

// Fans three energy connector lines from the bar's section feet (published by Bar.qml
// into Connectors.sectionAnchors) down to a dialog surface: left foot → surface top-left,
// center → top-center, right foot → top-right. Instantiate INSIDE the dialog's window and
// drive `active` from its shown state:
//
//     ConnectorFan { box: panel; active: win.visible }
//
// Registration waits out the dialog's entrance animation so endpoints land on settled
// geometry; the lines then spike and decay to `steady` like the Popout connector.
Item {
    id: root

    //! the dialog surface the fan feeds
    property Item box
    //! drive from the dialog's shown/visible state
    property bool active: false
    //! settle level after the open spike
    property real steady: 0.55

    readonly property string _fanId: "fan-" + root.toString()
    property real _energy: 0
    property bool _live: false

    on_EnergyChanged: {
        if (!_live)
            return;
        for (let i = 0; i < 3; i++)
            Connectors.update(_fanId + "-" + i, {
                energy: _energy
            });
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

    function _screenName() {
        const w = QsWindow.window;
        if (w && w.screen)
            return w.screen.name;
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    }

    function _register() {
        if (!root.active || !root.box || !Shell.effectsOn)
            return;
        const sn = _screenName();
        const feet = Connectors.sectionAnchors[sn];
        if (!feet || feet.length < 3)
            return;
        // dialog windows are fullscreen → window coords == screen coords
        const tl = root.box.mapToItem(null, 0, 0);
        const tr = root.box.mapToItem(null, root.box.width, 0);
        const targets = [
            { x: tl.x + Theme.radius * 2, y: tl.y },
            { x: (tl.x + tr.x) / 2, y: (tl.y + tr.y) / 2 },
            { x: tr.x - Theme.radius * 2, y: tr.y }
        ];
        for (let i = 0; i < 3; i++)
            Connectors.register({
                id: _fanId + "-" + i,
                screenName: sn,
                x1: feet[i].x,
                y1: feet[i].y - 2,       // tuck into the bar foot
                x2: targets[i].x,
                y2: targets[i].y + 2,    // melt into the surface edge
                energy: 1.0
            });
        _live = true;
        decay.restart();
    }

    function _unregister() {
        if (!_live)
            return;
        _live = false;
        decay.stop();
        for (let i = 0; i < 3; i++)
            Connectors.unregister(_fanId + "-" + i);
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

    Component.onDestruction: _unregister()
}
