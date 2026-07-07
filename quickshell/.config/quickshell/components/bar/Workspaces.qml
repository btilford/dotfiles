import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../config"

// Per-monitor workspaces. Same visual language as WindowList: a bright accent indicator that
// SLIDES + PULSES to this monitor's active workspace. Inactive labels use bright fg for contrast.
// The focused (cursor) monitor's indicator is full-bright; other monitors' are slightly dimmed.
//
// hyprland-lua hijacks `dispatch`, so switching uses hl.dsp.focus({workspace="N"}).
Item {
    id: root
    property string screenName: ""
    property int gap: 4
    implicitHeight: 20
    implicitWidth: rowLay.implicitWidth

    function goWorkspace(id) {
        Hyprland.dispatch('hl.dsp.focus({workspace="' + id + '"})');
    }

    function computeWs() {
        const out = [];
        const all = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        for (const w of all)
            if (w && w.monitor && w.monitor.name === root.screenName)
                out.push({ id: w.id, name: w.name });
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    property var wsModel: []
    Item {
        visible: false
        readonly property string key: root.computeWs().map(x => x.id).join(",")
        onKeyChanged: root.wsModel = root.computeWs()
        Component.onCompleted: root.wsModel = root.computeWs()
    }

    readonly property int monActiveId: {
        const all = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (const m of all)
            if (m.name === root.screenName && m.activeWorkspace)
                return m.activeWorkspace.id;
        return -1;
    }
    readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    readonly property bool monFocused: monActiveId === focusedId

    readonly property int activeIndex: {
        for (let i = 0; i < wsModel.length; i++)
            if (wsModel[i].id === root.monActiveId)
                return i;
        return -1;
    }
    onActiveIndexChanged: if (activeIndex >= 0)
        pulse.restart()

    // indicator geometry reported by the active pill (handles variable widths)
    property real indX: 0
    property real indW: 0
    function reportActive(x, w) {
        indX = x;
        indW = w;
    }

    Rectangle {
        id: ind
        visible: root.activeIndex >= 0
        x: root.indX
        width: root.indW
        height: parent.height
        radius: 6
        color: Theme.accent
        opacity: visible ? (root.monFocused ? 1 : 0.7) : 0
        Behavior on x {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Easing.OutBack
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Easing.OutBack
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }
    }
    SequentialAnimation {
        id: pulse
        NumberAnimation {
            target: ind
            property: "scale"
            from: 1.0
            to: 1.18
            duration: 90
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: ind
            property: "scale"
            to: 1.0
            duration: 190
            easing.type: Easing.OutBack
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const ids = root.wsModel.map(w => w.id);
            const cur = ids.indexOf(root.monActiveId);
            if (cur < 0 || ids.length === 0)
                return;
            const next = event.angleDelta.y > 0 ? Math.max(0, cur - 1) : Math.min(ids.length - 1, cur + 1);
            root.goWorkspace(ids[next]);
        }
    }

    Row {
        id: rowLay
        spacing: root.gap
        Repeater {
            model: root.wsModel
            delegate: Item {
                id: pill
                required property var modelData
                readonly property bool active: modelData.id === root.monActiveId
                width: Math.max(22, label.implicitWidth + 14)
                height: root.height

                onActiveChanged: if (active)
                    root.reportActive(x, width)
                onXChanged: if (active)
                    root.reportActive(x, width)
                onWidthChanged: if (active)
                    root.reportActive(x, width)
                Component.onCompleted: if (active)
                    root.reportActive(x, width)

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: (modelData.name && isNaN(modelData.name)) ? modelData.name : modelData.id
                    color: pill.active ? Theme.bg : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 2
                    font.bold: pill.active
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goWorkspace(pill.modelData.id)
                }
            }
        }
    }
}
