import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Multi-mode launcher (rofi parity): combi (apps + run fallback), drun, run, files, emoji, glyphs, icons.
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

    property string mode: "combi" // combi | drun | run | files | emoji | glyphs | icons
    property string query: ""
    property string folder: Quickshell.env("HOME")
    property var results: []
    // reactive effective mode (for the UI chip/placeholder); mirrors effectiveMode()
    readonly property string activeMode: query.startsWith(">") ? "run" : (query.startsWith("/") || query.startsWith("~")) ? "files" : query.startsWith(":") ? "emoji" : query.startsWith(";") ? "glyphs" : query.startsWith("#") ? "icons" : mode

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
        const order = ["combi", "run", "files", "emoji", "glyphs", "icons"];
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
        if (q.startsWith(">") || q.startsWith("/") || q.startsWith("~") || q.startsWith(":") || q.startsWith(";") || q.startsWith("#"))
            return q.slice(1).trim();
        return q.trim();
    }
    function effectiveMode() {
        if (query.startsWith(">"))
            return "run";
        if (query.startsWith("/") || query.startsWith("~"))
            return "files";
        if (query.startsWith(":"))
            return "emoji";
        if (query.startsWith(";"))
            return "glyphs";
        if (query.startsWith("#"))
            return "icons";
        return mode;
    }

    // ---- emoji data (config/emoji.json, generated from rofimoji's character data) ----
    // loaded lazily on first emoji refresh (Qt blocks XMLHttpRequest file reads, so FileView);
    // entries: { e: char, n: name, k: keywords, g: group }
    property var emojiData: []
    FileView {
        id: emojiFile
        onLoaded: {
            try {
                root.emojiData = JSON.parse(text());
            } catch (e) {
                root.emojiData = [];
            }
            root.refresh();
        }
    }
    function loadEmoji() {
        if (!emojiFile.path || !emojiFile.path.toString().length)
            emojiFile.path = Quickshell.env("HOME") + "/.config/quickshell/config/emoji.json";
    }

    // ---- glyph data (config/glyphs.json: curated unicode blocks + nerd-font PUA) ----
    // same shape and lazy-load pattern as emoji.json (see scripts/gen-glyph-data.py)
    property var glyphData: []
    FileView {
        id: glyphFile
        onLoaded: {
            try {
                root.glyphData = JSON.parse(text());
            } catch (e) {
                root.glyphData = [];
            }
            root.refresh();
        }
    }
    function loadGlyphs() {
        if (!glyphFile.path || !glyphFile.path.toString().length)
            glyphFile.path = Quickshell.env("HOME") + "/.config/quickshell/config/glyphs.json";
    }

    // ---- icon data (theme icons, scanned by scripts/list-icons.sh) ----
    // entries: { n: icon name, p: file path }; lazy like the JSON pickers
    property var iconData: []
    Process {
        id: iconProc
        command: [Quickshell.env("HOME") + "/.config/quickshell/scripts/list-icons.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = [];
                for (const line of this.text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 1)
                        continue;
                    out.push({
                        n: line.slice(0, tab),
                        p: line.slice(tab + 1)
                    });
                }
                root.iconData = out;
                root.refresh();
            }
        }
    }
    function loadIcons() {
        if (!root.iconData.length && !iconProc.running)
            iconProc.running = true;
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

        if (m === "emoji") {
            if (!root.emojiData.length) {
                loadEmoji(); // async; re-runs refresh when loaded
            } else {
                for (const em of root.emojiData) {
                    if (q.length && (em.n + " " + em.k).toLowerCase().indexOf(q) < 0)
                        continue;
                    out.push({
                        kind: "emoji",
                        label: em.n,
                        sub: em.g + (em.k.length ? " · " + em.k : ""),
                        icon: "",
                        char: em.e
                    });
                }
            }
        }

        if (m === "glyphs") {
            if (!root.glyphData.length) {
                loadGlyphs(); // async; re-runs refresh when loaded
            } else {
                for (const gl of root.glyphData) {
                    // group is searchable too ("nerd md", "math", ...)
                    if (q.length && (gl.n + " " + gl.k + " " + gl.g).toLowerCase().indexOf(q) < 0)
                        continue;
                    out.push({
                        kind: "glyph",
                        label: gl.n,
                        sub: gl.g + (gl.k.length ? " · " + gl.k : ""),
                        icon: "",
                        char: gl.e
                    });
                }
            }
        }

        if (m === "icons") {
            if (!root.iconData.length) {
                loadIcons(); // async; re-runs refresh when loaded
            } else {
                for (const ic of root.iconData) {
                    if (q.length && ic.n.toLowerCase().indexOf(q) < 0)
                        continue;
                    out.push({
                        kind: "icon",
                        label: ic.n,
                        sub: ic.p,
                        icon: "",
                        path: ic.p
                    });
                }
            }
        }

        root.results = out;
        list.currentIndex = out.length ? root.nextSelectable(-1, 1) : -1;
    }

    // Flat list: navigation is a plain clamp, no skipping.
    function nextSelectable(idx, dir) {
        if (!root.results.length)
            return idx;
        return Math.min(Math.max(idx + dir, 0), root.results.length - 1);
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
        } else if (item.kind === "emoji" || item.kind === "glyph") {
            Quickshell.execDetached(["wl-copy", item.char]);
            close();
        } else if (item.kind === "icon") {
            Quickshell.execDetached(["wl-copy", item.label]);
            close();
        }
    }

    // ---- click-away to close ----
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // water-mirror reflection under the box
    Reflection {
        sourceItem: box
        anchors.top: box.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: box.horizontalCenter
        z: 1
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
            thickness: 2.75
            energy: 0.7
        }

        // cursor-lit glimmer over the box
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
                        // translucent plasma fill behind → light text
                        color: Theme.fg
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
                        : root.activeMode === "emoji"
                            ? "Search emoji  ·  Enter copies to clipboard"
                            : root.activeMode === "glyphs"
                                ? "Search glyphs  ·  Enter copies to clipboard"
                                : root.activeMode === "icons"
                                    ? "Search icons  ·  Enter copies icon name"
                                    : "Search apps  ·  > run  ·  / files  ·  : emoji  ·  ; glyphs  ·  # icons"
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
                            list.currentIndex = root.nextSelectable(list.currentIndex, 1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.AltModifier))) {
                            list.currentIndex = root.nextSelectable(list.currentIndex, -1);
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
                // Up/Down set `currentIndex` directly, and a ListView only auto-scrolls for keys
                // it handles itself — without this the selection walks off the viewport and the
                // visible window never catches up (same fix as KeymapOverlay and ClipboardDialog).
                onCurrentIndexChanged: if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Rectangle {
                    id: del
                    readonly property bool current: ListView.isCurrentItem
                    width: list.width
                    height: 44
                    color: "transparent"
                    radius: 4

                    // animated lava fill on the selected row — subtle: it's a selector,
                    // not a status indicator, so keep it translucent under the row content
                    EnergyFill {
                        visible: del.current
                        anchors.fill: parent
                        radius: parent.radius
                        alpha: 0.3
                    }

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
                                    : modelData.kind === "icon"
                                        ? "file://" + modelData.path
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
                                text: (modelData.kind === "emoji" || modelData.kind === "glyph")
                                    ? modelData.char
                                    : modelData.kind === "run"
                                    ? "" // terminal
                                    : modelData.kind === "file"
                                        ? (modelData.isDir ? "" : "") // folder / file
                                        : "" // app fallback
                                color: Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: (modelData.kind === "emoji" || modelData.kind === "glyph") ? 22 : 18
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
                        // headers are clickable too now: activate() toggles their fold
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
