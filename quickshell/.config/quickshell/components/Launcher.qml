import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Multi-mode launcher (rofi parity): combi (apps + run fallback), drun, run, files.
PanelWindow {
    id: root
    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-launcher"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property string mode: "combi" // combi | drun | run | files
    property string query: ""
    property string folder: Quickshell.env("HOME")
    property var results: []
    // reactive effective mode (for the UI chip/placeholder); mirrors effectiveMode()
    readonly property string activeMode: query.startsWith(">") ? "run" : (query.startsWith("/") || query.startsWith("~")) ? "files" : mode

    // ---- lifecycle ----
    function open(m) {
        mode = (m && m.length) ? m : "combi";
        query = "";
        folder = Quickshell.env("HOME");
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen)
            root.screen = Hyprland.focusedMonitor.screen;
        input.text = "";
        visible = true;
        refresh();
        input.forceActiveFocus();
    }
    function close() {
        visible = false;
    }
    function toggle(m) {
        if (visible)
            close();
        else
            open(m);
    }
    function cycleMode() {
        const order = ["combi", "run", "files"];
        mode = order[(order.indexOf(mode) + 1) % order.length];
        refresh();
    }

    // ---- $PATH binaries (for run mode), collected once ----
    property var pathBins: []
    Process {
        id: pathProc
        command: ["bash", "-lc", "compgen -c | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: root.pathBins = this.text.split("\n").filter(s => s.length)
        }
    }
    Component.onCompleted: pathProc.running = true

    // ---- effective query (strip mode prefix) ----
    function effectiveQuery() {
        let q = query;
        if (q.startsWith(">") || q.startsWith("/") || q.startsWith("~"))
            return q.slice(1).trim();
        return q.trim();
    }
    function effectiveMode() {
        if (query.startsWith(">"))
            return "run";
        if (query.startsWith("/") || query.startsWith("~"))
            return "files";
        return mode;
    }

    // ---- build results ----
    function refresh() {
        const m = effectiveMode();
        const q = effectiveQuery().toLowerCase();
        let out = [];

        if (m === "combi" || m === "drun") {
            const apps = [...DesktopEntries.applications.values].filter(function (d) {
                if (!d.name)
                    return false;
                if (!q.length)
                    return true;
                const hay = (d.name + " " + (d.genericName || "") + " " + (d.comment || "")).toLowerCase();
                return hay.includes(q);
            }).sort((a, b) => a.name.localeCompare(b.name));
            for (const d of apps)
                out.push({
                    kind: "app",
                    label: d.name,
                    sub: d.genericName || d.comment || "",
                    icon: d.icon || "",
                    entry: d
                });
        }

        if (m === "run" || (m === "combi" && q.length)) {
            const bins = root.pathBins.filter(b => q.length ? b.toLowerCase().includes(q) : false).slice(0, 50);
            for (const b of bins)
                out.push({
                    kind: "run",
                    label: b,
                    sub: "run",
                    icon: "",
                    cmd: b
                });
            // freeform: always allow running exactly what was typed
            if (q.length && !bins.includes(effectiveQuery()))
                out.push({
                    kind: "run",
                    label: effectiveQuery(),
                    sub: "run command",
                    icon: "",
                    cmd: effectiveQuery()
                });
        }

        if (m === "files") {
            // handled by FolderListModel below; mirror into results for uniform nav
            out = fileResults();
        }

        root.results = out;
        list.currentIndex = out.length ? 0 : -1;
    }

    // ---- files mode ----
    FolderListModel {
        id: folderModel
        folder: "file://" + root.folder
        showDotAndDotDot: true
        showHidden: false
        sortField: FolderListModel.Type
    }
    function fileResults() {
        let out = [];
        const q = effectiveQuery().toLowerCase();
        for (let i = 0; i < folderModel.count; i++) {
            const name = folderModel.get(i, "fileName");
            const isDir = folderModel.get(i, "fileIsDir");
            const path = folderModel.get(i, "filePath");
            if (q.length && !name.toLowerCase().includes(q))
                continue;
            out.push({
                kind: "file",
                label: name,
                sub: path,
                icon: "",
                path: path,
                isDir: isDir
            });
        }
        return out;
    }

    // ---- activation ----
    function activate(item) {
        if (!item)
            return;
        if (item.kind === "app") {
            item.entry.execute();
            close();
        } else if (item.kind === "run") {
            Quickshell.execDetached(["sh", "-lc", item.cmd]);
            close();
        } else if (item.kind === "file") {
            if (item.isDir) {
                root.folder = item.path;
                query = "";
                input.text = "";
                Qt.callLater(refresh);
            } else {
                Quickshell.execDetached(["xdg-open", item.path]);
                close();
            }
        }
    }

    // ---- click-away to close ----
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // ---- the launcher box ----
    Rectangle {
        id: box
        width: 780
        height: 560
        anchors.centerIn: parent
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.surfaceOpacity)

        // animated energy border tracing the box (replaces the static stroke)
        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: 2.0
            energy: 0.7
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

                // accent underline
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

                // mode chip
                Rectangle {
                    id: chip
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24
                    width: chipText.implicitWidth + 16
                    radius: 4
                    color: "transparent"
                    // animated plasma fill (replaces the flat accent chip)
                    EnergyFill {
                        anchors.fill: parent
                        radius: parent.radius
                    }
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: root.activeMode
                        color: Theme.bg
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: true
                    }
                }

                // result count
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
                    anchors.left: chip.right
                    anchors.right: countText.left
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: root.activeMode === "files"
                        ? root.folder
                        : "Search apps  ·  > run  ·  / files"
                    color: Theme.fg
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize
                    background: Rectangle {
                        color: "transparent"
                    }
                    onTextChanged: {
                        root.query = text;
                        root.refresh();
                    }
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Escape) {
                            root.close();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier))) {
                            list.currentIndex = Math.min(list.currentIndex + 1, root.results.length - 1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier))) {
                            list.currentIndex = Math.max(list.currentIndex - 1, 0);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            root.activate(root.results[list.currentIndex]);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Tab) {
                            root.cycleMode();
                            e.accepted = true;
                        }
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 58
                clip: true
                model: root.results
                currentIndex: 0
                delegate: Rectangle {
                    id: del
                    readonly property bool current: ListView.isCurrentItem
                    width: list.width
                    height: 44
                    color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : "transparent"
                    radius: 4

                    // left accent bar on the selected row
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

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 10

                        // icon: themed app icon, else a mono glyph per kind
                        Item {
                            width: 28
                            height: 28
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                id: appIcon
                                anchors.fill: parent
                                visible: source != ""
                                source: (modelData.kind === "app" && modelData.icon)
                                    ? Quickshell.iconPath(modelData.icon, true)
                                    : ""
                                sourceSize.width: 28
                                sourceSize.height: 28
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !appIcon.visible
                                text: modelData.kind === "run"
                                    ? "" // terminal
                                    : modelData.kind === "file"
                                        ? (modelData.isDir ? "" : "") // folder / file
                                        : "" // app fallback
                                color: Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: 18
                            }
                        }

                        Column {
                            width: parent.width - 38
                            anchors.verticalCenter: parent.verticalCenter
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
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            list.currentIndex = index;
                            root.activate(modelData);
                        }
                    }
                }
            }
        }
    }
}
