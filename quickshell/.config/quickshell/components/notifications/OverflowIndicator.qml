import QtQuick
import "../../config"

// "+N more" — the tail of a stack that has hit placement.maxVisible. The queued notifications are
// still in the model with their timers unstarted, so this is a promise, not a loss report: each
// one becomes a real card as slots free. Clicking it is the drawer's job (later story); for now it
// is a status line, not a control.
Rectangle {
    id: pill

    required property int overflow

    visible: overflow > 0
    implicitHeight: visible ? label.implicitHeight + Theme.pad : 0
    radius: Theme.radius
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity * 0.8)
    border.width: Theme.borderThin
    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)

    Text {
        id: label
        anchors.centerIn: parent
        text: "+" + pill.overflow + " more"
        color: Theme.subtext
        font.family: Theme.fontUi
        font.pixelSize: Theme.fontSize - 2
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Theme.animFast
            easing.type: Theme.easing
        }
    }
}
