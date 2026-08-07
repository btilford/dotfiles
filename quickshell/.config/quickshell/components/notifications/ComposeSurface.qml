import QtQuick
import Quickshell
import ".."
import "../../config"

// The centred compose surface: one notification, pulled out of the stack (or out of the drawer's
// list) into something wide enough to write in. Pure view over NotifyCompose.
//
// It is NOT its own window. The host — the popup stack's flightHost layer, or the drawer — is a
// window that already holds the keyboard, so composing changes what is on screen and never which
// surface owns the grab (AD-012 §5: no third focus-grabbing surface). `hosted` says whether this
// instance is the one that should render, so exactly one of the two ever does.
//
// It is also not a NotificationCard with a bigger prompt box, though that was the shorter route.
// A card is a view over a live *entry* — it binds paused/collapsed/remainingMs/runToken and the
// notification object behind them — and half of compose is a stored SQLite row, which has none of
// those. One surface that renders both, over NotifyCompose's uniform view model, beats a card
// taught to survive a target that is missing most of what it reads.
Item {
    id: surface

    // This window is the one that should render the open compose. The host decides — the stack
    // additionally has to check that the composed entry belongs to ITS stack, since there is one
    // window per (monitor, anchor) pair.
    required property bool hosted

    readonly property bool shown: NotifyCompose.active && surface.hosted

    // There is somewhere for typed text to go, so the field is shown. Kept here rather than read
    // off the field's own `visible`: QML's `visible` reports EFFECTIVE visibility (parent
    // included), so a box whose visibility came from its child's would latch itself off forever.
    readonly property bool canWrite: NotifyCompose.route !== "none"

    // resolved icon: the notification image wins over app_icon, which may be a themed icon name
    // or a plain path
    readonly property string iconSource: {
        if (NotifyCompose.image)
            return NotifyCompose.image;
        const name = NotifyCompose.appIcon;
        if (!name)
            return "";
        if (name.startsWith("/") || name.startsWith("file://"))
            return name;
        return Quickshell.iconPath(name, true);
    }

    // Handed back when the surface closes, so the host can put the keyboard back on its own key
    // handler — nothing else in the window has focus while the field holds it.
    signal closed

    // Zero-sized while closed ON PURPOSE: the stack window masks its input to the items that may
    // be clicked, and a full-window item that is merely `visible: false` still contributes its
    // geometry to that region — which would make the notification layer swallow every click on
    // the desktop. Size, not visibility, is what keeps the mask honest.
    width: surface.shown ? parent.width : 0
    height: surface.shown ? parent.height : 0
    visible: surface.shown

    function focusField() {
        if (surface.canWrite)
            fieldText.forceActiveFocus();
        else
            keyCatcher.forceActiveFocus();
    }

    onShownChanged: if (surface.shown)
        Qt.callLater(surface.focusField)

    // Dim what is behind: the whole point of pulling one notification out is that it is now the
    // only thing being dealt with. Click-away closes, like every other dialog in this shell.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            onClicked: NotifyCompose.close()
        }
    }

    Elevation {
        target: panel
        level: 1.6
    }

    Rectangle {
        id: panel

        // Wider than a card (which is 420 by default) and capped, so it stays a dialog rather
        // than becoming a full-screen editor.
        width: Math.min(760, Math.max(480, surface.width * 0.6))
        height: Math.min(column.implicitHeight + Theme.pad * 2, surface.height * 0.8)
        anchors.centerIn: parent
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Math.min(1, NotifyConfig.surface.cardOpacity + 0.15))

        // The compose surface is a dialog, so it reads like one: the energy border is what the
        // launcher, the session overlay and the drawer's modal all use.
        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: Theme.borderThickness
            energy: surface.shown ? 0.7 : 0.0
        }

        scale: surface.shown ? 1 : 0.96
        Behavior on scale {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Easing.OutBack
            }
        }

        // swallow clicks that land on the panel so the click-away backdrop does not see them
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.pad

            // header: icon, app, provenance, close
            Item {
                width: parent.width
                height: Math.max(icon.height, appText.implicitHeight)

                Image {
                    id: icon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: surface.iconSource !== ""
                    source: surface.iconSource
                    sourceSize.width: Theme.barIcon
                    sourceSize.height: Theme.barIcon
                    width: visible ? Theme.barIcon : 0
                    height: Theme.barIcon
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Text {
                    id: appText
                    anchors.left: icon.right
                    anchors.leftMargin: icon.visible ? 8 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: NotifyCompose.appName || "notification"
                    color: Theme.accent
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }

                // A composed row that has no client behind it any more says so up here, not only
                // in the note by the field: it changes what every verb below can do.
                Text {
                    anchors.left: appText.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: NotifyCompose.fromHistory
                    text: "· history"
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 3
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "[Esc] close"
                    color: closeMa.containsMouse ? Theme.accent : Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 3
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotifyCompose.close()
                    }
                }
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: NotifyCompose.summary
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }

            // The body in full — this surface exists partly because a card shows six lines of it.
            // Still capped, and scrollable past the cap: a client that sends a 900-line body must
            // not be able to push the panel past the screen edge.
            Flickable {
                width: parent.width
                height: Math.min(bodyText.implicitHeight, surface.height * 0.3)
                visible: bodyText.text.length > 0
                contentHeight: bodyText.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    id: bodyText
                    width: parent.width
                    text: NotifyCompose.body
                    // PlainText: body markup is not advertised, so a client sending markup is out
                    // of spec and we show exactly what we were sent
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            ActionChips {
                width: parent.width
                list: NotifyCompose.actions
                activeAction: NotifyCompose.pendingAction
                onTriggered: action => {
                    NotifyCompose.invoke(action);
                    Qt.callLater(surface.focusField);
                }
            }

            // A capturing action is running — usually a language model, which takes seconds.
            Text {
                visible: NotifyCompose.live ? NotifyCompose.live.awaitingCapture : false
                text: "  working…"
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
            }

            // Why there is no field. Shown INSTEAD of the box, never beside a dead one: a reply
            // field that silently goes nowhere is worse than no reply field (see NotifyCompose).
            Text {
                width: parent.width
                visible: NotifyCompose.note.length > 0
                text: NotifyCompose.note
                wrapMode: Text.Wrap
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize - 2
            }

            Rectangle {
                id: fieldBox
                width: parent.width
                // The room to write that this whole surface is for: six lines to start, growing
                // with the text and then scrolling.
                height: Math.max(fieldText.font.pixelSize * 9, Math.min(fieldText.implicitHeight + 16, surface.height * 0.35))
                visible: surface.canWrite
                radius: Theme.radius / 2
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)
                border.width: Theme.borderThin
                border.color: fieldText.activeFocus ? Theme.accent : Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.4)

                Flickable {
                    id: field
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: fieldText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // TextEdit, not TextInput: replies are multi-line, and an agent draft
                    // especially so. TextEdit is in QtQuick, so this needs no Controls import.
                    TextEdit {
                        id: fieldText
                        width: field.width
                        wrapMode: TextEdit.Wrap
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize
                        selectByMouse: true

                        // The singleton holds the text so a draft can be written into it and the
                        // surface can be re-hosted; the widget is the editor, not the owner.
                        onTextChanged: NotifyCompose.text = text

                        Connections {
                            target: NotifyCompose
                            // A draft replaces what is there and selects it, so the first
                            // keystroke discards it and no keystroke is needed to accept it.
                            function onLoadTokenChanged() {
                                fieldText.text = NotifyCompose.text;
                                fieldText.selectAll();
                                fieldText.forceActiveFocus();
                            }
                            // opened, closed, or submitted: the widget follows
                            function onHostChanged() {
                                fieldText.text = NotifyCompose.text;
                            }
                            function onPendingActionChanged() {
                                fieldText.text = NotifyCompose.text;
                            }
                        }

                        Keys.onPressed: event => {
                            // Ctrl+<letter> FIRST, as everywhere else in this shell: the branches
                            // below carry no modifier guard, so Ctrl+D would otherwise be typed
                            // rather than fire an action.
                            if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_A && event.key <= Qt.Key_Z && event.key !== Qt.Key_A && event.key !== Qt.Key_C && event.key !== Qt.Key_V && event.key !== Qt.Key_X && event.key !== Qt.Key_Z) {
                                if (NotifyCompose.invokeActionByKey(String.fromCharCode(event.key).toLowerCase())) {
                                    event.accepted = true;
                                    return;
                                }
                            }
                            if (event.key === Qt.Key_Escape) {
                                NotifyCompose.close();
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                                // Ctrl+Enter sends, bare Enter inserts a newline — the other way
                                // round is what chat clients do and is wrong for a field an agent
                                // drafts INTO: the first thing you do to a draft is edit it.
                                NotifyCompose.submit();
                                event.accepted = true;
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            visible: fieldText.text.length === 0
                            text: NotifyCompose.placeholder
                            color: Theme.subtext
                            font: fieldText.font
                        }
                    }
                }
            }

            // Keys while there is no field to hold focus — Esc and the action hints still work.
            Item {
                id: keyCatcher
                width: parent.width
                height: 0

                Keys.onPressed: event => {
                    if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                        if (!NotifyCompose.invokeActionByKey(String.fromCharCode(event.key).toLowerCase()))
                            return;
                    } else if (event.key === Qt.Key_Escape)
                        NotifyCompose.close();
                    else
                        return;
                    event.accepted = true;
                }
            }

            Text {
                width: parent.width
                text: (surface.canWrite ? "[Ctrl+↵] " + (NotifyCompose.route === "action" ? "run" : "send") + " · " : "") + "[^key] action · [Esc] close"
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // The host puts the keyboard back on its own handler; nothing else in the window has it while
    // the field is open.
    onVisibleChanged: if (!surface.visible)
        surface.closed()
}
