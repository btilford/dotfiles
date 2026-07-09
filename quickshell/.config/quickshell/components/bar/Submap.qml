import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."
import "../../config"

// Active Hyprland submap indicator. Hidden when in the default map; shows a pulsing accent badge
// with the submap name while a submap is active. Submap changes arrive via Hyprland.rawEvent
// ("submap>>NAME"; empty NAME = back to default). Click opens the keymap overlay for this submap.
Item {
    id: root
    property string submap: ""
    readonly property bool active: submap.length > 0

    visible: active
    implicitWidth: active ? badge.implicitWidth : 0
    implicitHeight: Theme.barIcon + 6
    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.animFast
            easing.type: Theme.easing
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                root.submap = event.data;
        }
    }

    Rectangle {
        id: badge
        anchors.centerIn: parent
        implicitWidth: brow.implicitWidth + 14
        width: implicitWidth
        height: Theme.barIcon + 2
        radius: height / 2
        color: "transparent"

        // animated lava fill (replaces the flat accent badge)
        EnergyFill {
            anchors.fill: parent
            radius: parent.radius
        }

        // gentle pulse while a submap is active
        SequentialAnimation on opacity {
            running: root.active
            loops: Animation.Infinite
            NumberAnimation {
                from: 1
                to: 0.6
                duration: 700
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                from: 0.6
                to: 1
                duration: 700
                easing.type: Easing.InOutSine
            }
        }

        Row {
            id: brow
            anchors.centerIn: parent
            spacing: 5
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf11c" // fa-keyboard
                color: Theme.fg  // translucent lava fill behind → light text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.submap
                color: Theme.fg  // translucent lava fill behind → light text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Keymap.toggle()
    }
}
