import QtQuick
import ".."
import "../../config"

// Live stopwatch readout (story: notif-timers, decision 2).
//
// The stopwatch counts UP: it has no wake_at, so it gets nothing from the store's armed timer,
// and a notification card only re-renders on replaces_id — repainting one once a second to show a
// clock is an abuse of the popup stack. So the elapsed time lives here, in the bar, and the
// notification surface sees the stopwatch only at terminal events (started, lap, stopped).
//
// This is a bar MODULE, unlike NotificationPills: it sits inside a Section and carries no surface
// of its own, because it is not a notification that shrank — it is a readout.
//
// Click: pause/resume.  Middle-click: lap.  Right-click: stop (which writes the summary row).
Item {
    id: root

    readonly property var sw: Timers.stopwatch
    readonly property bool live: Timers.cfg.stopwatchPill && root.sw.id > 0

    visible: root.live
    implicitWidth: root.live ? content.implicitWidth : 0
    implicitHeight: Theme.barIcon + 6

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.animFast
            easing.type: Theme.easing
        }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf252" // fa-hourglass-half
            color: root.sw.running ? Theme.accent : Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 1

            // a slow pulse while it is running, so a stopwatch left going overnight is visible
            // from the corner of the eye rather than only when you read the digits
            SequentialAnimation on opacity {
                running: root.sw.running
                loops: Animation.Infinite
                NumberAnimation {
                    from: 1
                    to: 0.5
                    duration: 900
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 0.5
                    to: 1
                    duration: 900
                    easing.type: Easing.InOutSine
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Timers.now is what makes this tick; the singleton owns the elapsed state and this
            // only formats it
            text: Timers.fmt(Timers.stopwatchElapsed)
            color: root.sw.running ? Theme.fg : Theme.subtext
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize
            font.bold: root.sw.running
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.sw.laps.length > 0
            text: "· " + root.sw.laps.length
            color: Theme.subtext
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize - 3
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onEntered: {
            // one line: Tooltip elides to a single row, so laps are counted here and listed on
            // the cards the laps themselves raised
            tip.text = (root.sw.label.length ? root.sw.label + " — " : "") + "click pause/resume · middle lap · right stop";
            tip.anchorItem = root;
            tip.open();
        }
        onExited: tip.close()
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                Timers.stopwatchLap();
                return;
            }
            if (mouse.button === Qt.RightButton) {
                tip.close();
                Timers.stopwatchStop();
                return;
            }
            Timers.stopwatchToggle("");
        }
    }

    Tooltip {
        id: tip
        anchorItem: root
    }
}
