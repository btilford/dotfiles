import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../../config"

// One notification popup. Pure view over a Notifications entry — it reads the entry and calls
// back into the Notifications singleton, it never holds notification state of its own (the
// store story needs the model to outlive the card, and the timing story owns every timer).
Rectangle {
    id: card

    required property var entry

    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property bool low: entry.urgency === NotificationUrgency.Low
    // per-urgency accent: low recedes into the subtext grey, critical takes the urgent tone
    readonly property color urgencyColor: card.critical ? Theme.urgent : (card.low ? Theme.subtext : Theme.accent)

    // resolved icon: the notification image (image-data / image-path hints, materialized by
    // quickshell) wins over app_icon, which may be a themed icon name or a plain path
    readonly property string iconSource: {
        if (entry.image)
            return entry.image;
        if (!entry.appIcon)
            return "";
        if (entry.appIcon.startsWith("/") || entry.appIcon.startsWith("file://"))
            return entry.appIcon;
        return Quickshell.iconPath(entry.appIcon, true);
    }

    implicitHeight: layout.implicitHeight + Theme.pad * 2
    radius: Theme.radius
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity)
    border.width: Theme.borderThin
    border.color: Qt.rgba(card.urgencyColor.r, card.urgencyColor.g, card.urgencyColor.b, card.critical ? 0.9 : 0.45)

    // urgency stripe down the leading edge — the one always-on colour cue
    Rectangle {
        id: stripe
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Theme.borderThin
        width: 3
        radius: width / 2
        color: card.urgencyColor
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // a resident notification is explicitly asking to survive interaction, so clicking the
        // body doesn't close it (default-action handling belongs to the actions story)
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton || !card.entry.resident)
                Notifications.dismiss(card.entry);
        }
    }

    Column {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.pad
        anchors.leftMargin: Theme.pad + stripe.width
        spacing: 6

        // header: icon + app name + time + close
        Item {
            width: parent.width
            height: Math.max(icon.height, header.implicitHeight, closeBtn.height)

            Image {
                id: icon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: card.iconSource !== ""
                source: card.iconSource
                sourceSize.width: Theme.barIcon
                sourceSize.height: Theme.barIcon
                width: visible ? Theme.barIcon : 0
                height: Theme.barIcon
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Text {
                id: header
                anchors.left: icon.right
                anchors.leftMargin: icon.visible ? 8 : 0
                anchors.right: closeBtn.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: card.entry.appName || "notification"
                elide: Text.ElideRight
                color: card.urgencyColor
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize - 2
                font.bold: true
            }

            Text {
                id: closeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: closeMa.containsMouse ? Theme.urgent : Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.dismiss(card.entry)
                }
            }
        }

        Text {
            width: parent.width
            visible: text.length > 0
            text: card.entry.summary
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Text {
            width: parent.width
            visible: text.length > 0
            text: card.entry.body
            // PlainText on purpose: body-markup is NOT advertised, so a client sending markup
            // is out of spec and we show exactly what we were sent rather than half-parsing it
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 1
        }

        // `value` hint — progress-style notifications (volume, downloads, build steps)
        Rectangle {
            width: parent.width
            height: 4
            radius: height / 2
            visible: card.entry.hasProgress
            color: Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.35)

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(1, card.entry.value / 100))
                color: card.urgencyColor
                Behavior on width {
                    NumberAnimation {
                        duration: Theme.animFast
                        easing.type: Theme.easing
                    }
                }
            }
        }
    }
}
