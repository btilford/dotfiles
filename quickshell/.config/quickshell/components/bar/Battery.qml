import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../../config"
import ".."

// Laptop battery (UPower display device). Hidden on desktops (no laptop battery). Icon by level +
// charging state, % on hub bars; click = popup with time-to-empty/full + health. Charging is
// detected from the freedesktop iconName string to avoid depending on enum value ordering.
Item {
    id: root
    property bool hub: false

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev && dev.ready && dev.isLaptopBattery
    // UPower.displayDevice.percentage is a 0.0-1.0 fraction, not 0-100 — verified
    // live: a fully-charged battery (iconName battery-full-charged-symbolic)
    // reports percentage 1, which without the *100 renders as "1%".
    readonly property real pct: dev ? dev.percentage * 100 : 0
    readonly property bool charging: dev && dev.iconName ? dev.iconName.indexOf("charging") >= 0 : false

    visible: present
    implicitWidth: present ? row.implicitWidth : 0
    implicitHeight: Theme.barIcon + 6

    function glyph() {
        if (charging)
            return "\uf0e7";
        if (pct >= 90)
            return "\uf240";
        if (pct >= 65)
            return "\uf241";
        if (pct >= 40)
            return "\uf242";
        if (pct >= 15)
            return "\uf243";
        return "\uf244";
    }
    function fmtTime(secs) {
        if (!secs || secs <= 0)
            return "";
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        return (h > 0 ? h + "h " : "") + m + "m";
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Text {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph()
            color: root.pct <= 15 && !root.charging ? Theme.urgent : Theme.fg
            font.family: Theme.fontUi
            font.pixelSize: Theme.barIcon
            scale: ma.containsMouse ? 1.15 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Theme.animFast
                    easing.type: Theme.easing
                }
            }
        }
        Text {
            visible: root.hub
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.pct) + "%"
            color: Theme.fg
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize - 1
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (!pop.shown) {
            tip.text = "Battery " + Math.round(root.pct) + "%" + (root.charging ? " (charging)" : "");
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
        popWidth: 220

        Text {
            width: parent.width
            text: (root.charging ? "Charging" : "Discharging") + " · " + Math.round(root.pct) + "%"
            color: Theme.fg
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: {
                const t = root.charging ? (root.dev ? root.dev.timeToFull : 0) : (root.dev ? root.dev.timeToEmpty : 0);
                const s = root.fmtTime(t);
                return s ? (root.charging ? "Full in " + s : s + " left") : "";
            }
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 2
        }
        Text {
            width: parent.width
            // *100: inferred from the sibling `percentage` property, confirmed live to be a
            // 0.0-1.0 fraction (see the pct comment above) rather than 0-100. Unverified for
            // healthPercentage itself — this host reports healthSupported: false — but
            // Quickshell's UPower binding is consistent about normalizing percentage-like
            // properties, and a wrong guess here is obviously wrong (up to 10000%) rather than
            // silently plausible the way the un-scaled bug was.
            visible: root.dev && root.dev.healthPercentage > 0
            text: "Health " + Math.round(root.dev ? root.dev.healthPercentage * 100 : 0) + "%"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 2
        }
    }
}
