import QtQuick
import "../../config"

// Compact clock. Calendar popout comes in a later phase.
Text {
    id: root
    property string format: "HH:mm  ·  ddd dd/MM"
    text: Qt.formatDateTime(clock.now, format)
    color: Theme.fg
    font.family: Theme.fontMono
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter

    QtObject {
        id: clock
        property var now: new Date()
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clock.now = new Date()
    }
}
