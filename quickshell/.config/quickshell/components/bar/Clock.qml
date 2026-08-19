import QtQuick
import "../../config"

// Local clock. Clicking it opens the clock drawer (components/ClockDrawer.qml) — weather,
// world clocks and the calendar.
//
// The world-clock list and the month calendar used to be two hover/click Popouts hanging off
// this Text. They moved: a popout is the wrong home for anything with more than a few lines in
// it, and there was nowhere to put weather at all. The `TZ=… date` mechanism went with them
// unchanged (quickshell's JS engine has no Intl timezone support) and now lives in the Clocks
// singleton — see config/Clocks.qml.
Text {
    id: root
    property string format: "HH:mm · ddd dd/MM"

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

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Clocks.toggle()
    }
}
