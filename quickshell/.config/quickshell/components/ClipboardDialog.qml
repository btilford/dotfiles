import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Standalone clipboard-history dialog (clipvault), parity target for the old
// Launcher clip mode. Fullscreen overlay on the focused monitor, own IPC socket
// connections (list/search + live-update subscribe), driven by the Clipboard
// singleton. v2 (this pass): search + flat list + preview pane (get on
// selection change, id-tagged against late responses) + Enter-to-copy. Tree
// mode, actions/pin/delete parity, Launcher strip land in later passes.
PanelWindow {
    id: root
    visible: Clipboard.shown
    color: "transparent"
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-clipboard"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property string query: ""
    property var results: []

    onVisibleChanged: if (visible) {
        query = "";
        input.text = "";
        results = [];
        input.forceActiveFocus();
        runQuery();
    }

    // ---- ipc socket layer (ported from Launcher.qml's clip* members, prefix dropped) ----
    // socket: request/response channel, one in-flight request at a time, FIFO queue of
    // "what kind of request is this" correlates responses (they arrive in request order).
    // eventsSocket: subscribes once, gets a push line on every daemon db change -> requery.
    property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/clipvault.sock"
    property var data: []
    // FIFO of {kind, id?} descriptors — responses arrive in request order, so this
    // correlates them; "get" descriptors carry the requested id for stale-drop below.
    property var reqQueue: []

    Timer {
        id: debounce
        interval: 120
        repeat: false
        onTriggered: root.runQuery()
    }

    Socket {
        id: socket
        path: root.socketPath
        connected: root.visible
        onError: error => console.log("clipvault: ipc socket error (is the daemon running?)", error)
        parser: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const desc = root.reqQueue.length ? root.reqQueue.shift() : {
                    kind: ""
                };
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (desc.kind === "list") {
                    root.data = msg.entries || [];
                    root.rebuild();
                } else if (desc.kind === "get") {
                    // late response after selection moved on — drop it
                    if (desc.id !== root.selectedId)
                        return;
                    root.previewEntry = msg.entry || null;
                    root.previewForId = desc.id;
                }
                // act/pin/delete/copy: fire-and-forget acks; eventsSocket triggers
                // the requery once the mutation actually lands
            }
        }
    }
    function sendReq(desc, req) {
        root.reqQueue.push(desc);
        socket.write(JSON.stringify(req) + "\n");
        socket.flush();
    }
    function runQuery() {
        const q = root.query.trim();
        sendReq({
            kind: "list"
        }, {
            op: "list",
            query: q.length ? q : undefined,
            limit: 100
        });
    }
    function action(req) {
        sendReq({
            kind: req.op
        }, req);
    }

    // ---- preview pane: debounced `get` on selection change, id-tagged against
    // late responses (a slow response for a since-abandoned selection is dropped
    // in the socket handler above rather than flashing the wrong content). ----
    readonly property int selectedId: (list.currentIndex >= 0 && root.results[list.currentIndex]) ? root.results[list.currentIndex].id : -1
    property var previewEntry: null
    property int previewForId: -1
    onSelectedIdChanged: previewDebounce.restart()
    Timer {
        id: previewDebounce
        interval: 80
        repeat: false
        onTriggered: {
            if (root.selectedId < 0) {
                root.previewEntry = null;
                root.previewForId = -1;
                return;
            }
            root.sendReq({
                kind: "get",
                id: root.selectedId
            }, {
                op: "get",
                id: root.selectedId
            });
        }
    }
    function fmtTs(secs) {
        if (!secs)
            return "?";
        return new Date(secs * 1000).toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm");
    }
    function pinDesc(e) {
        if (!e)
            return "";
        if (e.pin_mode === "until")
            return "until (" + root.fmtTs(e.expires_at) + ")";
        return e.pin_mode || "none";
    }

    Socket {
        id: eventsSocket
        path: root.socketPath
        connected: root.visible
        onError: error => console.log("clipvault: ipc events socket error", error)
        parser: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (root.visible)
                    root.runQuery();
            }
        }
        onConnectedChanged: {
            if (connected) {
                write(JSON.stringify({
                    op: "subscribe"
                }) + "\n");
                flush();
            }
        }
    }

    // ---- row shaping + selection preservation across a requery ----
    function pinBadge(pinMode) {
        switch (pinMode) {
        case "forever": return "📌";
        case "until": return "⏳";
        case "session": return "🕐";
        default: return "";
        }
    }
    function itemRow(c) {
        const pinMode = c.pin_mode || "none";
        const badge = root.pinBadge(pinMode);
        return {
            id: c.id,
            label: c.preview,
            sub: (badge.length ? badge + "  " : "") + c.category + (c.use_count > 1 ? "  ·  x" + c.use_count : ""),
            category: c.category
        };
    }
    function rebuild() {
        const prevId = root.results[list.currentIndex] ? root.results[list.currentIndex].id : -1;
        const out = root.data.map(root.itemRow);
        root.results = out;
        const idx = prevId >= 0 ? out.findIndex(r => r.id === prevId) : -1;
        list.currentIndex = idx >= 0 ? idx : (out.length ? 0 : -1);
    }

    // ---- click-away to close ----
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: root.visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animMed
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: Clipboard.close()
        }
    }

    Reflection {
        sourceItem: box
        anchors.top: box.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: box.horizontalCenter
        z: 1
    }

    Rectangle {
        id: box
        width: parent.width * 0.72
        height: parent.height * 0.78
        anchors.centerIn: parent
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.surfaceOpacity)

        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: 2.75
            energy: 0.7
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
                    color: Theme.accent
                }

                Text {
                    id: countText
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.results.length + (root.results.length === 1 ? " result" : " results")
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 2
                }

                TextField {
                    id: input
                    anchors.left: parent.left
                    anchors.right: countText.left
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "Search clipboard history  ·  Enter copies  ·  Esc closes"
                    color: Theme.fg
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize
                    background: Rectangle {
                        color: "transparent"
                    }
                    onTextChanged: {
                        root.query = text;
                        debounce.restart();
                    }
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Escape) {
                            Clipboard.close();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier))) {
                            list.currentIndex = Math.min(list.currentIndex + 1, root.results.length - 1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier))) {
                            list.currentIndex = Math.max(list.currentIndex - 1, 0);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            const item = root.results[list.currentIndex];
                            if (item) {
                                root.action({
                                    op: "copy",
                                    id: item.id
                                });
                                Clipboard.close();
                            }
                            e.accepted = true;
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: parent.height - 58
                spacing: Theme.pad

                ListView {
                    id: list
                    width: parent.width * 0.58 - Theme.pad / 2
                    height: parent.height
                    clip: true
                    model: root.results
                    currentIndex: 0
                    delegate: Rectangle {
                        id: del
                        readonly property bool current: ListView.isCurrentItem
                        width: list.width
                        height: 44
                        color: "transparent"
                        radius: 4

                        EnergyFill {
                            visible: del.current
                            anchors.fill: parent
                            radius: parent.radius
                            alpha: 0.3
                        }

                        Rectangle {
                            visible: del.current
                            anchors.left: parent.left
                            anchors.leftMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: parent.height - 12
                            radius: 2
                            color: Theme.accent
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 14
                            anchors.rightMargin: 8
                            Text {
                                text: modelData.label
                                color: Theme.fg
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fontSize
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: modelData.sub
                                visible: modelData.sub.length > 0
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fontSize - 2
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                list.currentIndex = index;
                                root.action({
                                    op: "copy",
                                    id: modelData.id
                                });
                                Clipboard.close();
                            }
                        }
                    }
                }

                // ---- preview pane ----
                Rectangle {
                    id: previewPane
                    width: parent.width * 0.42 - Theme.pad / 2
                    height: parent.height
                    radius: Theme.radius
                    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.4)
                    clip: true

                    readonly property var entry: (root.previewEntry && root.previewForId === root.selectedId) ? root.previewEntry : null
                    readonly property bool isImage: previewPane.entry && previewPane.entry.kind === "image"

                    Text {
                        visible: !previewPane.entry
                        anchors.centerIn: parent
                        text: root.selectedId < 0 ? "(no entry selected)" : "loading…"
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize
                    }

                    Column {
                        visible: !!previewPane.entry
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: Theme.pad

                        // header block: same fields as the TUI's draw_detail
                        Column {
                            width: parent.width
                            spacing: 2
                            Text {
                                width: parent.width
                                text: previewPane.entry ? ("id: " + previewPane.entry.id + "  kind: " + previewPane.entry.kind + "  category: " + previewPane.entry.category) : ""
                                color: Theme.fg
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 2
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: previewPane.entry ? ("app: " + (previewPane.entry.app_class || "(unknown)")) : ""
                                color: Theme.subtext
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 2
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: previewPane.entry ? ("title: " + (previewPane.entry.window_title || "(none)")) : ""
                                color: Theme.subtext
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 2
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: previewPane.entry ? ("source: " + previewPane.entry.source + "  pin: " + root.pinDesc(previewPane.entry)) : ""
                                color: Theme.subtext
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 2
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: previewPane.entry ? ("created: " + root.fmtTs(previewPane.entry.created_at) + "  used: " + root.fmtTs(previewPane.entry.last_used_at) + " (x" + previewPane.entry.use_count + ")") : ""
                                color: Theme.subtext
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 2
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                        }

                        // image content: fall back to the path as text if the file's gone
                        Image {
                            id: previewImage
                            visible: previewPane.isImage && status !== Image.Error
                            width: parent.width
                            height: parent.height - y
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            source: previewPane.isImage && previewPane.entry.image_path ? ("file://" + previewPane.entry.image_path) : ""
                        }
                        Text {
                            visible: previewPane.isImage && previewImage.status === Image.Error
                            width: parent.width
                            text: previewPane.entry ? ("(image missing: " + previewPane.entry.image_path + ")") : ""
                            color: Theme.subtext
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSize - 2
                            wrapMode: Text.WrapAnywhere
                        }

                        // text content: read-only, capped at ~100KB — entries up to 1MB
                        // choke QML's text layout, so this trims rather than trying to
                        // render the whole thing. No syntax highlighting v1.
                        Flickable {
                            visible: !previewPane.isImage
                            width: parent.width
                            height: parent.height - y
                            clip: true
                            contentWidth: width
                            contentHeight: previewText.implicitHeight
                            TextEdit {
                                id: previewText
                                width: parent.width
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                color: Theme.fg
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 1
                                text: {
                                    const e = previewPane.entry;
                                    if (!e || !e.content)
                                        return "";
                                    const cap = 100000;
                                    return e.content.length > cap ? e.content.slice(0, cap) + "\n… (truncated)" : e.content;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
