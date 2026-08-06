import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import ".."
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

    // the keyboard's cursor (story: notif-keyboard-control). Read off the singleton rather than
    // passed down the slot: the selection follows a notification id, not a position, so a card
    // that reflows into another position keeps it.
    readonly property bool selected: NotifyFocus.active && NotifyFocus.selectedId === card.entry.nid

    implicitHeight: layout.implicitHeight + Theme.pad * 2
    radius: Theme.radius
    // No border at all: a notification is paper that landed on the desktop, not a powered
    // surface. Depth comes from the shadow (the Elevation sibling in NotificationSlot), colour
    // from the urgency stripe, and the glass from the Shimmer at the bottom of this file.
    // Selection is marked by the stripe and an accent-tinted shadow instead of a thicker stroke.
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, card.selected ? Math.min(1, NotifyConfig.surface.cardOpacity + 0.1) : NotifyConfig.surface.cardOpacity)

    // urgency stripe down the leading edge — the one always-on colour cue
    Rectangle {
        id: stripe
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Theme.borderThin
        width: card.selected ? 6 : 3
        radius: width / 2
        color: card.selected ? Theme.accent : card.urgencyColor
        Behavior on width {
            NumberAnimation {
                duration: Theme.animFast
            }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // reading a card must never be what makes it vanish: the pointer freezes its countdown
        // (and its collapse clock) until it leaves again
        onEntered: Notifications.pause(card.entry)
        onExited: Notifications.resume(card.entry)
        // A resident notification is explicitly asking to survive interaction, so clicking the
        // body doesn't close it. Clicking the card IS the spec's `default` action when the
        // client supplied one — that is what activating a notification means, which is why the
        // default action gets no button and no key of its own.
        onClicked: mouse => {
            if (card.entry.collapsed) {
                Notifications.expand(card.entry); // one click brings a shrunk critical back
                return;
            }
            if (mouse.button === Qt.LeftButton) {
                const def = Notifications.defaultActionFor(card.entry);
                if (def) {
                    def.invoke();
                    if (!card.entry.resident)
                        Notifications.dismiss(card.entry);
                    return;
                }
            }
            if (mouse.button === Qt.MiddleButton || !card.entry.resident)
                Notifications.dismiss(card.entry);
        }
    }

    // ---------------------------------------------------------------------------------------
    // Expansion. A body longer than the card shows is elided; Enter (or a click on the hint)
    // unfolds it. `truncated` is Qt's own answer to "did this text not fit", so the hint appears
    // exactly when there is more behind it — never on a card that is already whole.
    // ---------------------------------------------------------------------------------------

    property bool expanded: false
    readonly property bool hasMore: bodyText.truncated || card.expanded

    function toggleExpanded() {
        card.expanded = !card.expanded;
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Theme.animMed
            easing.type: Theme.easing
        }
    }

    // ---------------------------------------------------------------------------------------
    // Remaining-time indicator. `remaining` is animated from wherever the entry's clock actually
    // is down to zero, and restarted whenever the singleton re-arms that clock (runToken). It is
    // display only — the Timer in Notifications is what expires the card, so a dropped frame or
    // a paused animation can never change when that happens.
    // ---------------------------------------------------------------------------------------

    property real remaining: 1

    function restartCountdown() {
        countdown.stop();
        if (card.entry.spanMs <= 0) {
            card.remaining = 0;
            return;
        }
        card.remaining = Math.max(0, Math.min(1, card.entry.remainingMs / card.entry.spanMs));
        countdown.duration = card.entry.remainingMs;
        countdown.start();
    }

    NumberAnimation {
        id: countdown
        target: card
        property: "remaining"
        to: 0
        easing.type: Easing.Linear
        // `running` guards the binding: setPaused() on a stopped animation is a Qt warning, and
        // a sticky card (no countdown to run) pauses constantly under keyboard focus.
        paused: countdown.running && card.entry.paused
    }

    Connections {
        target: card.entry
        function onRunTokenChanged() {
            card.restartCountdown();
        }
    }

    // Enter in focus mode. The signal carries the notification id rather than the entry so the
    // singleton never has to hold a reference to a view.
    Connections {
        target: NotifyFocus
        function onExpandRequested(nid) {
            if (nid === card.entry.nid)
                card.toggleExpanded();
        }
    }

    Component.onCompleted: card.restartCountdown()

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
                // the pill has room for one line, and which notification it is matters more there
                // than which app sent it
                text: card.entry.collapsed ? (card.entry.summary || card.entry.appName) : (card.entry.appName || "notification")
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
            // collapsed: the pill keeps the header row (icon, app, close) and nothing else
            visible: text.length > 0 && !card.entry.collapsed
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
            id: bodyText
            width: parent.width
            visible: text.length > 0 && !card.entry.collapsed
            text: card.entry.body
            // PlainText on purpose: body-markup is NOT advertised, so a client sending markup
            // is out of spec and we show exactly what we were sent rather than half-parsing it
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            // 6 lines folded; expanded is capped too, because a client that sends a 900-line
            // body must not be able to push a card past the screen edge
            maximumLineCount: card.expanded ? 40 : 6
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 1
        }

        // "more" affordance: only when the body actually did not fit, so it never promises
        // content that is not there. Click or Enter (focus mode) unfolds; the same row carries
        // the copy hint, because the two things you want from a long notification are to read
        // all of it and to put it somewhere else.
        Row {
            visible: card.hasMore && !card.entry.collapsed
            spacing: 10

            Text {
                text: card.expanded ? "  less" : "  more"
                color: moreMa.containsMouse ? Theme.accent : Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
                MouseArea {
                    id: moreMa
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.toggleExpanded()
                }
            }

            Text {
                text: "  yank"
                color: copyMa.containsMouse ? Theme.accent : Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
                MouseArea {
                    id: copyMa
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.copy(card.entry, false)
                }
            }
        }

        // Action buttons (story: notif-actions, AD-012). Spec actions and custom actions render
        // identically and answer the same key hints — the user does not care which side of
        // D-Bus a verb lives on. Hidden while collapsed: a shrunk pill is not a control surface.
        Row {
            id: actionRow
            // Recomputed rather than cached: `actions` binds through entry.notification, so a
            // replaces_id update that changes the verbs is picked up like every other field.
            readonly property var list: Notifications.actionsFor(card.entry)
            visible: actionRow.list.length > 0 && !card.entry.collapsed
            spacing: 6

            Repeater {
                model: actionRow.list

                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    height: chipRow.implicitHeight + 6
                    width: chipRow.implicitWidth + 14
                    radius: Theme.radius / 2
                    color: chipMa.containsMouse
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                        : Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.12)

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: chip.modelData.key.length > 0
                            // ^r, the terminal spelling of Ctrl+R — this shell is
                            // terminal-flavoured and it is two glyphs instead of six
                            text: "^" + chip.modelData.key
                            color: Theme.accent
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSize - 3
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.label
                            color: chipMa.containsMouse ? Theme.accent : Theme.fg
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    MouseArea {
                        id: chipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifications.invokeAction(card.entry, chip.modelData, "")
                    }
                }
            }
        }

        // `value` hint — progress-style notifications (volume, downloads, build steps)
        Rectangle {
            width: parent.width
            height: 4
            radius: height / 2
            visible: card.entry.hasProgress && !card.entry.collapsed
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

        // how much of this card's dwell is left — and, when it stops moving and greys out, that
        // the pointer is holding it open. Sticky and drawer-only cards have no countdown to show.
        Rectangle {
            width: parent.width
            height: 2
            radius: height / 2
            visible: Notifications.timing.showRemaining && card.entry.durationMs > 0 && !card.entry.collapsed
            color: Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.25)

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * card.remaining
                color: card.entry.paused ? Theme.subtext : card.urgencyColor
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animFast
                    }
                }
            }
        }
    }

    // Cursor-lit glass, the same sheen the bar sections and the launcher carry. Last child so
    // the light sits over the content rather than under it.
    Shimmer {
        anchors.fill: parent
        radius: parent.radius
    }
}
