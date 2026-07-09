import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."
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

    // workspace name → nerd-font glyph (falls back to the name/id when unmapped)
    function iconFor(name) {
        const m = {
            "Main": "\uf015",       // home
            "CLI1": "\uf120",       // terminal
            "CLI2": "\uf120",       // terminal
            "Draw": "\uf1fc",       // paint-brush
            "RefLeft": "\uf02d",    // book
            "RefRight": "\uf02d",   // book
            "Music": "\uf001",      // music
            "Messaging": "\uf086",  // comments
            "Other": "\uf141"       // ellipsis
        };
        return name && m[name] ? m[name] : "";
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

    // shared hover-title tooltip
    property Item hoverPill: null
    property string hoverText: ""
    Tooltip {
        id: tip
        anchorItem: root.hoverPill
        text: root.hoverText
    }

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
        color: "transparent"
        opacity: visible ? (root.monFocused ? 1 : 0.7) : 0

        // animated plasma fill in the accent color (replaces the flat orange highlight)
        EnergyFill {
            anchors.fill: parent
            radius: parent.radius
        }
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

                // hover tint (behind the label; suppressed on the active pill, which has the indicator)
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Theme.accent
                    opacity: pillMa.containsMouse && !pill.active ? 0.4 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }
                }

                Text {
                    id: label
                    anchors.centerIn: parent
                    // icon where mapped, else the name (or id for numeric-only workspaces)
                    text: {
                        const ic = root.iconFor(modelData.name);
                        return ic ? ic : ((modelData.name && isNaN(modelData.name)) ? modelData.name : modelData.id);
                    }
                    color: pill.active ? Theme.bg : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 2
                    font.bold: pill.active
                    scale: pillMa.containsMouse ? 1.22 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.animFast
                            easing.type: Theme.easing
                        }
                    }
                }

                MouseArea {
                    id: pillMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        root.hoverPill = pill;
                        const nm = pill.modelData.name;
                        const hasName = nm && isNaN(nm);
                        root.hoverText = pill.modelData.id + (hasName ? " · " + nm : "");
                        tip.open();
                    }
                    onExited: if (root.hoverPill === pill)
                        tip.close()
                    onClicked: root.goWorkspace(pill.modelData.id)
                }
            }
        }
    }
}
