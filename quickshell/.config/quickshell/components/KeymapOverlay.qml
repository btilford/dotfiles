import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Fullscreen keymap cheatsheet. Lists binds from `hyprctl binds -j`, filtered by a submap TREE
// sidebar: Global at the root, each submap nested under the map its entry bind lives in (submaps
// can nest — e.g. window-swap inside window-cmd), All at the bottom. Each node shows the chord
// that enters it. Vim-style modal nav: opens in NAV mode — j/k move, Ctrl-d/u half-page, gg/G
// top/bottom, Tab/Shift-Tab cycle tree nodes, "/" or "i" focus the search box, Esc closes.
// In the search box, typing filters live; Esc/Enter return to NAV mode.
PanelWindow {
    id: win
    visible: Keymap.shown
    color: "transparent"
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-keymap"
    // true fullscreen (don't shrink below the bar's exclusive zone) — the connector fan
    // assumes window coords == screen coords
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Submap tree, flattened depth-first: [{name, submap, chord, depth}]. `submap` is the
    // filter value ("" = Global, null = All). A submap's parent is the submap its entry bind
    // fires from (Keymap.submapEntry); unparented maps fall back to Global.
    readonly property var nodes: {
        const parentOf = {};
        const chordOf = {};
        const seen = [];
        for (const b of Keymap.binds) {
            const sm = b.submap || "";
            if (sm.length && seen.indexOf(sm) < 0)
                seen.push(sm);
            const target = Keymap.submapEntry(b);
            if (!target)
                continue;
            if (seen.indexOf(target) < 0)
                seen.push(target);
            const from = sm;
            // first entry bind wins, but a Global entry beats a nested one
            if (!(target in parentOf) || (parentOf[target] !== "" && from === ""))
                parentOf[target] = from;
            if (!(target in chordOf) || (parentOf[target] === from))
                chordOf[target] = Keymap.chord(b);
        }
        for (const s of seen)
            if (!(s in parentOf))
                parentOf[s] = "";
        const kids = {};
        for (const s in parentOf) {
            if (!(parentOf[s] in kids))
                kids[parentOf[s]] = [];
            kids[parentOf[s]].push(s);
        }
        for (const k in kids)
            kids[k].sort();
        const out = [{ name: "Global", submap: "", chord: "", depth: 0 }];
        const visited = new Set();
        const walk = (parent, depth) => {
            for (const s of (kids[parent] || [])) {
                if (visited.has(s))
                    continue;
                visited.add(s);
                out.push({ name: s, submap: s, chord: chordOf[s] || "", depth: depth });
                walk(s, depth + 1);
            }
        };
        walk("", 1);
        out.push({ name: "All", submap: null, chord: "", depth: 0 });
        return out;
    }
    property int nodeIdx: 0

    readonly property var filtered: {
        const q = search.text.toLowerCase();
        const node = win.nodes[win.nodeIdx];
        const out = [];
        for (const b of Keymap.binds) {
            const sm = b.submap || "";
            if (node.submap !== null && sm !== node.submap)
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

    function cycleNode(dir) {
        win.nodeIdx = (win.nodeIdx + dir + win.nodes.length) % win.nodes.length;
    }

    onVisibleChanged: if (visible) {
        search.text = "";
        // default to the node of the submap active when the overlay opened
        let i = 0;
        if (Keymap.filterSubmap.length)
            i = Math.max(0, win.nodes.findIndex(n => n.submap === Keymap.filterSubmap));
        win.nodeIdx = i;
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
    // three energy lines fanning from the bar sections into the panel
    ConnectorFan {
        box: panel
        active: win.visible
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(880, win.width * 0.75)
        // fixed height — content-driven sizing made the panel jump when switching submaps
        height: win.height * 0.7
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.surfaceOpacity)

        // animated energy border tracing the panel (replaces the static stroke)
        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: Theme.borderThickness
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
                    win.cycleNode(1);
                } else if (event.key === Qt.Key_Backtab) {
                    win.cycleNode(-1);
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
                    text: "Keymap — " + win.nodes[win.nodeIdx].name
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

            // search
            Rectangle {
                width: parent.width
                height: 30
                radius: 5
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)
                border.width: Theme.borderThin
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
                            win.cycleNode(1);
                        } else if (event.key === Qt.Key_Backtab) {
                            win.cycleNode(-1);
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

            // tree sidebar + bind list
            Row {
                width: parent.width
                height: parent.height - header.height - search.height - parent.spacing * 2
                spacing: Theme.pad

                // submap tree
                Column {
                    id: tree
                    width: 230
                    spacing: 2
                    Repeater {
                        model: win.nodes
                        delegate: Rectangle {
                            id: node
                            required property var modelData
                            required property int index
                            readonly property bool current: index === win.nodeIdx
                            width: tree.width
                            height: 26
                            radius: 4
                            color: nodeMa.containsMouse && !current ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06) : "transparent"
                            // breathing neon fill on the current tree node
                            EnergyFill {
                                visible: node.current
                                anchors.fill: parent
                                radius: 4
                                alpha: 0.3
                            }
                            Text {
                                id: nodeName
                                anchors.left: parent.left
                                anchors.leftMargin: 8 + node.modelData.depth * 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: (node.modelData.depth > 0 ? "└ " : "") + node.modelData.name
                                color: node.current ? Theme.accent : Theme.fg
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: node.current
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: node.modelData.chord
                                color: node.current
                                    ? Theme.fg
                                    : Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.7)
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 3
                            }
                            MouseArea {
                                id: nodeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.nodeIdx = node.index
                            }
                        }
                    }
                }

                // vertical divider
                Rectangle {
                    width: 1
                    height: parent.height
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                }

                // list
                ListView {
                    id: list
                    width: parent.width - tree.width - 1 - parent.spacing * 2
                    height: parent.height
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
                            color: rowMa.containsMouse && !row.current ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06) : "transparent"
                        }
                        // breathing neon fill on the selected row
                        EnergyFill {
                            visible: row.current
                            anchors.fill: parent
                            radius: 4
                            alpha: 0.3
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
}
