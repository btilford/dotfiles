import QtQuick
import Quickshell
import ".."
import "../../config"

// Left-bar session button. Always present so the left widget is never empty on monitors with no
// open windows. Click opens the SessionOverlay (same dialog as SUPER+Escape).
Item {
    id: root
    implicitWidth: icon.implicitWidth + 14
    implicitHeight: Theme.barIcon + 6

    Text {
        id: icon
        anchors.centerIn: parent
        text: "\uf011" // fa-power-off
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
        onEntered: {
            tip.text = "Session";
            tip.open();
        }
        onExited: tip.close()
        onClicked: {
            tip.close();
            Session.toggle();
        }
    }

    Tooltip {
        id: tip
        anchorItem: root
    }
}
