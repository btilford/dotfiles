import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Window picker and close-all confirm, driven from the Hyprland app/window/focus submaps
// (hypr/lua/keybindings.lua):
//
//   qs ipc call windowpicker pick ''              every window: type to filter, Enter focuses
//   qs ipc call windowpicker pick brave-browser   one app's windows
//   qs ipc call windowpicker close brave-browser  list one app's windows, Enter/y closes ALL
//   qs ipc call windowpicker hide
//
// The list is read fresh from `hyprctl clients -j` on every open rather than bound to
// Hyprland.toplevels: the JSON already carries title, class, workspace name and focus
// history in one read, and a picker that reflects the moment it opened is what you want.
//
// Lockout safety. This surface takes an EXCLUSIVE keyboard grab, and a layer surface that
// grabs the keyboard and then fails to activate leaves the whole session keyboard-dead
// (see the quickshell-exclusive-grab-lockout note: a property named `data` did exactly that
// to ClipboardDialog). So:
//   - no property here shadows an Item built-in (data, children, resources, state, ...);
//   - a click anywhere outside the box closes it, which needs no keyboard at all;
//   - an idle timer closes it after `idleMs` without a key, so a broken grab can never
//     hold the keyboard for longer than that.
PanelWindow {
    id: root
    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.grabKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-windowpicker"
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // false only in a test harness: renders without ever touching the keyboard
    property bool grabKeyboard: true
    readonly property int idleMs: 60000

    property string mode: "pick"   // pick | close
    property string appClass: ""   // "" = every window
    property string query: ""
    property var clients: []       // raw hyprctl clients, sorted
    readonly property var shown: {
        const q = root.query.toLowerCase();
        if (root.mode === "close" || !q.length)
            return root.clients;
        return root.clients.filter(c => (c.title + " " + c.class + " " + root.wsLabel(c)).toLowerCase().includes(q));
    }

    IpcHandler {
        target: "windowpicker"
        function pick(cls: string): void {
            root.open("pick", cls);
        }
        function close(cls: string): void {
            if (cls.length)
                root.open("close", cls);
        }
        function hide(): void {
            root.dismiss();
        }
    }

    // ---- lifecycle ----
    function open(m, cls) {
        root.mode = m;
        root.appClass = cls || "";
        root.query = "";
        root.clients = [];
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen)
            root.screen = Hyprland.focusedMonitor.screen;
        input.text = "";
        list.currentIndex = 0;
        reader.running = true;
        root.visible = true;
        idle.restart();
        input.forceActiveFocus();
    }
    function dismiss() {
        idle.stop();
        root.visible = false;
    }

    function wsLabel(c) {
        const n = c.workspace ? c.workspace.name : "";
        if (n.startsWith("special:hide-"))
            return "hidden";
        if (n.startsWith("special:"))
            return n.substring(8) + " (special)";
        return n;
    }

    function dispatch(lua) {
        Quickshell.execDetached(["hyprctl", "dispatch", lua]);
    }
    function focusClient(c) {
        if (!c)
            return;
        root.dismiss();
        root.dispatch('hl.dsp.focus({ window = "address:' + c.address + '" })');
    }
    function closeAll() {
        const targets = root.clients.slice();
        root.dismiss();
        for (const c of targets)
            root.dispatch('hl.dsp.window.close({ window = "address:' + c.address + '" })');
    }

    Process {
        id: reader
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let all = [];
                try {
                    all = JSON.parse(this.text);
                } catch (e) {
                    all = [];
                }
                if (root.appClass.length)
                    all = all.filter(c => c.class === root.appClass);
                // most recently used first, the order alt-tab trains you to expect
                all.sort((a, b) => (a.focusHistoryID ?? 1e9) - (b.focusHistoryID ?? 1e9));
                root.clients = all;
                // nothing to act on: do not hold an exclusive grab over an empty box
                if (!all.length)
                    root.dismiss();
            }
        }
    }

    Timer {
        id: idle
        interval: root.idleMs
        onTriggered: root.dismiss()
    }

    // ---- click-away to close: the keyboard-free way out ----
    MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
    }

    Rectangle {
        id: box
        width: 820
        height: root.mode === "close" ? Math.min(520, 120 + root.clients.length * 44) : 560
        anchors.centerIn: parent
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.surfaceOpacity)

        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: Theme.borderThickness
            energy: root.mode === "close" ? 1.0 : 0.7
        }
        Shimmer {
            anchors.fill: parent
            radius: parent.radius
        }
        // swallow clicks so click-away doesn't fire inside the box
        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.pad

            Rectangle {
                id: header
                width: parent.width
                height: 46
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
                radius: Theme.radius

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    height: 2
                    radius: 1
                    color: root.mode === "close" ? Theme.urgent : Theme.accent
                }

                Text {
                    id: countText
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode === "close" ? "Enter / y  close all   ·   Esc / n  cancel" : root.shown.length + (root.shown.length === 1 ? " window" : " windows")
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 2
                }

                // close mode: a fixed question, not a search field
                Text {
                    visible: root.mode === "close"
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Close " + root.clients.length + (root.clients.length === 1 ? " window" : " windows") + " of " + root.appClass + "?"
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                // Present in BOTH modes: it is the item that holds keyboard focus. In close mode
                // it is invisible and read-only, and only its key handler matters.
                TextField {
                    id: input
                    opacity: root.mode === "close" ? 0 : 1
                    readOnly: root.mode === "close"
                    anchors.left: parent.left
                    anchors.right: countText.left
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: root.appClass.length ? "Filter " + root.appClass + " windows  ·  Enter focuses" : "Filter windows  ·  Enter focuses"
                    color: Theme.fg
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize
                    background: Rectangle {
                        color: "transparent"
                    }
                    onTextChanged: {
                        if (root.mode !== "close") {
                            root.query = text;
                            list.currentIndex = 0;
                        }
                    }
                    Keys.onPressed: function (e) {
                        idle.restart();
                        const ctrl = e.modifiers & Qt.ControlModifier;
                        if (e.key === Qt.Key_Escape) {
                            root.dismiss();
                            e.accepted = true;
                        } else if (root.mode === "close") {
                            // every other key is swallowed: a stray letter must not close anything
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Y)
                                root.closeAll();
                            else if (e.key === Qt.Key_N)
                                root.dismiss();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_N && ctrl)) {
                            list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_P && ctrl)) {
                            list.currentIndex = Math.max(0, list.currentIndex - 1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            root.focusClient(root.shown[list.currentIndex]);
                            e.accepted = true;
                        }
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - header.height - parent.spacing
                clip: true
                model: root.shown
                currentIndex: 0
                onCurrentIndexChanged: if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem && root.mode !== "close"
                    width: list.width
                    height: 44
                    radius: 4
                    color: "transparent"

                    EnergyFill {
                        visible: row.current
                        anchors.fill: parent
                        radius: parent.radius
                        alpha: 0.3
                    }
                    Rectangle {
                        visible: row.current
                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: parent.height - 12
                        radius: 2
                        color: Theme.accent
                    }

                    // workspace chip, fixed width so titles line up
                    Text {
                        id: wsChip
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 110
                        text: root.wsLabel(row.modelData)
                        elide: Text.ElideRight
                        color: Theme.accent
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        id: titleText
                        anchors.left: wsChip.right
                        anchors.leftMargin: 10
                        anchors.right: classText.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.title || "(untitled)"
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        id: classText
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 200)
                        text: row.modelData.class
                        elide: Text.ElideLeft
                        color: Theme.subtext
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSize - 2
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.mode !== "close"
                        hoverEnabled: true
                        onEntered: list.currentIndex = row.index
                        onClicked: root.focusClient(row.modelData)
                    }
                }
            }
        }
    }
}
