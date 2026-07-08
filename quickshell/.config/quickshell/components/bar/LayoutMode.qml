import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."
import "../../config"

// Per-workspace window layout for THIS monitor's active desktop. Hyprland's layout is per-workspace
// under the hyprland-lua plugin (`tiledLayout`); switching goes through the plugin's workspace_rule.
// The dispatch hijack wraps strings in hl.dispatch(), which accepts a function — so we pass an anon
// function that calls hl.workspace_rule (a plain dispatcher can't set the layout engine). Read comes
// from `hyprctl workspaces -j` (.tiledLayout), keyed by this monitor's active workspace id.
Item {
    id: root
    property string screenName: ""
    implicitWidth: icon.implicitWidth + 14
    implicitHeight: Theme.barIcon + 6

    readonly property var layouts: ["master", "dwindle", "scrolling"]

    // this monitor's active workspace id (same source as Workspaces.qml)
    readonly property int activeWsId: {
        const ms = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (const m of ms)
            if (m.name === root.screenName && m.activeWorkspace)
                return m.activeWorkspace.id;
        return -1;
    }
    property var layoutByWs: ({})
    readonly property string layout: {
        const l = layoutByWs[root.activeWsId];
        return l ? l : "";
    }
    onActiveWsIdChanged: refresh()

    function glyphFor(name) {
        if (name === "master")
            return "\uf0db";      // columns
        if (name === "dwindle")
            return "\uf009";      // th-large
        if (name === "scrolling")
            return "\uf07e";      // arrows-h
        return "\uf00a";          // th
    }

    Process {
        id: readProc
        command: ["sh", "-c", "hyprctl workspaces -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(this.text);
                    const map = {};
                    for (const w of arr)
                        map[w.id] = w.tiledLayout || "";
                    root.layoutByWs = map;
                } catch (e) {}
            }
        }
    }
    function refresh() {
        readProc.running = false;
        readProc.running = true;
    }
    function setLayout(name) {
        if (root.activeWsId < 0)
            return;
        // hl.dispatch() accepts a function; call workspace_rule inside it (per-workspace layout)
        Hyprland.dispatch('function() hl.workspace_rule({workspace="' + root.activeWsId + '", layout="' + name + '"}) end');
        refreshTimer.restart();
    }
    Timer {
        id: refreshTimer
        interval: 300
        onTriggered: root.refresh()
    }
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Text {
        id: icon
        anchors.centerIn: parent
        text: root.glyphFor(root.layout)
        color: ma.containsMouse ? Theme.accent : Theme.fg
        font.family: Theme.fontUi
        font.pixelSize: Theme.barIcon
        scale: ma.containsMouse ? 1.15 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Theme.animFast
                easing.type: Theme.easing
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: Theme.animFast
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (!pop.shown) {
            tip.text = "Layout: " + (root.layout || "?");
            tip.open();
        }
        onExited: tip.close()
        onClicked: {
            tip.close();
            pop.toggle();
        }
    }

    Tooltip {
        id: tip
        anchorItem: root
    }

    Popout {
        id: pop
        anchorItem: root
        popWidth: 150

        Repeater {
            model: root.layouts
            delegate: Item {
                required property var modelData
                width: parent.width
                height: 24
                readonly property bool current: modelData === root.layout
                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: Theme.accent
                    opacity: rowMa.containsMouse ? 0.25 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.glyphFor(modelData)
                    color: parent.current ? Theme.accent : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 28
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    color: parent.current ? Theme.accent : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: parent.current
                }
                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.setLayout(modelData);
                        pop.close();
                    }
                }
            }
        }
    }
}
