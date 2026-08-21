import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Multi-mode launcher (rofi parity): combi (apps + run fallback), drun, run, files, emoji, glyphs, icons, wallpaper.
PanelWindow {
    id: root
    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-launcher"
    // true fullscreen (don't shrink below the bar's exclusive zone) — the connector fan
    // assumes window coords == screen coords
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property string mode: "combi" // combi | drun | run | files | emoji | glyphs | icons | wallpaper
    property string query: ""
    property string folder: Quickshell.env("HOME")
    property var results: []
    // reactive effective mode (for the tab row/placeholder); mirrors effectiveMode()
    readonly property string activeMode: query.startsWith(">") ? "run" : (query.startsWith("/") || query.startsWith("~")) ? "files" : query.startsWith(":") ? "emoji" : query.startsWith(";") ? "glyphs" : query.startsWith("#") ? "icons" : query.startsWith("!") ? "wallpaper" : mode

    // The modes, in tab order, each with the query prefix that also selects it. One list drives
    // the tab row, Tab cycling, and the prefix stripping in selectMode() — they cannot drift.
    readonly property var modes: [
        {
            name: "combi",
            chord: ""
        },
        // drun has no prefix and the old cycle order skipped it, but `launcher show drun` is a
        // live IPC entry point (Launcher.sh passes it), so it needs a tab or it lights nothing
        {
            name: "drun",
            chord: ""
        },
        {
            name: "run",
            chord: ">"
        },
        {
            name: "files",
            chord: "/"
        },
        {
            name: "emoji",
            chord: ":"
        },
        {
            name: "glyphs",
            chord: ";"
        },
        {
            name: "icons",
            chord: "#"
        },
        {
            name: "wallpaper",
            chord: "!"
        }
    ]
    // every character that steers activeMode from the front of the query ("~" is files, as above)
    readonly property string modePrefixes: ">/~:;#!"

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
    // Select a mode by name. A typed prefix outranks `mode` in activeMode, so a tab click has to
    // drop the prefix as well — otherwise clicking "files" while the query reads ":smile" would
    // leave the launcher in emoji mode with the files tab lit.
    function selectMode(m) {
        const t = input.text;
        if (t.length && modePrefixes.indexOf(t.charAt(0)) >= 0)
            input.text = t.slice(1);   // onTextChanged re-syncs query and refreshes
        mode = m;
        refresh();
    }
    function cycleMode(dir) {
        const step = dir || 1;
        const names = modes.map(m => m.name);
        // cycle from what's actually showing, so Tab continues from a prefix-selected mode
        const at = names.indexOf(activeMode);
        selectMode(names[((at < 0 ? 0 : at) + step + names.length) % names.length]);
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
        if (q.startsWith(">") || q.startsWith("/") || q.startsWith("~") || q.startsWith(":") || q.startsWith(";") || q.startsWith("#") || q.startsWith("!"))
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
        if (query.startsWith("!"))
            return "wallpaper";
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

    // ---- wallpaper data (scripts/list-wallpapers.sh: name\tpath\tpreview) ----
    // previews are static images (gif/video first frames come from the same caches the
    // rofi menu uses; the script generates missing ones, so the first scan can be slow)
    property var wallpaperData: []
    Process {
        id: wallpaperProc
        command: [Quickshell.env("HOME") + "/.config/quickshell/scripts/list-wallpapers.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = [];
                for (const line of this.text.split("\n")) {
                    const parts = line.split("\t");
                    if (parts.length < 3 || !parts[0].length)
                        continue;
                    out.push({
                        n: parts[0],
                        p: parts[1],
                        v: parts[2]
                    });
                }
                root.wallpaperData = out;
                root.refresh();
            }
        }
    }
    function loadWallpapers() {
        if (!root.wallpaperData.length && !wallpaperProc.running)
            wallpaperProc.running = true;
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

        if (m === "wallpaper") {
            if (!root.wallpaperData.length) {
                loadWallpapers(); // async; re-runs refresh when loaded
            } else {
                // ". random" first row (rofi parity) — resolved to a concrete file on activate
                if (!q.length)
                    out.push({
                        kind: "wallpaper",
                        label: ". random",
                        sub: "pick one at random",
                        icon: "",
                        path: "",
                        preview: "",
                        random: true
                    });
                for (const wp of root.wallpaperData) {
                    if (q.length && wp.n.toLowerCase().indexOf(q) < 0)
                        continue;
                    out.push({
                        kind: "wallpaper",
                        label: wp.n,
                        sub: wp.p,
                        icon: "",
                        path: wp.p,
                        preview: wp.v,
                        random: false
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

    // ---- selection history ----
    // The stable identity of a row, which is what LauncherStore keys on — NEVER the display
    // label, which is user-visible, localised, and changes under us. Empty means "this row has
    // no history": a directory (navigation is not a selection) and the `. random` wallpaper row,
    // which has nothing to record until it has picked a file.
    function selectionKey(item) {
        if (!item)
            return "";
        if (item.kind === "app")
            return (item.entry && item.entry.id) ? item.entry.id : "";
        if (item.kind === "run")
            return item.cmd || "";
        if (item.kind === "file")
            return item.isDir ? "" : (item.path || "");
        if (item.kind === "emoji" || item.kind === "glyph")
            return item.char || "";
        if (item.kind === "icon")
            return item.label || "";
        if (item.kind === "wallpaper")
            return item.random ? "" : (item.path || "");
        return "";
    }

    // Which kind of selection the active tab is about. The empty-query pin is per KIND, so this
    // is what decides that opening emoji pins the last emoji rather than the last app. Every tab
    // maps onto exactly one kind, which is why the store needs no `mode` column.
    function activeKind() {
        const m = effectiveMode();
        if (m === "combi" || m === "drun")
            return "app";
        if (m === "glyphs")
            return "glyph";
        if (m === "icons")
            return "icon";
        if (m === "files")
            return "file";
        return m; // run | emoji | wallpaper
    }

    // ---- activation ----
    function activate(item) {
        if (!item)
            return;
        if (item.kind === "app") {
            // The desktop-entry id, not the name: the name is localised and user-visible.
            LauncherStore.record("app", root.selectionKey(item), item.label);
            item.entry.execute();
            close();
        } else if (item.kind === "run") {
            LauncherStore.record("run", item.cmd, item.label);
            Quickshell.execDetached(["sh", "-lc", item.cmd]);
            close();
        } else if (item.kind === "file") {
            if (item.isDir) {
                // Directory navigation is deliberately NOT a selection, and a file does not
                // boost its parent directory either — this stays as unrecorded as it is today.
                root.folder = item.path;
                query = "";
                input.text = "";
                Qt.callLater(refresh);
            } else {
                LauncherStore.record("file", item.path, item.label);
                Quickshell.execDetached(["xdg-open", item.path]);
                close();
            }
        } else if (item.kind === "emoji" || item.kind === "glyph") {
            LauncherStore.record(item.kind, item.char, item.label);
            Quickshell.execDetached(["wl-copy", item.char]);
            close();
        } else if (item.kind === "icon") {
            // the icon NAME is the identity — it is also what gets copied
            LauncherStore.record("icon", item.label, item.label);
            Quickshell.execDetached(["wl-copy", item.label]);
            close();
        } else if (item.kind === "wallpaper") {
            // full path straight to the apply seam — no basename re-find (lossy)
            let target = item.path;
            if (item.random && root.wallpaperData.length)
                target = root.wallpaperData[Math.floor(Math.random() * root.wallpaperData.length)].p;
            if (target.length)
                Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/WallpaperApply.sh", target]);
            close();
        }
    }

    // ---- click-away to close ----
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // three energy lines fanning from the bar sections into the box;
    // the box materializes only once the fan has landed
    ConnectorFan {
        id: fan
        box: box
        active: root.visible
    }

    // water-mirror reflection under the box
    Reflection {
        sourceItem: box
        anchors.top: box.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: box.horizontalCenter
        opacity: box.opacity
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
        // materialize only once the connector fan has landed
        opacity: fan.landed ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }

        // animated energy border tracing the box (replaces the static stroke)
        EnergyBorder {
            anchors.fill: parent
            radius: parent.radius
            thickness: Theme.borderThickness
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

            // mode tabs — rofi's mode-switcher row, which the quickshell launcher never carried
            // over. Click or Tab; the lit tab is activeMode, so a typed prefix moves it too.
            Row {
                id: tabRow
                width: parent.width
                height: 26
                spacing: 4

                Repeater {
                    model: root.modes

                    Rectangle {
                        readonly property bool current: modelData.name === root.activeMode
                        width: tabText.implicitWidth + 18
                        height: parent.height
                        radius: 4
                        color: current ? "transparent" : (tabMa.containsMouse ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : "transparent")

                        // the current tab wears the plasma fill the mode chip used to
                        EnergyFill {
                            anchors.fill: parent
                            radius: parent.radius
                            visible: parent.current
                        }

                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData.chord.length ? modelData.name + "  " + modelData.chord : modelData.name
                            color: parent.current ? Theme.fg : Theme.subtext
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: parent.current
                        }

                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectMode(modelData.name);
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }

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

                // (the mode chip lived here; the tab row above states the mode now)

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
                    anchors.left: parent.left
                    anchors.right: countText.left
                    anchors.leftMargin: 12
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
                                    : root.activeMode === "wallpaper"
                                        ? "Search wallpapers  ·  Enter applies"
                                        : "Search apps  ·  Tab switches mode"   // the prefixes are on the tabs now
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
                            root.cycleMode(1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Backtab) {
                            root.cycleMode(-1);
                            e.accepted = true;
                        }
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                // derived from the siblings, so adding/resizing a header row can't strand the list
                height: parent.height - tabRow.height - header.height - parent.spacing * 2
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
                    readonly property bool isWallpaper: modelData.kind === "wallpaper"
                    width: list.width
                    // wallpaper rows are tall enough for a readable thumbnail
                    height: isWallpaper ? 90 : 44
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

                        // icon: themed app icon, wallpaper thumbnail, else a mono glyph per kind
                        Item {
                            id: iconBox
                            width: del.isWallpaper ? 140 : 28
                            height: del.isWallpaper ? 78 : 28
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                id: appIcon
                                anchors.fill: parent
                                visible: source != ""
                                source: (modelData.kind === "app" && modelData.icon)
                                    ? Quickshell.iconPath(modelData.icon, true)
                                    : modelData.kind === "icon"
                                        ? "file://" + modelData.path
                                        : (del.isWallpaper && modelData.preview.length)
                                            ? "file://" + modelData.preview
                                            : ""
                                sourceSize.width: del.isWallpaper ? 280 : 28
                                sourceSize.height: del.isWallpaper ? 156 : 28
                                fillMode: del.isWallpaper ? Image.PreserveAspectCrop : Image.PreserveAspectFit
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
                                        : del.isWallpaper
                                            ? "󰒿" // shuffle — the random row has no preview
                                            : "" // app fallback
                                color: Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: (modelData.kind === "emoji" || modelData.kind === "glyph") ? 22 : del.isWallpaper ? 30 : 18
                            }
                        }

                        Column {
                            width: parent.width - iconBox.width - 10
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
