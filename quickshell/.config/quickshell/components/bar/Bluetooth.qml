import QtQuick
import Quickshell
import Quickshell.Bluetooth
import ".."
import "../../config"

// Bluetooth status. Icon reflects adapter power + whether anything is connected; hover = summary;
// click = popout listing paired/known devices with connection state + battery. Always visible.
Item {
    id: root
    implicitWidth: icon.implicitWidth + 14
    implicitHeight: Theme.barIcon + 6

    // right-click launches the bluetooth management app (disowned)
    property string manageCmd: "blueman-manager"

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter && adapter.enabled
    readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var connectedDevices: root.devices.filter(d => d.connected)

    function summary() {
        if (!root.adapter)
            return "No Bluetooth adapter";
        if (!root.powered)
            return "Bluetooth off";
        if (root.connectedDevices.length === 0)
            return "Bluetooth on";
        return root.connectedDevices.map(d => d.deviceName || d.name).join(", ");
    }

    Text {
        id: icon
        anchors.centerIn: parent
        text: "\uf293" // fa-bluetooth
        color: !root.powered ? Theme.subtext : (root.connectedDevices.length > 0 ? Theme.accent : Theme.fg)
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: if (!pop.shown)
            htip.open()
        onExited: htip.close()
        onClicked: mouse => {
            htip.close();
            if (mouse.button === Qt.RightButton)
                Quickshell.execDetached(["sh", "-lc", root.manageCmd]);
            else
                pop.toggle();
        }
    }

    // rich hover popout: every saved device, connection state, and per-device battery.
    // (qs exposes one battery per BluetoothDevice; a device with multiple cells reports its
    // aggregate here — bluez/qs 0.3.0 has no per-cell breakdown.)
    Popout {
        id: htip
        anchorItem: root
        dismissable: false
        popWidth: 250

        Text {
            width: parent.width
            text: "Bluetooth " + (root.powered ? "on" : "off") + (root.adapter && root.adapter.discovering ? " · scanning" : "")
            color: Theme.fg
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize
        }
        Text {
            width: parent.width
            visible: root.devices.length === 0
            text: root.adapter ? "No saved devices" : "No adapter"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 2
        }
        Repeater {
            model: root.devices
            delegate: Item {
                required property var modelData
                width: parent.width
                height: 20
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 96
                    text: (modelData.connected ? "● " : "○ ") + (modelData.deviceName || modelData.name || modelData.address)
                    color: modelData.connected ? Theme.accent : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const bat = modelData.batteryAvailable ? (Math.round(modelData.battery > 1 ? modelData.battery : modelData.battery * 100) + "%") : "";
                        const st = modelData.connected ? "connected" : (modelData.paired ? "paired" : "");
                        return bat && st ? (st + " · " + bat) : (bat || st);
                    }
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }

    Popout {
        id: pop
        anchorItem: root
        popWidth: 240

        // header + power toggle
        Item {
            width: parent.width
            height: 20
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Bluetooth"
                color: Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.powered ? "on" : "off"
                color: root.powered ? Theme.accent : Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize - 1
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.adapter !== null
                    onClicked: if (root.adapter)
                        root.adapter.enabled = !root.adapter.enabled
                }
            }
        }

        // device list
        Repeater {
            model: root.devices
            delegate: Item {
                required property var modelData
                width: parent.width
                height: 20
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
                    text: (modelData.connected ? "● " : "") + (modelData.deviceName || modelData.name || modelData.address)
                    color: modelData.connected ? Theme.accent : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.batteryAvailable
                    text: Math.round(modelData.battery > 1 ? modelData.battery : modelData.battery * 100) + "%"
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
}
