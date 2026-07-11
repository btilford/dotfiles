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

    property string mode: "combi" // combi | drun | run | files | emoji | glyphs | icons | clip
    property string query: ""
    property string folder: Quickshell.env("HOME")
    property var results: []
    // reactive effective mode (for the UI chip/placeholder); mirrors effectiveMode()
    readonly property string activeMode: query.startsWith(">") ? "run" : (query.startsWith("/") || query.startsWith("~")) ? "files" : query.startsWith(":") ? "emoji" : query.startsWith(";") ? "glyphs" : query.startsWith("#") ? "icons" : query.startsWith(",") ? "clip" : mode

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
        if (effectiveMode() === "clip")
            clipDebounce.restart();
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
        const order = ["combi", "run", "files", "clip", "emoji", "glyphs", "icons"];
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
        if (q.startsWith(">") || q.startsWith("/") || q.startsWith("~") || q.startsWith(":") || q.startsWith(";") || q.startsWith("#") || q.startsWith(","))
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
        if (query.startsWith(","))
            return "clip";
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

    // ---- clip data (clipvault clipboard history, via the daemon's ipc socket) ----
    // Two persistent Unix-socket connections instead of spawning a `clipvault`
    // process per query: `clipSocket` is a request/response channel (one
    // in-flight request at a time, responses arrive in request order so a
    // simple FIFO queue of "what kind of request is this" correlates them);
    // `clipEventsSocket` subscribes once and gets a push line every time the
    // daemon's db changes, so the list refreshes on new captures without
    // polling. Falls back to nothing gracefully if the daemon/socket isn't
    // up — clip mode just stays empty rather than erroring.
    property string clipSocketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/clipvault.sock"
    property var clipData: []
    property var clipReqQueue: []
    // Tree mode (app -> window -> item, Ctrl+T toggles): server-side group_by:"app"
    // clusters entries so headers are built in one pass; fold state is a plain
    // JS object keyed by app_class ("") or "app_class|||window_title" (window).
    property bool clipTreeMode: false
    property var clipCollapsed: ({})
    // Bulk-delete submode (Ctrl+Shift+X): freezes text input (mirrors clipActionsOpen),
    // Space toggles selection, Enter opens a confirm popup before the actual delete.
    property bool clipBulkMode: false
    property var clipBulkSelected: ({})
    property bool clipBulkConfirmOpen: false
    property var clipBulkConfirmIds: []
    // Pin-mode picker (Alt+P): none/session/until/forever; "until" chains into a
    // duration-entry overlay instead of firing immediately.
    readonly property var clipPinModes: ["none", "session", "until", "forever"]
    property bool clipPinPickerOpen: false
    property int clipPinPickerIndex: 0
    property var clipPinPickerFor: null
    property bool clipPinDurationOpen: false
    property int clipPinDurationFor: -1
    property string clipPinDurationBuf: ""
    Timer {
        id: clipDebounce
        interval: 120
        repeat: false
        onTriggered: root.runClipQuery()
    }
    Socket {
        id: clipSocket
        path: root.clipSocketPath
        connected: true
        onError: error => console.log("clipvault: ipc socket error (is the daemon running?)", error)
        parser: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                const kind = root.clipReqQueue.length ? root.clipReqQueue.shift() : "";
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (kind === "list") {
                    root.clipData = msg.entries || [];
                    root.refresh();
                } else if (kind === "actions") {
                    root.clipActionsList = msg.actions || [];
                    root.clipActionsIndex = 0;
                    root.clipActionsOpen = root.clipActionsList.length > 0;
                }
                // act/pin/delete/copy: fire-and-forget acks; clipEventsSocket
                // triggers the requery once the mutation actually lands
            }
        }
    }
    function clipSend(kind, req) {
        root.clipReqQueue.push(kind);
        clipSocket.write(JSON.stringify(req) + "\n");
        clipSocket.flush();
    }
    function runClipQuery() {
        const q = effectiveQuery();
        clipSend("list", {
            op: "list",
            query: q.length ? q : undefined,
            limit: 100,
            group_by: root.clipTreeMode ? "app" : undefined
        });
    }
    function clipAction(req) {
        clipSend(req.op, req);
    }

    Socket {
        id: clipEventsSocket
        path: root.clipSocketPath
        connected: true
        onError: error => console.log("clipvault: ipc events socket error", error)
        parser: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                // every line on this socket (the subscribe ack, and every
                // subsequent "changed" push) is a cue to requery if clip
                // mode is on screen
                if (root.visible && root.activeMode === "clip")
                    root.runClipQuery();
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

    // ---- clip action sub-list (open in browser, edit, tmux, curl, ...) ----
    // `{"op":"actions","id":N}` -> [{id, label}]; picking one sends
    // `{"op":"act","id":N,"action":"..."}` and closes the launcher, same as Enter.
    property var clipActionsList: []
    property int clipActionsIndex: 0
    property bool clipActionsOpen: false
    property int clipActionsForId: -1
    function openClipActions(id) {
        clipActionsForId = id;
        clipSend("actions", {
            op: "actions",
            id: id
        });
    }
    function closeClipActions() {
        clipActionsOpen = false;
        clipActionsList = [];
    }
    function runClipAction(actionId) {
        root.clipAction({
            op: "act",
            id: clipActionsForId,
            action: actionId
        });
        closeClipActions();
        root.close();
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

        if (m === "clip") {
            // Note: the server requery itself is NOT triggered here — it used to be
            // (clipDebounce.restart() on every refresh()), which self-perpetuated
            // forever (query response -> refresh() -> restart debounce -> query ...)
            // and stomped the selection back to row 0 on every ~120ms pass. The
            // requery is now driven only by actual query-changing events: typing
            // (input.onTextChanged), entering clip mode (open()), a tree-mode
            // toggle, and clipEventsSocket's "changed" push.
            if (root.clipTreeMode) {
                let prevApp = null;
                let prevWin = null;
                for (const c of root.clipData) {
                    const appKey = c.app_class || "";
                    if (appKey !== prevApp) {
                        out.push({
                            kind: "clip-header-app",
                            key: appKey,
                            label: c.app_class ? c.app_class : "(unknown app)",
                            collapsed: !!root.clipCollapsed[appKey]
                        });
                        prevApp = appKey;
                        prevWin = null;
                    }
                    if (root.clipCollapsed[appKey])
                        continue;
                    const winKey = appKey + "|||" + (c.window_title || "");
                    if (winKey !== prevWin) {
                        out.push({
                            kind: "clip-header-window",
                            key: winKey,
                            label: c.window_title ? c.window_title : "(no title)",
                            collapsed: !!root.clipCollapsed[winKey]
                        });
                        prevWin = winKey;
                    }
                    if (root.clipCollapsed[winKey])
                        continue;
                    out.push(root.clipItemRow(c));
                }
            } else {
                for (const c of root.clipData)
                    out.push(root.clipItemRow(c));
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

        // In clip mode, preserve the current selection across a data refresh
        // (typing a requery response, or an clipEventsSocket "changed" push)
        // instead of always snapping back to row 0 — that snap-back is what
        // made clip mode feel "stuck on the first item".
        const prevItem = root.results[list.currentIndex];
        root.results = out;
        if (m === "clip" && prevItem) {
            const key = prevItem.kind === "clip" ? "id:" + prevItem.id : prevItem.kind.startsWith("clip-header") ? "key:" + prevItem.key : null;
            const idx = key ? out.findIndex(r => (r.kind === "clip" ? "id:" + r.id : r.kind.startsWith("clip-header") ? "key:" + r.key : null) === key) : -1;
            list.currentIndex = idx >= 0 ? idx : (out.length ? root.nextSelectable(-1, 1) : -1);
        } else {
            list.currentIndex = out.length ? root.nextSelectable(-1, 1) : -1;
        }
    }

    // Flat mode has no headers at all now; tree mode's headers are real,
    // selectable rows (so hjkl-equivalents can collapse/expand "the node at
    // the cursor") — so navigation is just a plain clamp, no skipping.
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

    // ---- clip mode helpers ----
    function clipGlyph(category) {
        switch (category) {
        case "url": return "";
        case "color": return "";
        case "email": return "";
        case "file-path": return "";
        case "code": return "";
        case "files": return "";
        case "image": return "";
        default: return "";
        }
    }

    // Plain emoji badge for the pin mode (kept distinct from the nerd-font
    // category glyph above, which stays category-only now).
    function pinBadge(pinMode) {
        switch (pinMode) {
        case "forever": return "📌";
        case "until": return "⏳";
        case "session": return "🕐";
        default: return "";
        }
    }

    function clipItemRow(c) {
        const pinMode = c.pin_mode || "none";
        const badge = root.pinBadge(pinMode);
        return {
            kind: "clip",
            id: c.id,
            label: c.preview,
            sub: (badge.length ? badge + "  " : "") + c.category + (c.use_count > 1 ? "  ·  x" + c.use_count : ""),
            icon: "",
            ckind: c.kind,
            category: c.category,
            pin_mode: pinMode,
            app_class: c.app_class || "",
            window_title: c.window_title || "",
            image_path: c.image_path
        };
    }

    // "24h" / "30m" / "90s" -> seconds, or null if unparseable. Mirrors
    // clipvault's own cli::parse_duration (s/m/h/d/w suffix).
    function parseDurationSecs(s) {
        const m = /^([0-9]+)([smhdw])$/.exec((s || "").trim());
        if (!m)
            return null;
        const mult = {
            s: 1,
            m: 60,
            h: 3600,
            d: 86400,
            w: 604800
        }[m[2]];
        return parseInt(m[1], 10) * mult;
    }

    // ---- tree mode: collapse/expand at cursor (Alt+H/Alt+L), all (Alt+M/Alt+R) ----
    function collapseOrUp() {
        const item = root.results[list.currentIndex];
        if (!item)
            return;
        if (item.kind === "clip-header-app" || item.kind === "clip-header-window") {
            if (!item.collapsed) {
                root.clipCollapsed[item.key] = true;
                root.refresh();
                const idx = root.results.findIndex(r => r.key === item.key);
                if (idx >= 0)
                    list.currentIndex = idx;
                return;
            }
            if (item.kind === "clip-header-window") {
                const appKey = item.key.split("|||")[0];
                const idx = root.results.findIndex(r => r.kind === "clip-header-app" && r.key === appKey);
                if (idx >= 0)
                    list.currentIndex = idx;
            }
        } else if (item.kind === "clip") {
            const wKey = item.app_class + "|||" + item.window_title;
            const idx = root.results.findIndex(r => r.kind === "clip-header-window" && r.key === wKey);
            if (idx >= 0)
                list.currentIndex = idx;
        }
    }
    function expandOrInto() {
        const item = root.results[list.currentIndex];
        if (!item)
            return;
        if (item.kind === "clip-header-app" || item.kind === "clip-header-window") {
            if (item.collapsed) {
                delete root.clipCollapsed[item.key];
                root.refresh();
                const idx = root.results.findIndex(r => r.key === item.key);
                if (idx >= 0)
                    list.currentIndex = idx;
            } else {
                list.currentIndex = root.nextSelectable(list.currentIndex, 1);
            }
        }
    }
    function expandAllClip() {
        root.clipCollapsed = {};
        root.refresh();
    }
    function collapseAllClip() {
        const collapsed = {};
        for (const c of root.clipData)
            collapsed[c.app_class || ""] = true;
        root.clipCollapsed = collapsed;
        root.refresh();
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
        } else if (item.kind === "clip") {
            root.clipAction({
                op: "copy",
                id: item.id
            });
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
                                    : root.activeMode === "clip"
                                        ? (root.clipTreeMode
                                            ? "Clipboard (tree)  ·  Alt+H/L fold  ·  Alt+R/M all  ·  Ctrl+T flat  ·  Ctrl+Shift+X bulk delete"
                                            : "Search clipboard history  ·  Enter copies  ·  Ctrl+A actions  ·  Ctrl+D delete  ·  Ctrl+T tree  ·  Alt+P pin")
                                        : "Search apps  ·  > run  ·  / files  ·  : emoji  ·  ; glyphs  ·  # icons  ·  , clipboard"
                    color: Theme.fg
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize
                    background: Rectangle {
                        color: "transparent"
                    }
                    onTextChanged: {
                        root.query = text;
                        root.refresh();
                        // requery the daemon (debounced) on every keystroke while in
                        // clip mode — separate from refresh()'s own re-render so a
                        // query response doesn't re-trigger another requery (that
                        // self-perpetuating loop was the nav-stuck bug).
                        if (root.effectiveMode() === "clip")
                            clipDebounce.restart();
                    }
                    Keys.onPressed: function (e) {
                        if (root.clipActionsOpen) {
                            // action sub-list steals all input until closed
                            if (e.key === Qt.Key_Escape) {
                                root.closeClipActions();
                            } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier))) {
                                root.clipActionsIndex = Math.min(root.clipActionsIndex + 1, root.clipActionsList.length - 1);
                            } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier))) {
                                root.clipActionsIndex = Math.max(root.clipActionsIndex - 1, 0);
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const act = root.clipActionsList[root.clipActionsIndex];
                                if (act)
                                    root.runClipAction(act.id);
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.clipPinDurationOpen) {
                            // duration entry for the "until" pin mode
                            if (e.key === Qt.Key_Escape) {
                                root.clipPinDurationOpen = false;
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const secs = root.parseDurationSecs(root.clipPinDurationBuf);
                                if (secs !== null) {
                                    root.clipAction({
                                        op: "pin",
                                        id: root.clipPinDurationFor,
                                        pin_mode: "until",
                                        expires_at: Math.floor(Date.now() / 1000) + secs
                                    });
                                    root.clipPinDurationOpen = false;
                                }
                            } else if (e.key === Qt.Key_Backspace) {
                                root.clipPinDurationBuf = root.clipPinDurationBuf.slice(0, -1);
                            } else if (e.text && e.text.length) {
                                root.clipPinDurationBuf += e.text;
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.clipPinPickerOpen) {
                            if (e.key === Qt.Key_Escape) {
                                root.clipPinPickerOpen = false;
                            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                                root.clipPinPickerIndex = Math.min(root.clipPinPickerIndex + 1, root.clipPinModes.length - 1);
                            } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                                root.clipPinPickerIndex = Math.max(root.clipPinPickerIndex - 1, 0);
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const mode = root.clipPinModes[root.clipPinPickerIndex];
                                root.clipPinPickerOpen = false;
                                if (mode === "until") {
                                    root.clipPinDurationFor = root.clipPinPickerFor.id;
                                    root.clipPinDurationBuf = "";
                                    root.clipPinDurationOpen = true;
                                } else {
                                    root.clipAction({
                                        op: "pin",
                                        id: root.clipPinPickerFor.id,
                                        pin_mode: mode
                                    });
                                }
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.clipBulkConfirmOpen) {
                            if (e.key === Qt.Key_Y || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                root.clipAction({
                                    op: "delete",
                                    ids: root.clipBulkConfirmIds
                                });
                                root.clipBulkMode = false;
                                root.clipBulkSelected = {};
                            }
                            root.clipBulkConfirmOpen = false;
                            e.accepted = true;
                            return;
                        }
                        if (root.clipBulkMode) {
                            // bulk-delete submode steals input like clipActionsOpen; Space/a/A
                            // are selection commands, so typing to filter is frozen while active
                            if (e.key === Qt.Key_Escape) {
                                root.clipBulkMode = false;
                                root.clipBulkSelected = {};
                            } else if (e.key === Qt.Key_Space) {
                                const item = root.results[list.currentIndex];
                                if (item && item.kind === "clip") {
                                    const sel = Object.assign({}, root.clipBulkSelected);
                                    if (sel[item.id])
                                        delete sel[item.id];
                                    else
                                        sel[item.id] = true;
                                    root.clipBulkSelected = sel;
                                }
                            } else if (e.key === Qt.Key_A && (e.modifiers & Qt.ShiftModifier)) {
                                root.clipBulkSelected = {};
                            } else if (e.key === Qt.Key_A) {
                                const sel = {};
                                for (const r of root.results)
                                    if (r.kind === "clip")
                                        sel[r.id] = true;
                                root.clipBulkSelected = sel;
                            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
                                list.currentIndex = root.nextSelectable(list.currentIndex, e.key === Qt.Key_Down ? 1 : -1);
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const ids = Object.keys(root.clipBulkSelected).map(Number);
                                if (ids.length) {
                                    root.clipBulkConfirmIds = ids;
                                    root.clipBulkConfirmOpen = true;
                                }
                            }
                            e.accepted = true;
                            return;
                        }
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
                        } else if (root.activeMode === "clip" && root.clipTreeMode && e.key === Qt.Key_H && (e.modifiers & Qt.AltModifier)) {
                            root.collapseOrUp();
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && root.clipTreeMode && e.key === Qt.Key_L && (e.modifiers & Qt.AltModifier)) {
                            root.expandOrInto();
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && e.key === Qt.Key_R && (e.modifiers & Qt.AltModifier)) {
                            root.expandAllClip();
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && e.key === Qt.Key_M && (e.modifiers & Qt.AltModifier)) {
                            root.collapseAllClip();
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && e.key === Qt.Key_T && (e.modifiers & Qt.ControlModifier)) {
                            // Ctrl+T: toggle flat/tree view (the search box can't use plain
                            // hjkl for this — every letter it receives is a search keystroke)
                            root.clipTreeMode = !root.clipTreeMode;
                            root.clipCollapsed = {};
                            clipDebounce.restart();
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && e.key === Qt.Key_X && (e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.ShiftModifier)) {
                            // Ctrl+Shift+X: enter/exit the bulk-delete submode
                            root.clipBulkMode = !root.clipBulkMode;
                            if (!root.clipBulkMode)
                                root.clipBulkSelected = {};
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.ShiftModifier)) {
                            // Ctrl+Shift+D: delete all entries from this item's app
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip" && item.app_class)
                                root.clipAction({
                                    op: "delete",
                                    app: item.app_class
                                });
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier)) {
                            // Ctrl+D: delete this entry
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip")
                                root.clipAction({
                                    op: "delete",
                                    id: item.id
                                });
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && e.key === Qt.Key_P && (e.modifiers & Qt.AltModifier)) {
                            // Alt+P: open the pin-mode picker (none/session/until/forever)
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip") {
                                root.clipPinPickerFor = item;
                                root.clipPinPickerIndex = Math.max(0, root.clipPinModes.indexOf(item.pin_mode || "none"));
                                root.clipPinPickerOpen = true;
                            }
                            e.accepted = true;
                        } else if (root.activeMode === "clip" && e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) {
                            // Ctrl+A: open the action sub-list (open in browser, edit, tmux, ...)
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip")
                                root.openClipActions(item.id);
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
                    readonly property bool isHeader: modelData.kind === "clip-header-app" || modelData.kind === "clip-header-window"
                    // headers are real, selectable rows in tree mode (so Alt+H/Alt+L can
                    // collapse/expand "the node at the cursor") — they highlight too.
                    readonly property bool current: ListView.isCurrentItem
                    width: list.width
                    height: isHeader ? (modelData.kind === "clip-header-app" ? 26 : 22) : 44
                    color: "transparent"
                    radius: 4

                    // app/window tree headers (clip tree mode): fold arrow + label
                    Text {
                        visible: del.isHeader
                        anchors.left: parent.left
                        anchors.leftMargin: modelData.kind === "clip-header-window" ? 26 : 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.collapsed ? "▸ " : "▾ ") + modelData.label
                        color: Theme.subtext
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: modelData.kind === "clip-header-app"
                        elide: Text.ElideRight
                        width: parent.width - 28
                    }

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
                        visible: !del.isHeader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: (modelData.kind === "clip" && root.clipTreeMode) ? 28 : 14
                        anchors.rightMargin: 8
                        spacing: 10

                        // bulk-delete selection checkbox (clip mode only)
                        Text {
                            visible: root.clipBulkMode && modelData.kind === "clip"
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.clipBulkSelected[modelData.id] ? "☑" : "☐"
                            color: Theme.accent
                            font.pixelSize: Theme.fontSize
                        }

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
                                        : (modelData.kind === "clip" && modelData.ckind === "image" && modelData.image_path)
                                            ? "file://" + modelData.image_path
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
                                        : modelData.kind === "clip"
                                            ? root.clipGlyph(modelData.category)
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

    // ---- clip action sub-list overlay ----
    Rectangle {
        id: actionsPopup
        visible: root.clipActionsOpen
        z: 10
        anchors.centerIn: parent
        width: 340
        height: Math.min(root.clipActionsList.length, 8) * 32 + Theme.pad * 2 + 28
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.97)
        border.color: Theme.accent
        border.width: 1.5

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: 4

            Text {
                text: "actions  ·  j/k, Enter, Esc"
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
            }

            Repeater {
                model: root.clipActionsList
                delegate: Rectangle {
                    readonly property bool current: index === root.clipActionsIndex
                    width: actionsPopup.width - Theme.pad * 2
                    height: 28
                    radius: 4
                    color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        text: modelData.label
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize - 1
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.runClipAction(modelData.id)
                    }
                }
            }
        }
    }

    // ---- pin-mode picker overlay (Alt+P) ----
    Rectangle {
        id: pinPickerPopup
        visible: root.clipPinPickerOpen
        z: 10
        anchors.centerIn: parent
        width: 260
        height: root.clipPinModes.length * 30 + Theme.pad * 2 + 24
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.97)
        border.color: Theme.accent
        border.width: 1.5

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: 4

            Text {
                text: "pin mode  ·  j/k, Enter, Esc"
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
            }

            Repeater {
                model: root.clipPinModes
                delegate: Rectangle {
                    readonly property bool current: index === root.clipPinPickerIndex
                    width: pinPickerPopup.width - Theme.pad * 2
                    height: 28
                    radius: 4
                    color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        text: root.pinBadge(modelData) + "  " + modelData
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize - 1
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.clipPinPickerIndex = index
                    }
                }
            }
        }
    }

    // ---- pin-until duration entry overlay ----
    Rectangle {
        id: pinDurationPopup
        visible: root.clipPinDurationOpen
        z: 10
        anchors.centerIn: parent
        width: 300
        height: 70
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.97)
        border.color: Theme.accent
        border.width: 1.5

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: 8
            Text {
                text: "pin until (e.g. 24h, 30m)  ·  Enter, Esc"
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
            }
            Text {
                text: root.clipPinDurationBuf.length ? root.clipPinDurationBuf : " "
                color: Theme.fg
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize
            }
        }
    }

    // ---- bulk-delete confirm overlay ----
    Rectangle {
        id: bulkConfirmPopup
        visible: root.clipBulkConfirmOpen
        z: 10
        anchors.centerIn: parent
        width: 340
        height: 70
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.97)
        border.color: Theme.accent
        border.width: 1.5

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: 8
            Text {
                text: "delete " + root.clipBulkConfirmIds.length + " selected entries?"
                color: Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize
            }
            Text {
                text: "y / Enter to confirm  ·  any other key cancels"
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }
}
