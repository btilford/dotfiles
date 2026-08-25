import QtQuick
import "../../config"

// The action chip row, shared by the popup card and the centred compose surface.
//
// Extracted so there is ONE renderer for a verb: the card and the compose surface show the same
// chips with the same `^<letter>` hints, and a change to how an action looks cannot land on one
// surface and miss the other. It is a pure view — the caller supplies the list and decides what
// invoking one means (fire it, or open a prompt for it).
//
// Flow, not Row, and bounded to the given width: several verbs with long labels ran straight past
// a 420px card instead of wrapping.
Flow {
    id: chips

    // [{ kind, label, key, spec, run, prompt, capture, perform? }] — Notifications.actionsFor /
    // actionsForRow. `perform` is only present on built-in verbs (kind "timer"/"snooze") —
    // invokeAction calls it in process instead of running `run` as a subprocess.
    required property var list
    // the one whose prompt is currently open, so it reads as engaged rather than just hovered
    property var activeAction: null

    signal triggered(var action)

    visible: chips.list.length > 0
    spacing: 6
    padding: 0

    Repeater {
        model: chips.list

        delegate: Rectangle {
            id: chip
            required property var modelData

            readonly property bool engaged: chips.activeAction === chip.modelData

            height: chipRow.implicitHeight + 6
            width: chipRow.implicitWidth + 14
            radius: Theme.radius / 2
            color: chip.engaged || chipMa.containsMouse
                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, chip.engaged ? 0.3 : 0.18)
                : Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.12)

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: chip.modelData.key.length > 0
                    // ^r, the terminal spelling of Ctrl+R — this shell is terminal-flavoured and
                    // it is two glyphs instead of six
                    text: "^" + chip.modelData.key
                    color: Theme.accent
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 3
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData.label
                    color: chip.engaged || chipMa.containsMouse ? Theme.accent : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            MouseArea {
                id: chipMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chips.triggered(chip.modelData)
            }
        }
    }
}
