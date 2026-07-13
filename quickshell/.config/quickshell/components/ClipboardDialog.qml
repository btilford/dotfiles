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
// singleton. v3 (this pass): search + flat/tree list + preview pane + actions
// popup + pin picker + delete + bulk delete, all ported from Launcher's clip
// mode (prefix dropped). Launcher strip + hyprland rebind land in later passes.
PanelWindow {
    id: root
    visible: Clipboard.shown
    color: "transparent"
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive, matching the other overlays (Session/Keymap/Launcher). Two earlier live tests
    // hung the whole session needing killall/logout. Real root cause (found the hard way): a
    // `property var data` below shadowed Item's built-in `data` default property, corrupting the
    // window's content tree so the layer surface never gained keyboard activation — Window.active
    // stayed false, every key (incl. Escape) was dropped, and the Exclusive grab held the physical
    // keyboard with nothing able to release it = system-wide lockout. Fixed by renaming that
    // property to clipData; the window now activates and `input` receives keys, so Escape (and
    // per-sub-mode Escape) is handled entirely in input's Keys.onPressed. An earlier window-scope
    // Escape Shortcut was removed — it hijacked Escape globally and closed the whole dialog even
    // when a sub-mode popup should have caught it.
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

    // Tree mode (app -> window -> item, Ctrl+T toggles): server-side group_by:"app"
    // clusters entries so headers are built in one pass; fold state is a plain JS
    // object keyed by app_class ("") or "app_class|||window_title" (window).
    property bool treeMode: false
    property var collapsed: ({})
    // Bulk-delete submode (Ctrl+Shift+X): freezes text input, Space toggles
    // selection, Enter opens a confirm popup before the actual delete.
    property bool bulkMode: false
    property var bulkSelected: ({})
    property bool bulkConfirmOpen: false
    property var bulkConfirmIds: []
    // Pin-mode picker (Alt+P): none/session/until/forever; "until" chains into a
    // duration-entry overlay instead of firing immediately.
    readonly property var pinModes: ["none", "session", "until", "forever"]
    property bool pinPickerOpen: false
    property int pinPickerIndex: 0
    property var pinPickerFor: null
    property bool pinDurationOpen: false
    property int pinDurationFor: -1
    property string pinDurationBuf: ""
    // Action sub-list (open in browser, edit, tmux, curl, ...)
    property var actionsList: []
    property int actionsIndex: 0
    property bool actionsOpen: false
    property int actionsForId: -1
    // LLM prompt sub-list (Ctrl+L): clipvault's `[llm]` prompts matched to the
    // selected entry's category. Enter runs one in its configured mode, `t` forces
    // a background tmux session, `h` overrides the harness for this run only.
    // (clipvault's third mode, `foreground`, exec-replaces the process with the
    // harness — it needs a terminal, so the daemon rejects it over IPC.)
    property var llmList: []
    property int llmIndex: 0
    property bool llmOpen: false
    property int llmForId: -1
    // Harness override sub-list (`h`), mirroring the TUI's `h` key. `llmPending*`
    // holds the run the picker will fire once a harness is chosen.
    property var llmHarnessList: []
    property int llmHarnessIndex: 0
    property bool llmHarnessOpen: false
    property string llmHarnessDefault: ""
    property string llmPendingPrompt: ""
    property string llmPendingLabel: ""
    property string llmPendingMode: ""
    // Result view for capture-mode prompts: the `llm` op returns the harness text
    // as `output`, so the answer is shown here whether or not it was stored.
    // `insert_result` defaults to false in clipvault — `i` stores it, `c` copies it,
    // Esc throws it away. `llmResultEntryId` is set only when it did land in the db
    // (an `insert_result = true` prompt, or after `i`), and then guards a re-insert.
    property bool llmRunning: false
    property string llmRunLabel: ""
    property bool llmResultOpen: false
    property string llmResultBody: ""
    property int llmResultEntryId: -1
    property bool llmResultCopied: false
    // Tab toggles which pane j/k-style keys drive; list-mutating keys (delete,
    // pin, actions, bulk) only fire when the list has focus.
    property bool previewFocused: false

    onVisibleChanged: if (visible) {
        query = "";
        input.text = "";
        results = [];
        treeMode = false;
        collapsed = ({});
        bulkMode = false;
        bulkSelected = ({});
        bulkConfirmOpen = false;
        pinPickerOpen = false;
        pinDurationOpen = false;
        actionsOpen = false;
        llmOpen = false;
        closeLlmHarness();
        closeLlmResult();
        previewFocused = false;
        input.forceActiveFocus();
        runQuery();
    }

    // ---- ipc socket layer (ported from Launcher.qml's clip* members, prefix dropped) ----
    // socket: request/response channel, one in-flight request at a time, FIFO queue of
    // "what kind of request is this" correlates responses (they arrive in request order).
    // eventsSocket: subscribes once, gets a push line on every daemon db change -> requery.
    property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/clipvault.sock"
    // NB: named clipData, NOT `data` — `data` is Item's built-in default property (children +
    // resources). Shadowing it with a plain var corrupts the window's content tree so the layer
    // surface never gains keyboard activation (Window.active stays false), which silently killed
    // all key input incl. Escape and, under the Exclusive grab, locked out the whole session.
    property var clipData: []
    // FIFO of {kind, id?} descriptors — responses arrive in request order, so this
    // correlates them; "get" descriptors carry the requested id for stale-drop below.
    property var reqQueue: []

    Timer {
        id: debounce
        interval: 120
        repeat: false
        onTriggered: root.runQuery()
    }

    // A quickshell 0.3.0 Socket is single-use: once the daemon goes away the peer
    // close is reported via onError, and from then on the object is dead — writes
    // are dropped ("QIODevice::write: device not open") and it never re-dials. Not
    // by re-asserting `connected = true`, not by re-setting `path` (both verified
    // against a real daemon restart; the earlier retry-timer approach silently did
    // nothing). The only thing that reconnects is building a NEW Socket, so each
    // one lives in a Loader and a dead socket is respawned by cycling `active`.
    // Symptom this fixes: restart clipvault, and the dialog opens empty (0 results)
    // forever, until qs itself is restarted.
    property int socketRespawnMs: 1500
    readonly property var socket: socketLoader.item
    readonly property var eventsSocket: eventsLoader.item
    readonly property var llmSocket: llmLoader.item
    function respawn(loader) {
        loader.active = false;
        loader.active = true;
    }

    Loader {
        id: socketLoader
        active: true
        sourceComponent: Socket {
            path: root.socketPath
            // always-on, like Launcher's clip* sockets — toggling `connected` off on hide (tried
            // earlier) cycles the unix socket on every open/close and can race a pending debounce
            // timer's write against the disconnect, which is a real hang vector.
            connected: true
            onError: error => {
                console.log("clipvault: ipc socket error (is the daemon running?)", error);
                // in-flight responses will never arrive; their descriptors would
                // mis-correlate every reply after the respawn
                root.reqQueue = [];
                socketRespawn.restart();
            }
            onConnectedChanged: if (connected && root.visible) root.runQuery()
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
                    root.clipData = msg.entries || [];
                    root.rebuild();
                } else if (desc.kind === "get") {
                    // late response after selection moved on — drop it
                    if (desc.id !== root.selectedId)
                        return;
                    root.previewEntry = msg.entry || null;
                    root.previewForId = desc.id;
                } else if (desc.kind === "actions") {
                    root.actionsList = msg.actions || [];
                    root.actionsIndex = 0;
                    root.actionsOpen = root.actionsList.length > 0;
                } else if (desc.kind === "llm_prompts") {
                    root.llmList = msg.prompts || [];
                    root.llmIndex = 0;
                    root.llmOpen = root.llmList.length > 0;
                } else if (desc.kind === "llm_harnesses") {
                    root.llmHarnessList = msg.harnesses || [];
                    root.llmHarnessDefault = msg.default_id || "";
                    const at = root.llmHarnessList.findIndex(h => h.id === root.llmHarnessDefault);
                    root.llmHarnessIndex = at < 0 ? 0 : at;
                    root.llmHarnessOpen = root.llmHarnessList.length > 0;
                    root.llmOpen = false;
                } else if (desc.kind === "llm_insert") {
                    // `i` in the result view stored the answer — hold the id so the
                    // view can say so and refuse a second insert
                    root.llmResultEntryId = msg.entry_id || -1;
                }
                    // act/pin/delete/copy: fire-and-forget acks; eventsSocket triggers
                    // the requery once the mutation actually lands
                }
            }
        }
    }
    Timer {
        id: socketRespawn
        interval: root.socketRespawnMs
        onTriggered: root.respawn(socketLoader)
    }

    function sendReq(desc, req) {
        if (!root.socket || !root.socket.connected)
            return; // socket is down/respawning; the reconnect re-queries
        root.reqQueue.push(desc);
        root.socket.write(JSON.stringify(req) + "\n");
        root.socket.flush();
    }
    function runQuery() {
        const q = root.query.trim();
        sendReq({
            kind: "list"
        }, {
            op: "list",
            query: q.length ? q : undefined,
            limit: 100,
            group_by: root.treeMode ? "app" : undefined
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
    readonly property int selectedId: (list.currentIndex >= 0 && root.results[list.currentIndex] && root.results[list.currentIndex].kind === "clip") ? root.results[list.currentIndex].id : -1
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

    Loader {
        id: eventsLoader
        active: true
        sourceComponent: Socket {
            path: root.socketPath
            // always-on, matching Launcher's clipEventsSocket — see the note on `socket` above.
            connected: true
            onError: error => {
                console.log("clipvault: ipc events socket error", error);
                eventsRespawn.restart();
            }
            parser: SplitParser {
                splitMarker: "\n"
                onRead: function (line) {
                    if (root.visible)
                        root.runQuery();
                }
            }
            // the subscription dies with the socket, so a respawned one re-subscribes
            onConnectedChanged: {
                if (connected) {
                    write(JSON.stringify({
                        op: "subscribe"
                    }) + "\n");
                    flush();
                }
            }
        }
    }
    Timer {
        id: eventsRespawn
        interval: root.socketRespawnMs
        onTriggered: root.respawn(eventsLoader)
    }

    // ---- action sub-list (open in browser, edit, tmux, curl, ...) ----
    function openActions(id) {
        actionsForId = id;
        sendReq({
            kind: "actions"
        }, {
            op: "actions",
            id: id
        });
    }
    function closeActions() {
        actionsOpen = false;
        actionsList = [];
    }
    function runAction(actionId) {
        root.action({
            op: "act",
            id: actionsForId,
            action: actionId
        });
        closeActions();
        Clipboard.close();
    }

    // ---- llm prompt sub-list (Ctrl+L) ----
    function openLlm(id) {
        llmForId = id;
        sendReq({
            kind: "llm_prompts"
        }, {
            op: "llm_prompts",
            id: id
        });
    }
    function closeLlm() {
        llmOpen = false;
        llmList = [];
    }
    // `h` on a prompt: ask the daemon which harnesses exist and which one this
    // prompt would resolve to, then let the user pick a different one for this run.
    function openLlmHarness(promptId, label, mode) {
        llmPendingPrompt = promptId;
        llmPendingLabel = label || promptId;
        llmPendingMode = mode || "";
        sendReq({
            kind: "llm_harnesses"
        }, {
            op: "llm_harnesses",
            prompt: promptId
        });
    }
    function closeLlmHarness() {
        llmHarnessOpen = false;
        llmHarnessList = [];
    }
    function runLlm(promptId, label, mode, harness) {
        // Fired on the dedicated llmSocket, not `socket`: the `llm` op runs the
        // harness synchronously and blocks its connection until done, which would
        // stall list/get/actions if it shared the main socket.
        const req = {
            op: "llm",
            id: root.llmForId,
            prompt: promptId
        };
        if (mode)
            req.mode = mode;
        if (harness)
            req.harness = harness;
        root.llmRunLabel = (label || promptId) + (harness ? "  ·  " + harness : "") + (mode === "tmux" ? "  ·  tmux" : "");
        root.llmResultBody = "";
        root.llmResultEntryId = -1;
        root.llmResultCopied = false;
        root.llmRunning = true;
        closeLlm();
        closeLlmHarness();
        if (!root.llmSocket || !root.llmSocket.connected) {
            root.llmRunning = false;
            root.llmResultBody = "the clipvault daemon isn't reachable";
            root.llmResultOpen = true;
            return;
        }
        root.llmResultOpen = true; // stay open and show progress, then the answer
        root.llmSocket.write(JSON.stringify(req) + "\n");
        root.llmSocket.flush();
    }
    // `i` in the result view — the answer only lives in this dialog until it's
    // stored (clipvault's insert_result defaults to false).
    function insertLlmResult() {
        if (root.llmResultEntryId > 0 || !root.llmResultBody)
            return;
        sendReq({
            kind: "llm_insert"
        }, {
            op: "llm_insert",
            text: root.llmResultBody
        });
    }
    function copyLlmResult() {
        if (!root.llmResultBody)
            return;
        Quickshell.execDetached(["wl-copy", "--", root.llmResultBody]);
        root.llmResultCopied = true;
    }
    function closeLlmResult() {
        llmResultOpen = false;
        llmRunning = false;
        llmResultBody = "";
        llmResultEntryId = -1;
        llmResultCopied = false;
    }

    // Dedicated channel for the blocking `llm` op, and where its outcome comes back.
    Loader {
        id: llmLoader
        active: true
        sourceComponent: Socket {
            path: root.socketPath
            connected: true
            onError: error => {
                console.log("clipvault: llm socket error", error);
                // if this fires mid-run the harness's answer is gone with the socket —
                // say so rather than leaving the spinner up forever
                if (root.llmRunning) {
                    root.llmRunning = false;
                    root.llmResultBody = "the clipvault daemon went away while the harness was running";
                    root.llmResultOpen = true;
                }
                llmRespawn.restart();
            }
            parser: SplitParser {
                splitMarker: "\n"
                onRead: function (line) {
                    let msg;
                    try {
                        msg = JSON.parse(line);
                    } catch (e) {
                        return;
                    }
                    if (msg.error) {
                        root.llmRunning = false;
                        root.llmResultBody = "error: " + msg.error;
                        root.llmResultOpen = true;
                    } else if (msg.tmux_session) {
                        // background mode — nothing to display here; point the user at the
                        // session instead of silently stranding it.
                        root.closeLlmResult();
                        Quickshell.execDetached(["notify-send", "-a", "clipvault", "LLM running in tmux", "tmux attach -t " + msg.tmux_session]);
                        Clipboard.close();
                    } else {
                        // capture mode: the op carries the harness text, so the answer is
                        // shown whether or not clipvault stored it. entry_id is set only
                        // when an `insert_result = true` prompt auto-inserted it.
                        root.llmRunning = false;
                        root.llmResultBody = msg.output || "(empty result)";
                        root.llmResultEntryId = msg.entry_id || -1;
                        root.llmResultCopied = !!msg.copied;
                        root.llmResultOpen = true;
                    }
                }
            }
        }
    }
    Timer {
        id: llmRespawn
        interval: root.socketRespawnMs
        onTriggered: root.respawn(llmLoader)
    }

    // ---- row shaping + tree building + selection preservation across a requery ----
    function pinBadge(pinMode) {
        switch (pinMode) {
        case "forever": return "📌";
        case "until": return "⏳";
        case "session": return "🕐";
        default: return "";
        }
    }
    function glyph(category) {
        switch (category) {
        case "url": return "";
        case "color": return "";
        case "email": return "";
        case "file-path": return "";
        case "code": return "";
        case "files": return "";
        case "image": return "";
        default: return "";
        }
    }
    function itemRow(c) {
        const pinMode = c.pin_mode || "none";
        const badge = root.pinBadge(pinMode);
        return {
            kind: "clip",
            id: c.id,
            label: c.preview,
            sub: (badge.length ? badge + "  " : "") + c.category + (c.use_count > 1 ? "  ·  x" + c.use_count : ""),
            category: c.category,
            pin_mode: pinMode,
            app_class: c.app_class || "",
            window_title: c.window_title || "",
            ckind: c.kind,
            image_path: c.image_path
        };
    }
    // Flat mode has no headers; tree mode's headers are real, selectable rows
    // (so hjkl-equivalents can collapse/expand "the node at the cursor").
    function nextSelectable(idx, dir) {
        if (!root.results.length)
            return idx;
        return Math.min(Math.max(idx + dir, 0), root.results.length - 1);
    }
    function rebuild() {
        const prevItem = root.results[list.currentIndex];
        let out = [];
        if (root.treeMode) {
            let prevApp = null;
            let prevWin = null;
            for (const c of root.clipData) {
                const appKey = c.app_class || "";
                if (appKey !== prevApp) {
                    out.push({
                        kind: "header-app",
                        key: appKey,
                        label: c.app_class ? c.app_class : "(unknown app)",
                        collapsed: !!root.collapsed[appKey]
                    });
                    prevApp = appKey;
                    prevWin = null;
                }
                if (root.collapsed[appKey])
                    continue;
                const winKey = appKey + "|||" + (c.window_title || "");
                if (winKey !== prevWin) {
                    out.push({
                        kind: "header-window",
                        key: winKey,
                        label: c.window_title ? c.window_title : "(no title)",
                        collapsed: !!root.collapsed[winKey]
                    });
                    prevWin = winKey;
                }
                if (root.collapsed[winKey])
                    continue;
                out.push(root.itemRow(c));
            }
        } else {
            for (const c of root.clipData)
                out.push(root.itemRow(c));
        }
        root.results = out;
        const key = prevItem ? (prevItem.kind === "clip" ? "id:" + prevItem.id : "key:" + prevItem.key) : null;
        const idx = key ? out.findIndex(r => (r.kind === "clip" ? "id:" + r.id : "key:" + r.key) === key) : -1;
        list.currentIndex = idx >= 0 ? idx : (out.length ? root.nextSelectable(-1, 1) : -1);
    }

    // "24h" / "30m" / "90s" -> seconds, or null if unparseable.
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
        if (item.kind === "header-app" || item.kind === "header-window") {
            if (!item.collapsed) {
                root.collapsed[item.key] = true;
                root.rebuild();
                const idx = root.results.findIndex(r => r.key === item.key);
                if (idx >= 0)
                    list.currentIndex = idx;
                return;
            }
            if (item.kind === "header-window") {
                const appKey = item.key.split("|||")[0];
                const idx = root.results.findIndex(r => r.kind === "header-app" && r.key === appKey);
                if (idx >= 0)
                    list.currentIndex = idx;
            }
        } else if (item.kind === "clip") {
            const wKey = item.app_class + "|||" + item.window_title;
            const idx = root.results.findIndex(r => r.kind === "header-window" && r.key === wKey);
            if (idx >= 0)
                list.currentIndex = idx;
        }
    }
    function expandOrInto() {
        const item = root.results[list.currentIndex];
        if (!item)
            return;
        if (item.kind === "header-app" || item.kind === "header-window") {
            if (item.collapsed) {
                delete root.collapsed[item.key];
                root.rebuild();
                const idx = root.results.findIndex(r => r.key === item.key);
                if (idx >= 0)
                    list.currentIndex = idx;
            } else {
                list.currentIndex = root.nextSelectable(list.currentIndex, 1);
            }
        }
    }
    function expandAll() {
        root.collapsed = {};
        root.rebuild();
    }
    function collapseAll() {
        const c = {};
        for (const e of root.clipData)
            c[e.app_class || ""] = true;
        root.collapsed = c;
        root.rebuild();
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
        width: root.width * 0.72
        height: root.height * 0.78
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
                    placeholderText: root.treeMode
                        ? "Clipboard (tree)  ·  Alt+H/L fold  ·  Alt+R/M all  ·  Ctrl+T flat  ·  Ctrl+Shift+X bulk delete"
                        : "Search  ·  Enter copies  ·  Ctrl+A actions  ·  Ctrl+L llm  ·  Ctrl+D delete  ·  Ctrl+T tree  ·  Alt+P pin  ·  Tab preview"
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
                        if (root.actionsOpen) {
                            // action sub-list steals all input until closed
                            if (e.key === Qt.Key_Escape) {
                                root.closeActions();
                            } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier))) {
                                root.actionsIndex = Math.min(root.actionsIndex + 1, root.actionsList.length - 1);
                            } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier))) {
                                root.actionsIndex = Math.max(root.actionsIndex - 1, 0);
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const act = root.actionsList[root.actionsIndex];
                                if (act)
                                    root.runAction(act.id);
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.llmResultOpen) {
                            // llm result view: c/Enter copies the answer, i stores it as
                            // an entry, Esc dismisses (and drops it), j/k scroll.
                            const rf = llmResultFlick;
                            if (e.key === Qt.Key_Escape) {
                                root.closeLlmResult();
                            } else if (e.key === Qt.Key_C || e.key === Qt.Key_Y) {
                                root.copyLlmResult();
                            } else if (e.key === Qt.Key_I) {
                                root.insertLlmResult();
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                root.copyLlmResult();
                                root.closeLlmResult();
                                Clipboard.close();
                            } else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
                                rf.contentY = Math.min(rf.contentY + 40, Math.max(0, rf.contentHeight - rf.height));
                            } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
                                rf.contentY = Math.max(rf.contentY - 40, 0);
                            } else if (e.key === Qt.Key_PageDown || (e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier))) {
                                rf.contentY = Math.min(rf.contentY + rf.height * 0.9, Math.max(0, rf.contentHeight - rf.height));
                            } else if (e.key === Qt.Key_PageUp || (e.key === Qt.Key_U && (e.modifiers & Qt.ControlModifier))) {
                                rf.contentY = Math.max(rf.contentY - rf.height * 0.9, 0);
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.llmHarnessOpen) {
                            // harness override sub-list — Enter fires the pending run
                            if (e.key === Qt.Key_Escape) {
                                root.closeLlmHarness();
                            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J || (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier))) {
                                root.llmHarnessIndex = Math.min(root.llmHarnessIndex + 1, root.llmHarnessList.length - 1);
                            } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K || (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier))) {
                                root.llmHarnessIndex = Math.max(root.llmHarnessIndex - 1, 0);
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const h = root.llmHarnessList[root.llmHarnessIndex];
                                if (h)
                                    root.runLlm(root.llmPendingPrompt, root.llmPendingLabel, root.llmPendingMode, h.id);
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.llmOpen) {
                            // llm prompt sub-list steals all input until closed
                            const p = root.llmList[root.llmIndex];
                            if (e.key === Qt.Key_Escape) {
                                root.closeLlm();
                            } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier))) {
                                root.llmIndex = Math.min(root.llmIndex + 1, root.llmList.length - 1);
                            } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier))) {
                                root.llmIndex = Math.max(root.llmIndex - 1, 0);
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                if (p)
                                    root.runLlm(p.id, p.label, "", "");
                            } else if (e.key === Qt.Key_T) {
                                // background tmux session — the answer lands in the
                                // session, not here
                                if (p)
                                    root.runLlm(p.id, p.label, "tmux", "");
                            } else if (e.key === Qt.Key_H) {
                                if (p)
                                    root.openLlmHarness(p.id, p.label, "");
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.pinDurationOpen) {
                            if (e.key === Qt.Key_Escape) {
                                root.pinDurationOpen = false;
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const secs = root.parseDurationSecs(root.pinDurationBuf);
                                if (secs !== null) {
                                    root.action({
                                        op: "pin",
                                        id: root.pinDurationFor,
                                        pin_mode: "until",
                                        expires_at: Math.floor(Date.now() / 1000) + secs
                                    });
                                    root.pinDurationOpen = false;
                                }
                            } else if (e.key === Qt.Key_Backspace) {
                                root.pinDurationBuf = root.pinDurationBuf.slice(0, -1);
                            } else if (e.text && e.text.length) {
                                root.pinDurationBuf += e.text;
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.pinPickerOpen) {
                            if (e.key === Qt.Key_Escape) {
                                root.pinPickerOpen = false;
                            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                                root.pinPickerIndex = Math.min(root.pinPickerIndex + 1, root.pinModes.length - 1);
                            } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                                root.pinPickerIndex = Math.max(root.pinPickerIndex - 1, 0);
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const mode = root.pinModes[root.pinPickerIndex];
                                root.pinPickerOpen = false;
                                if (mode === "until") {
                                    root.pinDurationFor = root.pinPickerFor.id;
                                    root.pinDurationBuf = "";
                                    root.pinDurationOpen = true;
                                } else {
                                    root.action({
                                        op: "pin",
                                        id: root.pinPickerFor.id,
                                        pin_mode: mode
                                    });
                                }
                            }
                            e.accepted = true;
                            return;
                        }
                        if (root.bulkConfirmOpen) {
                            if (e.key === Qt.Key_Y || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                root.action({
                                    op: "delete",
                                    ids: root.bulkConfirmIds
                                });
                                root.bulkMode = false;
                                root.bulkSelected = {};
                            }
                            root.bulkConfirmOpen = false;
                            e.accepted = true;
                            return;
                        }
                        if (root.bulkMode) {
                            if (e.key === Qt.Key_Escape) {
                                root.bulkMode = false;
                                root.bulkSelected = {};
                            } else if (e.key === Qt.Key_Space) {
                                const item = root.results[list.currentIndex];
                                if (item && item.kind === "clip") {
                                    const sel = Object.assign({}, root.bulkSelected);
                                    if (sel[item.id])
                                        delete sel[item.id];
                                    else
                                        sel[item.id] = true;
                                    root.bulkSelected = sel;
                                }
                            } else if (e.key === Qt.Key_A && (e.modifiers & Qt.ShiftModifier)) {
                                root.bulkSelected = {};
                            } else if (e.key === Qt.Key_A) {
                                const sel = {};
                                for (const r of root.results)
                                    if (r.kind === "clip")
                                        sel[r.id] = true;
                                root.bulkSelected = sel;
                            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
                                list.currentIndex = root.nextSelectable(list.currentIndex, e.key === Qt.Key_Down ? 1 : -1);
                            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                const ids = Object.keys(root.bulkSelected).map(Number);
                                if (ids.length) {
                                    root.bulkConfirmIds = ids;
                                    root.bulkConfirmOpen = true;
                                }
                            }
                            e.accepted = true;
                            return;
                        }
                        if (e.key === Qt.Key_Escape) {
                            Clipboard.close();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Tab) {
                            root.previewFocused = !root.previewFocused;
                            e.accepted = true;
                        } else if (root.previewFocused) {
                            // preview has focus: j/k/PgUp/PgDn/^d/^u scroll the flickable
                            const fl = previewFlick;
                            const page = fl.height * 0.9;
                            if (e.key === Qt.Key_J || e.key === Qt.Key_Down) {
                                fl.contentY = Math.min(fl.contentY + 40, Math.max(0, fl.contentHeight - fl.height));
                            } else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) {
                                fl.contentY = Math.max(fl.contentY - 40, 0);
                            } else if (e.key === Qt.Key_PageDown || (e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier))) {
                                fl.contentY = Math.min(fl.contentY + page, Math.max(0, fl.contentHeight - fl.height));
                            } else if (e.key === Qt.Key_PageUp || (e.key === Qt.Key_U && (e.modifiers & Qt.ControlModifier))) {
                                fl.contentY = Math.max(fl.contentY - page, 0);
                            } else if (e.key === Qt.Key_G && (e.modifiers & Qt.ShiftModifier)) {
                                fl.contentY = Math.max(0, fl.contentHeight - fl.height);
                            } else if (e.key === Qt.Key_G) {
                                fl.contentY = 0;
                            }
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Down || (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier))) {
                            list.currentIndex = root.nextSelectable(list.currentIndex, 1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.AltModifier))) {
                            list.currentIndex = root.nextSelectable(list.currentIndex, -1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip") {
                                root.action({
                                    op: "copy",
                                    id: item.id
                                });
                                Clipboard.close();
                            }
                            e.accepted = true;
                        } else if (root.treeMode && e.key === Qt.Key_H && (e.modifiers & Qt.AltModifier)) {
                            root.collapseOrUp();
                            e.accepted = true;
                        } else if (root.treeMode && e.key === Qt.Key_L && (e.modifiers & Qt.AltModifier)) {
                            root.expandOrInto();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_R && (e.modifiers & Qt.AltModifier)) {
                            root.expandAll();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_M && (e.modifiers & Qt.AltModifier)) {
                            root.collapseAll();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_T && (e.modifiers & Qt.ControlModifier)) {
                            root.treeMode = !root.treeMode;
                            root.collapsed = {};
                            debounce.restart();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_X && (e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.ShiftModifier)) {
                            root.bulkMode = !root.bulkMode;
                            if (!root.bulkMode)
                                root.bulkSelected = {};
                            e.accepted = true;
                        } else if (e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.ShiftModifier)) {
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip" && item.app_class)
                                root.action({
                                    op: "delete",
                                    app: item.app_class
                                });
                            e.accepted = true;
                        } else if (e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier)) {
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip")
                                root.action({
                                    op: "delete",
                                    id: item.id
                                });
                            e.accepted = true;
                        } else if (e.key === Qt.Key_P && (e.modifiers & Qt.AltModifier)) {
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip") {
                                root.pinPickerFor = item;
                                root.pinPickerIndex = Math.max(0, root.pinModes.indexOf(item.pin_mode || "none"));
                                root.pinPickerOpen = true;
                            }
                            e.accepted = true;
                        } else if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) {
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip")
                                root.openActions(item.id);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_L && (e.modifiers & Qt.ControlModifier)) {
                            const item = root.results[list.currentIndex];
                            if (item && item.kind === "clip")
                                root.openLlm(item.id);
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
                    // The selection highlight is a ShaderEffect (EnergyFill). One instance,
                    // owned by the ListView — putting it in the delegate built a shader node
                    // per row, so every scroll step paid for effects that were never visible.
                    // (Delegate reuse is deliberately NOT enabled: with a plain-array model the
                    // recycled delegates see `modelData === undefined` and spam binding errors.)
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 0
                    highlightResizeDuration: 0
                    // j/k set `currentIndex` directly, and a ListView only auto-scrolls for keys
                    // it handles itself — without this the selection walks off the viewport and
                    // the visible window never catches up.
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    highlight: Item {
                        width: list.width
                        EnergyFill {
                            anchors.fill: parent
                            radius: 4
                            alpha: 0.3
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: parent.height - 12
                            radius: 2
                            color: Theme.accent
                        }
                    }
                    delegate: Rectangle {
                        id: del
                        readonly property bool isHeader: modelData.kind === "header-app" || modelData.kind === "header-window"
                        width: list.width
                        height: isHeader ? (modelData.kind === "header-app" ? 26 : 22) : 44
                        color: "transparent"
                        radius: 4

                        // app/window tree headers: fold arrow + label
                        Text {
                            visible: del.isHeader
                            anchors.left: parent.left
                            anchors.leftMargin: modelData.kind === "header-window" ? 26 : 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: (modelData.collapsed ? "▸ " : "▾ ") + modelData.label
                            color: Theme.subtext
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: modelData.kind === "header-app"
                            elide: Text.ElideRight
                            width: parent.width - 28
                        }

                        Row {
                            visible: !del.isHeader
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: (modelData.kind === "clip" && root.treeMode) ? 28 : 14
                            anchors.rightMargin: 8
                            spacing: 10

                            Text {
                                visible: root.bulkMode && modelData.kind === "clip"
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.bulkSelected[modelData.id] ? "☑" : "☐"
                                color: Theme.accent
                                font.pixelSize: Theme.fontSize
                            }

                            Item {
                                width: 24
                                height: 24
                                anchors.verticalCenter: parent.verticalCenter
                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    visible: source != ""
                                    source: (modelData.kind === "clip" && modelData.ckind === "image" && modelData.image_path) ? "file://" + modelData.image_path : ""
                                    sourceSize.width: 24
                                    sourceSize.height: 24
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !thumb.visible
                                    text: modelData.kind === "clip" ? root.glyph(modelData.category) : ""
                                    color: Theme.accent
                                    font.family: Theme.fontUi
                                    font.pixelSize: 16
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
                                if (modelData.kind === "header-app" || modelData.kind === "header-window") {
                                    if (modelData.collapsed)
                                        root.expandOrInto();
                                    else
                                        root.collapseOrUp();
                                } else if (modelData.kind === "clip") {
                                    root.action({
                                        op: "copy",
                                        id: modelData.id
                                    });
                                    Clipboard.close();
                                }
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
                    border.width: root.previewFocused ? 1 : 0
                    border.color: Theme.accent

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

                        // image content: fall back to the path as text if the file's gone.
                        // sourceSize bounds the decode — without it a 4K screenshot is decoded
                        // and uploaded at full resolution (~33MB RGBA) for a pane a few hundred
                        // px wide, which is the bulk of the stall on selecting an image.
                        Image {
                            id: previewImage
                            visible: previewPane.isImage && status !== Image.Error
                            width: parent.width
                            height: parent.height - y
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            // A fixed box, not the live pane size: sourceSize is part of the
                            // pixmap cache key, and the pane's height shifts per entry (the
                            // metadata header grows/shrinks), so binding it to `height` would
                            // miss the cache on every selection. Raster sources are never
                            // upscaled to it.
                            sourceSize.width: 1024
                            sourceSize.height: 1024
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
                            id: previewFlick
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
                                // don't steal key/nav focus from `input` on click — a focus
                                // steal here used to kill the only Escape handler and wedge the
                                // Exclusive keyboard grab (see keyboardFocus note above). Mouse
                                // drag-select still works; the window Escape Shortcut is the
                                // backstop if focus ever does land here anyway.
                                activeFocusOnPress: false
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

    // ---- action sub-list overlay ----
    Rectangle {
        id: actionsPopup
        visible: root.actionsOpen
        z: 10
        anchors.centerIn: parent
        width: 340
        height: Math.min(root.actionsList.length, 8) * 32 + Theme.pad * 2 + 28
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

            // ListView, not Repeater-in-Column: the popup is sized for at most 8 rows, so a
            // longer list has to scroll — a Repeater would render every row unclipped and the
            // selection could sit outside the popup with no way to bring it into view.
            ListView {
                width: actionsPopup.width - Theme.pad * 2
                height: actionsPopup.height - Theme.pad * 2 - 28
                clip: true
                model: root.actionsList
                currentIndex: root.actionsIndex
                onCurrentIndexChanged: if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Rectangle {
                    readonly property bool current: index === root.actionsIndex
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
                        onClicked: root.runAction(modelData.id)
                    }
                }
            }
        }
    }

    // ---- llm prompt sub-list overlay (Ctrl+L) ----
    Rectangle {
        id: llmPopup
        visible: root.llmOpen
        z: 10
        anchors.centerIn: parent
        width: 340
        height: Math.min(root.llmList.length, 8) * 32 + Theme.pad * 2 + 28
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.97)
        border.color: Theme.accent
        border.width: 1.5

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: 4

            Text {
                text: "llm  ·  Enter run  ·  t tmux (background)  ·  h harness  ·  Esc"
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
            }

            ListView {
                width: llmPopup.width - Theme.pad * 2
                height: llmPopup.height - Theme.pad * 2 - 28
                clip: true
                model: root.llmList
                currentIndex: root.llmIndex
                onCurrentIndexChanged: if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Rectangle {
                    readonly property bool current: index === root.llmIndex
                    width: llmPopup.width - Theme.pad * 2
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
                        onClicked: root.runLlm(modelData.id, modelData.label)
                    }
                }
            }
        }
    }

    // ---- llm harness override (`h` on a prompt) ----
    Rectangle {
        id: llmHarnessPopup
        visible: root.llmHarnessOpen
        z: 11
        anchors.centerIn: parent
        width: 340
        height: Math.min(root.llmHarnessList.length, 8) * 32 + Theme.pad * 2 + 28
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.97)
        border.color: Theme.accent
        border.width: 1.5

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: 4

            Text {
                text: "harness for this run  ·  j/k, Enter, Esc"
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
            }

            ListView {
                width: llmHarnessPopup.width - Theme.pad * 2
                height: llmHarnessPopup.height - Theme.pad * 2 - 28
                clip: true
                model: root.llmHarnessList
                currentIndex: root.llmHarnessIndex
                onCurrentIndexChanged: if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Rectangle {
                    readonly property bool current: index === root.llmHarnessIndex
                    width: llmHarnessPopup.width - Theme.pad * 2
                    height: 28
                    radius: 4
                    color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        text: modelData.label + (modelData.id === root.llmHarnessDefault ? "  (default)" : "")
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize - 1
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.runLlm(root.llmPendingPrompt, root.llmPendingLabel, root.llmPendingMode, modelData.id)
                    }
                }
            }
        }
    }

    // ---- llm result view (capture-mode prompts: summarize / explain) ----
    Rectangle {
        id: llmResultPopup
        visible: root.llmResultOpen
        z: 20
        anchors.centerIn: parent
        width: root.width * 0.6
        height: root.height * 0.62
        radius: Theme.radius
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.98)
        border.color: Theme.accent
        border.width: 1.5

        // swallow clicks so the click-away backdrop doesn't close mid-read
        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.pad

            Text {
                width: parent.width
                text: {
                    if (root.llmRunning)
                        return "running  ·  " + root.llmRunLabel + "  …";
                    const state = root.llmResultEntryId > 0
                        ? ("saved as #" + root.llmResultEntryId + (root.llmResultCopied ? ", copied" : ""))
                        : (root.llmResultCopied ? "copied, not saved" : "not saved");
                    return root.llmRunLabel + "  ·  " + state + "  ·  c copy  ·  i save  ·  j/k scroll  ·  Esc discards";
                }
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 3
                elide: Text.ElideRight
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
            }

            Flickable {
                id: llmResultFlick
                width: parent.width
                height: parent.height - y
                clip: true
                contentWidth: width
                contentHeight: llmResultView.implicitHeight
                TextEdit {
                    id: llmResultView
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    activeFocusOnPress: false // never steal focus from `input`
                    wrapMode: TextEdit.Wrap
                    color: Theme.fg
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 1
                    text: root.llmRunning ? "…" : root.llmResultBody
                }
            }
        }
    }

    // ---- pin-mode picker overlay (Alt+P) ----
    Rectangle {
        id: pinPickerPopup
        visible: root.pinPickerOpen
        z: 10
        anchors.centerIn: parent
        width: 260
        height: root.pinModes.length * 30 + Theme.pad * 2 + 24
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
                model: root.pinModes
                delegate: Rectangle {
                    readonly property bool current: index === root.pinPickerIndex
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
                        onClicked: root.pinPickerIndex = index
                    }
                }
            }
        }
    }

    // ---- pin-until duration entry overlay ----
    Rectangle {
        id: pinDurationPopup
        visible: root.pinDurationOpen
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
                text: root.pinDurationBuf.length ? root.pinDurationBuf : " "
                color: Theme.fg
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize
            }
        }
    }

    // ---- bulk-delete confirm overlay ----
    Rectangle {
        id: bulkConfirmPopup
        visible: root.bulkConfirmOpen
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
                text: "delete " + root.bulkConfirmIds.length + " selected entries?"
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
