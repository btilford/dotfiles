import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "../config"

// Notification drawer: the history, grouped and searchable. A view over NotifyDrawer, which
// is a view over the SQLite store — no notification state lives in this file.
//
// One window, two shapes (NotifyConfig.drawer.mode): "panel" is a full-height slab against the
// right edge, "modal" is the centred launcher-shaped dialog. Same rows, same keys, same code
// path; only the geometry differs, because "which one do I actually want" is a question the
// story says to answer by living with both rather than by argument.
PanelWindow {
    id: win

    visible: Shell.notificationsEnabled && NotifyDrawer.shown
    color: "transparent"
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    readonly property bool modal: NotifyDrawer.mode === "modal"

    // ExclusionMode.Ignore means the bar does not push this window off its strip, so a
    // full-height panel has to step around it by hand — exactly as the popup stack does. The
    // hub height covers both bar sizes: overshooting a minimal bar by a few pixels is
    // invisible, sliding the drawer's header under a hub bar is not.
    readonly property int barInset: Shell.barVisible ? Theme.barHeightHub : 0
    readonly property int topInset: Shell.barDevMode ? 0 : win.barInset
    readonly property int bottomInset: Shell.barDevMode ? win.barInset : 0

    WlrLayershell.layer: WlrLayer.Overlay
    // Unlike a popup, the drawer is something the user deliberately opened, so taking the
    // keyboard is correct here — it is the same rule, not an exception to it: focus follows
    // intent (see AD-011).
    WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-notification-drawer"
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // The field holds its own text, so a reopened drawer would show the last search while
    // listing everything — the box and the list have to agree about what is being filtered.
    onVisibleChanged: if (visible) {
        search.text = "";
        keys.forceActiveFocus();
    }

    // click-away
    MouseArea {
        anchors.fill: parent
        onClicked: NotifyDrawer.close()
    }

    // ---------------------------------------------------------------------------------------
    // Keys — the popup stack's scheme, so one set of habits covers both surfaces:
    // j/k move, gg/G ends, d clears, D clears the group, A clears everything listed,
    // Tab folds a group, / searches, f cycles the time filter, Esc closes.
    // ---------------------------------------------------------------------------------------
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        property bool pendingG: false

        Keys.onPressed: event => {
            let g = false;
            if (event.key === Qt.Key_Escape)
                NotifyDrawer.close();
            else if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
                NotifyDrawer.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
                NotifyDrawer.move(-1);
            else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier))
                NotifyDrawer.last();
            else if (event.key === Qt.Key_G) {
                if (keys.pendingG)
                    NotifyDrawer.first();
                else
                    g = true;
            } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ShiftModifier))
                NotifyDrawer.clearSelectedGroup();
            else if (event.key === Qt.Key_D || event.key === Qt.Key_X)
                NotifyDrawer.clearSelected();
            else if (event.key === Qt.Key_A && (event.modifiers & Qt.ShiftModifier))
                NotifyDrawer.clearAll();
            else if (event.key === Qt.Key_F)
                NotifyDrawer.cycleRange();
            else if (event.key === Qt.Key_C)
                NotifyDrawer.clearFilters();
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                NotifyDrawer.activate();
            else if (event.key === Qt.Key_Slash || event.key === Qt.Key_I)
                search.forceActiveFocus();
            else
                return;
            keys.pendingG = g;
            event.accepted = true;
        }
    }

    Rectangle {
        id: panel

        // panel: hard against the right edge, full height, no rounding on that edge.
        // modal: floating, centred, launcher proportions.
        width: win.modal ? Math.min(880, win.width * 0.7) : NotifyConfig.drawer.width
        height: win.modal ? win.height * 0.7 : win.height - win.topInset - win.bottomInset
        x: win.modal ? (win.width - width) / 2 : win.width - width * panel.reveal
        y: win.modal ? (win.height - height) / 2 : win.topInset
        radius: win.modal ? Theme.radius : 0
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity)

        // 0 = off screen right, 1 = fully out. The panel slides; the modal fades and scales,
        // matching what each shape does everywhere else in this shell.
        property real reveal: win.visible ? 1 : 0
        Behavior on reveal {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Theme.easing
            }
        }

        opacity: win.modal ? (win.visible ? 1 : 0) : 1
        scale: win.modal ? (win.visible ? 1 : 0.96) : 1
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Easing.OutBack
            }
        }

        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: Theme.borderThickness
            energy: win.visible ? 0.7 : 0.0
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.pad

            // header: title, counts, filter chips
            Item {
                width: parent.width
                height: 24

                Text {
                    id: title
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }

                Text {
                    anchors.left: title.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: NotifyDrawer.filtered.length + " of " + NotifyDrawer.rows.length + (NotifyDrawer.filterApp ? " · " + NotifyDrawer.filterApp : "") + (NotifyDrawer.filterRange !== "all" ? " · " + NotifyDrawer.filterRange : "")
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 2
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "clear all"
                    color: clearMa.containsMouse ? Theme.urgent : Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 2
                    MouseArea {
                        id: clearMa
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotifyDrawer.clearAll()
                    }
                }
            }

            // search
            Rectangle {
                width: parent.width
                height: 30
                radius: Theme.radius
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)
                border.width: Theme.borderThin
                border.color: search.activeFocus ? Theme.accent : Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.4)

                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.margins: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 1
                    clip: true
                    onTextChanged: NotifyDrawer.search = text
                    // Esc/Enter hand the keyboard back to nav mode rather than closing the
                    // drawer: closing on Esc-in-search loses the search AND the drawer, which
                    // is never what was meant.
                    Keys.onEscapePressed: keys.forceActiveFocus()
                    Keys.onReturnPressed: keys.forceActiveFocus()

                    Text {
                        anchors.fill: parent
                        visible: !search.text.length
                        verticalAlignment: Text.AlignVCenter
                        text: "Search…  [/] search · [j/k] move · [d] clear · [D] group · [A] all · [f] range · [Esc] close"
                        color: Theme.subtext
                        font: search.font
                        elide: Text.ElideRight
                    }
                }
            }

            // list
            ListView {
                id: list
                width: parent.width
                height: parent.height - y
                clip: true
                spacing: 4
                model: NotifyDrawer.items
                currentIndex: NotifyDrawer.selectedIndex
                highlightFollowsCurrentItem: true
                highlightMoveDuration: Theme.animFast
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index

                    readonly property bool isGroup: entry.modelData.kind === "group"
                    readonly property var row: entry.modelData.row || null
                    readonly property bool selected: NotifyDrawer.selectedKey === entry.modelData.key
                    readonly property int urgency: entry.isGroup ? entry.modelData.group.urgency : (entry.row ? entry.row.urgency : 1)
                    readonly property color urgencyColor: entry.urgency === NotificationUrgency.Critical ? Theme.urgent : (entry.urgency === NotificationUrgency.Low ? Theme.subtext : Theme.accent)

                    width: list.width
                    height: body.implicitHeight + 12

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: entry.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : (entry.isGroup ? Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.35) : "transparent")
                        border.width: entry.selected ? Theme.borderThin : 0
                        border.color: Theme.accent
                    }

                    // unread marker: the drawer's job is to make "what did I miss" answerable
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 3
                        width: 3
                        radius: 1.5
                        visible: entry.isGroup ? entry.modelData.group.unread > 0 : !entry.row.read_at
                        color: entry.urgencyColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => {
                            NotifyDrawer.selectedKey = entry.modelData.key;
                            if (mouse.button === Qt.MiddleButton) {
                                NotifyDrawer.clearSelected();
                                return;
                            }
                            if (entry.isGroup)
                                NotifyDrawer.toggleGroup(entry.modelData.group.name);
                        }
                    }

                    Column {
                        id: body
                        anchors.fill: parent
                        anchors.margins: 6
                        anchors.leftMargin: 12
                        spacing: 2

                        // group header
                        Row {
                            visible: entry.isGroup
                            spacing: 6

                            Text {
                                text: NotifyDrawer.isCollapsed(entry.isGroup ? entry.modelData.group.name : "") ? "" : ""
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Text {
                                text: entry.isGroup ? entry.modelData.group.name : ""
                                color: entry.urgencyColor
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: true
                            }
                            Text {
                                text: entry.isGroup ? "×" + entry.modelData.group.count + (entry.modelData.group.unread ? " · " + entry.modelData.group.unread + " new" : "") : ""
                                color: Theme.subtext
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }

                        // row: summary + time, then body
                        Item {
                            visible: !entry.isGroup
                            width: body.width
                            height: entry.isGroup ? 0 : summary.implicitHeight

                            Text {
                                id: summary
                                anchors.left: parent.left
                                anchors.right: stamp.left
                                anchors.rightMargin: 8
                                text: entry.row ? (entry.row.summary || "(no summary)") : ""
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: entry.row ? !entry.row.read_at : false
                            }

                            Text {
                                id: stamp
                                anchors.right: parent.right
                                anchors.verticalCenter: summary.verticalCenter
                                text: entry.row ? win.ago(entry.row.received_at) : ""
                                color: Theme.subtext
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }

                        Text {
                            visible: !entry.isGroup && text.length > 0
                            width: body.width
                            text: entry.row ? (entry.row.body || "") : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }

                // empty state — an empty drawer is a success, so it should not look like a bug
                Text {
                    anchors.centerIn: parent
                    visible: NotifyDrawer.items.length === 0
                    text: NotifyDrawer.loading ? "loading…" : (NotifyStore.healthy ? (NotifyDrawer.search.length || NotifyDrawer.filterApp ? "nothing matches" : "nothing to catch up on") : "history unavailable — the store is disabled")
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }

    // "4m" / "2h" / "3d" — relative time is what makes a list of notifications readable at a
    // glance; the absolute stamp is in the database for anyone who needs it.
    function ago(ms) {
        const s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (s < 60)
            return s + "s";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }
}
