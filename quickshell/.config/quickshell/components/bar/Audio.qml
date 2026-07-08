import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import ".."

// Default-sink volume. Icon reflects level/mute; scroll = volume, click = slide-out popup with a
// draggable slider, mute toggle, and the sink name. PwObjectTracker keeps the sink subscribed so
// volume/muted stay reactive.
Item {
    id: root
    implicitWidth: icon.implicitWidth + 14
    implicitHeight: Theme.barIcon + 6

    // right-click launches the audio management app (disowned)
    property string manageCmd: "pavucontrol"

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var au: sink && sink.audio ? sink.audio : null
    readonly property real vol: au ? au.volume : 0
    readonly property bool muted: au ? au.muted : false

    // subscribe to the default sink so its audio props update live
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    function setVol(v) {
        if (root.au)
            root.au.volume = Math.max(0, Math.min(1, v));
    }
    function toggleMute() {
        if (root.au)
            root.au.muted = !root.au.muted;
    }

    Text {
        id: icon
        anchors.centerIn: parent
        text: root.muted ? "\uf026" : (root.vol < 0.01 ? "\uf026" : (root.vol < 0.5 ? "\uf027" : "\uf028"))
        color: root.muted ? Theme.subtext : Theme.fg
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
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onEntered: if (!pop.shown) {
            tip.text = root.muted ? "Muted" : "Volume " + Math.round(root.vol * 100) + "%";
            tip.open();
        }
        onExited: tip.close()
        onClicked: mouse => {
            tip.close();
            if (mouse.button === Qt.MiddleButton)
                root.toggleMute();
            else if (mouse.button === Qt.RightButton)
                Quickshell.execDetached(["sh", "-lc", root.manageCmd]);
            else
                pop.toggle();
        }
        onWheel: wheel => root.setVol(root.vol + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
    }

    Tooltip {
        id: tip
        anchorItem: root
    }

    Popout {
        id: pop
        anchorItem: root
        popWidth: 92

        // sink name
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.sink ? (root.sink.description || root.sink.nickname || root.sink.name) : "No sink"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 3
            elide: Text.ElideRight
        }

        // percent readout
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.muted ? "muted" : Math.round(root.vol * 100) + "%"
            color: root.muted ? Theme.subtext : Theme.fg
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize
        }

        // vertical slider (fill grows from the bottom; drag anywhere on the track)
        Item {
            width: parent.width
            height: 130
            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 8
                height: parent.height
                radius: 4
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.15)

                Rectangle {
                    id: fill
                    anchors.bottom: parent.bottom
                    width: parent.width
                    radius: parent.radius
                    height: parent.height * root.vol
                    color: root.muted ? Theme.subtext : Theme.accent
                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }
                }
                Rectangle {
                    id: handle
                    width: 18
                    height: 18
                    radius: 9
                    color: root.muted ? Theme.subtext : Theme.accent
                    border.color: Theme.bg
                    border.width: 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (parent.height - height) * (1 - root.vol)
                    Behavior on y {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onPressed: mouse => root.setVol(1 - (mouse.y + anchors.margins) / track.height)
                    onPositionChanged: mouse => root.setVol(1 - (mouse.y + anchors.margins) / track.height)
                    onWheel: wheel => root.setVol(root.vol + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                }
            }
        }

        // mute toggle
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.muted ? "\uf026" : "\uf028"
            color: Theme.accent
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize + 2
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMute()
            }
        }
    }
}
