import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Fullscreen keymap cheatsheet. Lists binds from `hyprctl binds -j` under a tab row with one tab
// per submap (Global first, All last), defaulting to the active submap. Vim-style modal nav:
// opens in NAV mode — j/k move, Ctrl-d/u half-page, gg/G top/bottom, Tab/Shift-Tab cycle tabs,
// "/" or "i" focus the search box, Esc closes. In the search box, typing filters live;
// Esc/Enter return to NAV mode; Up/Down still move the selection.
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

    // tab list: Global, each submap seen in the binds (sorted), All
    readonly property var tabs: {
        const s = new Set();
        for (const b of Keymap.binds)
            if (b.submap && b.submap.length)
                s.add(b.submap);
        return ["Global", ...[...s].sort(), "All"];
    }
    property int tabIdx: 0

    readonly property var filtered: {
        const q = search.text.toLowerCase();
        const tab = win.tabs[win.tabIdx];
        const out = [];
        for (const b of Keymap.binds) {
            const sm = b.submap || "";
            if (tab !== "All" && sm !== (tab === "Global" ? "" : tab))
                continue;
            const chord = Keymap.chord(b);
            const act = Keymap.action(b);
            if (q.length && (chord + " " + act).toLowerCase().indexOf(q) < 0)
                continue;
            out.push({ "chord": chord, "action": act, "submap": sm });
        }
        return out;
    }
    onFilteredChanged: list.currentIndex = filtered.length ? 0 : -1

    function cycleTab(dir) {
        win.tabIdx = (win.tabIdx + dir + win.tabs.length) % win.tabs.length;
    }

    onVisibleChanged: if (visible) {
        search.text = "";
        // default to the tab of the submap active when the overlay opened
        const i = win.tabs.indexOf(Keymap.filterSubmap);
        win.tabIdx = (Keymap.filterSubmap.length && i >= 0) ? i : 0;
        navKeys.forceActiveFocus();
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

    // water-mirror reflection under the panel (fades/scales with it)
    Reflection {
        sourceItem: panel
        anchors.top: panel.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: panel.horizontalCenter
        opacity: panel.opacity
    }

    // panel
    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(760, win.width * 0.7)
        height: Math.min(win.height * 0.75, header.height + tabRow.height + list.contentHeight + 4 * Theme.pad + search.height)
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity)

        // animated energy border tracing the panel (replaces the static stroke)
        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: 2.75
            energy: win.visible ? 0.7 : 0.0
        }

        // cursor-lit glimmer over the panel
        Shimmer {
            anchors.fill: parent
            radius: parent.radius
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

        // NAV mode key handling (vim-style). Focused whenever the search box isn't.
        FocusScope {
            id: navKeys
            anchors.fill: parent
            property bool pendingG: false
            Keys.onPressed: event => {
                const n = win.filtered.length;
                const page = Math.max(1, Math.floor(list.height / 28));
                let g = false;
                if (event.key === Qt.Key_Escape) {
                    Keymap.close();
                } else if (event.key === Qt.Key_Tab) {
                    win.cycleTab(1);
                } else if (event.key === Qt.Key_Backtab) {
                    win.cycleTab(-1);
                } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                    list.currentIndex = Math.min(list.currentIndex + 1, n - 1);
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                    list.currentIndex = Math.max(list.currentIndex - 1, 0);
                } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                    list.currentIndex = Math.min(list.currentIndex + Math.floor(page / 2), n - 1);
                } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                    list.currentIndex = Math.max(list.currentIndex - Math.floor(page / 2), 0);
                } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                    list.currentIndex = n - 1;
                } else if (event.key === Qt.Key_G) {
                    if (navKeys.pendingG)
                        list.currentIndex = n ? 0 : -1;
                    else
                        g = true;
                } else if (event.key === Qt.Key_Slash || event.key === Qt.Key_I) {
                    search.forceActiveFocus();
                } else {
                    return; // unhandled — don't accept, don't clear pendingG state below
                }
                navKeys.pendingG = g;
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
                    text: "Keymap — " + win.tabs[win.tabIdx]
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.filtered.length + " binds · [Tab] map · [j/k] move · [/] search · [Esc] close"
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            // submap tabs
            Row {
                id: tabRow
                width: parent.width
                spacing: 6
                Repeater {
                    model: win.tabs
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool current: index === win.tabIdx
                        width: tabText.implicitWidth + 18
                        height: 24
                        radius: 4
                        color: current
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                            : (tabMa.containsMouse ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : "transparent")
                        border.width: 1
                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, current ? 0.9 : 0.25)
                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.current ? Theme.accent : Theme.subtext
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: parent.current
                        }
                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.tabIdx = parent.index
                        }
                    }
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
                    placeholderText: "Search keybinds…  [Esc/Enter] back to nav"
                    placeholderTextColor: Theme.subtext
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            navKeys.forceActiveFocus();
                        } else if (event.key === Qt.Key_Tab) {
                            win.cycleTab(1);
                        } else if (event.key === Qt.Key_Backtab) {
                            win.cycleTab(-1);
                        } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
                            list.currentIndex = Math.min(list.currentIndex + 1, win.filtered.length - 1);
                        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
                            list.currentIndex = Math.max(list.currentIndex - 1, 0);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }
            }

            // list
            ListView {
                id: list
                width: parent.width
                height: parent.height - header.height - tabRow.height - search.height - parent.spacing * 3
                clip: true
                model: win.filtered
                spacing: 2
                currentIndex: 0
                onCurrentIndexChanged: if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem
                    width: list.width
                    height: 26
                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: row.current
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                            : (rowMa.containsMouse ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06) : "transparent")
                    }
                    // left accent bar on the selected row
                    Rectangle {
                        visible: row.current
                        anchors.left: parent.left
                        anchors.leftMargin: 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: parent.height - 8
                        radius: 2
                        color: Theme.accent
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.42
                        text: row.modelData.chord
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
                        text: row.modelData.action
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: list.currentIndex = row.index
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
}
