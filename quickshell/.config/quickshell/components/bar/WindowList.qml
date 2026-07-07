import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../config"

// Task list: windows on THIS monitor's active workspace. The focused window (Hyprland.activeToplevel,
// reactive) gets a bright accent indicator that SLIDES + PULSES to it. Click to focus. Model only
// swaps when the window set changes, so the indicator animates rather than delegates rebuilding.
Item {
    id: root
    property string screenName: ""
    property int cellW: Theme.barIcon + 10
    property int gap: 4

    implicitHeight: Theme.barIcon + 6
    implicitWidth: winModel.length > 0 ? winModel.length * cellW + (winModel.length - 1) * gap : 0
    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.animFast
            easing.type: Theme.easing
        }
    }

    readonly property int activeWsId: {
        const ms = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (const m of ms)
            if (m.name === root.screenName && m.activeWorkspace)
                return m.activeWorkspace.id;
        return -1;
    }

    function computeWins() {
        const out = [];
        const tls = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (const w of tls) {
            const o = w.lastIpcObject;
            if (!o || !o.workspace || o.workspace.id !== root.activeWsId)
                continue;
            out.push({ address: o.address, cls: o.class || "" });
        }
        out.sort((a, b) => a.address < b.address ? -1 : 1);
        return out;
    }

    property var winModel: []
    // Hyprland.toplevels.values doesn't reliably notify on window open/close/move, so poll the
    // window-set key; only swap the model when the set actually changes (keeps the animation).
    Timer {
        interval: 250
        running: true
        repeat: true
        triggeredOnStart: true
        property string key: ""
        onTriggered: {
            const k = root.computeWins().map(w => w.address).join(",");
            if (k !== key) {
                key = k;
                root.winModel = root.computeWins();
            }
        }
    }

    // focused window (reactive) → indicator target
    readonly property string activeAddr: {
        const a = Hyprland.activeToplevel;
        return (a && a.lastIpcObject) ? a.lastIpcObject.address : "";
    }
    readonly property int activeIndex: {
        for (let i = 0; i < winModel.length; i++)
            if (winModel[i].address === root.activeAddr)
                return i;
        return -1;
    }
    onActiveIndexChanged: if (activeIndex >= 0)
        pulse.restart()

    // bright sliding indicator (behind the icons)
    Rectangle {
        id: ind
        visible: root.activeIndex >= 0
        width: root.cellW
        height: root.height
        radius: 5
        color: Theme.accent
        x: root.activeIndex >= 0 ? root.activeIndex * (root.cellW + root.gap) : 0
        opacity: visible ? 1 : 0
        Behavior on x {
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

    Row {
        spacing: root.gap
        Repeater {
            model: root.winModel
            delegate: Item {
                id: cell
                required property var modelData
                width: root.cellW
                height: root.height
                readonly property bool active: modelData.address === root.activeAddr
                readonly property string appClass: modelData.cls || ""
                readonly property var entry: {
                    DesktopEntries.applications.values.length; // reactive tap
                    return appClass ? DesktopEntries.heuristicLookup(appClass) : null;
                }
                readonly property string iconName: entry && entry.icon ? entry.icon : ""

                Image {
                    id: icon
                    anchors.centerIn: parent
                    visible: source != "" && cell.appClass !== ""
                    source: cell.iconName ? Quickshell.iconPath(cell.iconName, true) : ""
                    sourceSize.width: Theme.barIcon
                    sourceSize.height: Theme.barIcon
                    width: Theme.barIcon
                    height: Theme.barIcon
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    opacity: cell.active ? 1 : 0.6
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animMed
                            easing.type: Theme.easing
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !icon.visible && cell.appClass !== ""
                    text: ""
                    color: cell.active ? Theme.bg : Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.barIcon
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch('hl.dsp.focus({window="address:' + cell.modelData.address + '"})')
                }
            }
        }
    }
}
