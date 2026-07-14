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

    function vpnLine() {
        if (Vpn.connected)
            return Vpn.backend === "mullvad"
                ? "VPN: " + Vpn.relay + (Vpn.location ? " · " + Vpn.location : "")
                : "VPN: " + Vpn.relay + " (generic)";
        if (Vpn.busy)
            return "VPN: " + Vpn.status + "…";
        if (Vpn.lockedDown)
            return "VPN: blocked (lockdown)";
        return "";
    }

    function summary() {
        const vpn = vpnLine();
        const tail = vpn.length ? " · " + vpn : "";
        if (!dev)
            return "Disconnected" + tail;
        if (root.wired)
            return "Wired" + (root.online ? "" : " · limited") + (dev.address ? " · " + dev.address : "") + tail;
        const ssid = root.wifiNet ? root.wifiNet.name : dev.name;
        const sig = root.wifiNet ? " · " + root.wifiNet.signalStrength + "%" : "";
        return (ssid || "Wi-Fi") + sig + (root.online ? "" : " · limited") + tail;
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

        // VPN badge: lock glyph pinned to the icon's foot. Overlay only — the module's
        // implicitWidth is untouched. Accent = connected, urgent = connecting/error or
        // lockdown-blocked; hidden when plainly disconnected.
        Text {
            visible: Vpn.status !== "disconnected" || Vpn.lockedDown
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -4
            anchors.bottomMargin: -3
            text: "" // fa-lock
            color: Vpn.connected ? Theme.accent : Theme.urgent
            font.family: Theme.fontUi
            font.pixelSize: 9
            style: Text.Outline
            styleColor: Theme.bg
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

        // VPN: status line + connect/disconnect (button is mullvad-only; the generic
        // backend is observe-only — nothing safe to toggle for an arbitrary wg/tun iface)
        Column {
            width: parent.width
            spacing: 6
            visible: Vpn.backend !== "none"

            Text {
                width: parent.width
                text: {
                    if (Vpn.connected)
                        return " " + (Vpn.relay || "VPN") + (Vpn.location ? " · " + Vpn.location : "") + (Vpn.backend === "generic" ? " (generic)" : "");
                    if (Vpn.busy)
                        return " VPN " + Vpn.status + "…";
                    if (Vpn.lockedDown)
                        return " VPN off · lockdown (network blocked)";
                    return " VPN off";
                }
                color: Vpn.connected ? Theme.accent : (Vpn.lockedDown ? Theme.urgent : Theme.subtext)
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize - 2
                elide: Text.ElideRight
            }

            Rectangle {
                visible: Vpn.mullvadAvailable
                width: parent.width
                height: 26
                radius: 4
                color: vpnBtnMa.containsMouse && !Vpn.busy
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                    : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
                border.width: Theme.borderThin
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Vpn.busy ? 0.25 : 0.6)
                opacity: Vpn.busy ? 0.6 : 1

                Text {
                    anchors.centerIn: parent
                    text: Vpn.busy ? "…" : (Vpn.connected ? "Disconnect VPN" : "Connect VPN")
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 2
                }
                MouseArea {
                    id: vpnBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !Vpn.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Vpn.connected ? Vpn.disconnectVpn() : Vpn.connectVpn()
                }
            }
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
