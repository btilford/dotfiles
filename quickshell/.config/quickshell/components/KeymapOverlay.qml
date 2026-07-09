import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Fullscreen keymap cheatsheet. Lists binds from `hyprctl binds -j`, defaulting to the active
// submap (or Global). A search box filters by chord/description live; Tab toggles "all maps".
// Non-interactive use = just read it; interactive = type to search. Esc / click-backdrop closes.
PanelWindow {
    id: win
    visible: Keymap.shown
    color: "transparent"
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-keymap"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property bool showAll: false
    readonly property var filtered: {
        const q = search.text.toLowerCase();
        const out = [];
        for (const b of Keymap.binds) {
            const sm = b.submap || "";
            if (!win.showAll && sm !== Keymap.filterSubmap)
                continue;
            const chord = Keymap.chord(b);
            const act = Keymap.action(b);
            if (q.length && (chord + " " + act).toLowerCase().indexOf(q) < 0)
                continue;
            out.push({ "chord": chord, "action": act, "submap": sm });
        }
        return out;
    }

    onVisibleChanged: if (visible) {
        search.text = "";
        win.showAll = false;
        search.forceActiveFocus();
    }

    // dim backdrop
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
            onClicked: Keymap.close()
        }
    }

    // panel
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(760, win.width * 0.7)
        height: Math.min(win.height * 0.75, header.height + list.contentHeight + 3 * Theme.pad + search.height)
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity)

        // animated energy border tracing the panel (replaces the static stroke)
        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: 2.0
            energy: win.visible ? 0.7 : 0.0
        }

        scale: win.visible ? 1 : 0.96
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

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Keymap.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                win.showAll = !win.showAll;
                event.accepted = true;
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.pad

            // header
            Item {
                id: header
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Keymap — " + (win.showAll ? "all maps" : (Keymap.filterSubmap.length ? Keymap.filterSubmap : "Global"))
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.filtered.length + " binds · [Tab] all · [Esc] close"
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            // search
            Rectangle {
                width: parent.width
                height: 30
                radius: 5
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)
                border.width: 1
                border.color: search.activeFocus ? Theme.accent : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                TextField {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    leftPadding: 0
                    verticalAlignment: Text.AlignVCenter
                    background: null
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize
                    placeholderText: "Search keybinds…"
                    placeholderTextColor: Theme.subtext
                    Keys.onEscapePressed: Keymap.close()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            win.showAll = !win.showAll;
                            event.accepted = true;
                        }
                    }
                }
            }

            // list
            ListView {
                id: list
                width: parent.width
                height: parent.height - header.height - search.height - parent.spacing * 2
                clip: true
                model: win.filtered
                spacing: 2
                delegate: Item {
                    required property var modelData
                    width: list.width
                    height: 26
                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: rowMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : "transparent"
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.42
                        text: modelData.chord
                        color: Theme.accent
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: parent.width * 0.44
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.action
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
}
