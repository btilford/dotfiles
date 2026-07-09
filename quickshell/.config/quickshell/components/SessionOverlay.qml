import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Fullscreen session/power dialog on the focused monitor. Replaces wlogout. Driven by the Session
// singleton (Power button, IPC, SUPER+Escape all set Session.shown). Dim backdrop (click to cancel),
// a centered row of action cards with icon + label + key hint, and single-key accelerators
// (l/e/u/h/r/s) plus Escape to cancel.
PanelWindow {
    id: win
    visible: Session.shown
    color: "transparent"
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-session"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property int sel: 0
    onVisibleChanged: if (visible) {
        sel = 0;
        keyScope.forceActiveFocus();
    }

    // dim backdrop — click anywhere to cancel
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: win.visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animMed
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: Session.close()
        }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const n = Session.actions.length;
            if (event.key === Qt.Key_Escape) {
                Session.close();
            } else if (event.key === Qt.Key_Left) {
                win.sel = (win.sel - 1 + n) % n;
            } else if (event.key === Qt.Key_Right) {
                win.sel = (win.sel + 1) % n;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                Session.run(Session.actions[win.sel].cmd);
            } else if (event.text && Session.runKey(event.text.toLowerCase())) {// letter accelerator fired
            } else {
                return;
            }
            event.accepted = true;
        }

        Row {
            id: cards
            anchors.centerIn: parent
            spacing: 18
            scale: win.visible ? 1 : 0.92
            opacity: win.visible ? 1 : 0
            Behavior on scale {
                NumberAnimation {
                    duration: Theme.animMed
                    easing.type: Easing.OutBack
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animFast
                }
            }

            Repeater {
                model: Session.actions
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool hot: cardMa.containsMouse || card.index === win.sel
                    width: 120
                    height: 130
                    radius: Theme.radius
                    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity)
                    // faint static outline when idle; energy border takes over when hot
                    border.width: 1
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, card.hot ? 0 : 0.35)
                    scale: card.hot ? 1.06 : 1
                    // pointer nav follows the mouse too
                    onHotChanged: if (cardMa.containsMouse)
                        win.sel = card.index
                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.animFast
                            easing.type: Theme.easing
                        }
                    }

                    // animated energy border on the selected/hovered card
                    EnergyBorder {
                        anchors.fill: parent
                        radius: parent.radius
                        thickness: 2.5
                        energy: card.hot ? 0.9 : 0.0
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: card.modelData.icon
                            color: card.hot ? Theme.accent : Theme.fg
                            font.family: Theme.fontUi
                            font.pixelSize: 40
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: card.modelData.label
                            color: Theme.fg
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSize
                        }
                        // accelerator key — always shown as a small keycap
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: keycap.implicitWidth + 12
                            height: keycap.implicitHeight + 6
                            radius: 4
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, card.hot ? 0.9 : 0.5)
                            Text {
                                id: keycap
                                anchors.centerIn: parent
                                text: card.modelData.key.toUpperCase()
                                color: Theme.accent
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                            }
                        }
                    }

                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Session.run(card.modelData.cmd)
                    }
                }
            }
        }
    }
}
