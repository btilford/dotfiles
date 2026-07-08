import QtQuick
import Quickshell
import Quickshell.Networking
import ".."
import "../../config"

// Network status. Icon = wired / wifi / offline; hover = connection summary; click = popout with
// details and (for wifi) the visible network list. Always visible, including on minimal bars.
Item {
    id: root
    implicitWidth: icon.implicitWidth + 14
    implicitHeight: Theme.barIcon + 6

    // right-click launches the network management app (disowned)
    property string manageCmd: "nm-connection-editor"

    readonly property var devs: Networking.devices ? Networking.devices.values : []
    // prefer a connected wired link, else a connected wifi device
    readonly property var dev: {
        let wired = null, wifi = null;
        for (const d of root.devs) {
            if (d.type === DeviceType.Wired && d.connected)
                wired = d;
            else if (d.type === DeviceType.Wifi && d.connected)
                wifi = d;
        }
        return wired || wifi || null;
    }
    readonly property int conn: Networking.connectivity
    readonly property bool online: conn === NetworkConnectivity.Full
    readonly property bool wired: dev && dev.type === DeviceType.Wired
    readonly property var wifiNet: {
        if (!dev || dev.type !== DeviceType.Wifi)
            return null;
        const ns = dev.networks ? dev.networks.values : [];
        for (const n of ns)
            if (n.connected)
                return n;
        return null;
    }

    function summary() {
        if (!dev)
            return "Disconnected";
        if (root.wired)
            return "Wired" + (root.online ? "" : " · limited") + (dev.address ? " · " + dev.address : "");
        const ssid = root.wifiNet ? root.wifiNet.name : dev.name;
        const sig = root.wifiNet ? " · " + root.wifiNet.signalStrength + "%" : "";
        return (ssid || "Wi-Fi") + sig + (root.online ? "" : " · limited");
    }

    Text {
        id: icon
        anchors.centerIn: parent
        // wired=sitemap, wifi=wifi, offline=ban
        text: !root.dev ? "\uf05e" : (root.wired ? "\uf0e8" : "\uf1eb")
        color: !root.dev ? Theme.subtext : (root.online ? Theme.fg : Theme.urgent)
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
        onEntered: if (!pop.shown) {
            tip.text = root.summary();
            tip.open();
        }
        onExited: tip.close()
        onClicked: mouse => {
            tip.close();
            if (mouse.button === Qt.RightButton)
                Quickshell.execDetached(["sh", "-lc", root.manageCmd]);
            else
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
        popWidth: 240

        Text {
            width: parent.width
            text: root.dev ? (root.wired ? "Wired connection" : "Wi-Fi") : "Not connected"
            color: Theme.fg
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize
        }
        Text {
            width: parent.width
            visible: root.dev !== null
            text: root.summary()
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 2
            elide: Text.ElideRight
        }

        // wifi network list (read-only for now)
        Repeater {
            model: (root.dev && root.dev.type === DeviceType.Wifi && root.dev.networks) ? root.dev.networks.values : []
            delegate: Item {
                required property var modelData
                width: parent.width
                height: 20
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44
                    text: (modelData.connected ? "● " : "") + (modelData.name || "(hidden)")
                    color: modelData.connected ? Theme.accent : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.signalStrength + "%"
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
}
