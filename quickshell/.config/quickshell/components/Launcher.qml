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

    // The store answers asynchronously. A launcher opened in the first moments of a session
    // would otherwise show the pre-history order until the next keystroke moved it.
    Connections {
        target: LauncherStore
        function onChanged() {
            if (root.visible)
                root.refresh();
        }
    }

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

    // ---- ranking ----
    //
    // The rule differs by whether a query is typed, and that split IS the design. With nothing
    // typed there is nothing to match on, so history is the whole signal; the first keystroke
    // hands control straight back to the matcher, so one stray launch can never sit above what
    // the user actually typed for. The two comparators are kept apart on purpose — collapsing
    // them into one is how the recency pin leaks into a query.
    //
    // SORTED PER GROUP, NEVER ACROSS THE RESULT SET. refresh() pushes each kind's rows in turn
    // and combi pushes apps and then `run:` fallback rows. A single global sort would let a hot
    // run entry displace the app list, which is not what combi is.

    // Match quality of a label against the typed query: 0 exact, 1 prefix, 2 word boundary,
    // 3 substring, 4 subsequence, 5 no match on the label at all. 5 is not "not a result" — the
    // row is here because something else about it matched (an app's keywords, a file's path), so
    // it sorts last rather than being dropped.
    function matchTier(label, q) {
        const s = String(label || "").toLowerCase();
        if (s === q)
            return 0;
        if (s.indexOf(q) === 0)
            return 1;
        const at = s.indexOf(q);
        if (at > 0 && " -_./:()[]".indexOf(s.charAt(at - 1)) >= 0)
            return 2;
        if (at > 0)
            return 3;
        // subsequence, the same shape NotifyDrawer.matches() uses: "bldfl" finds "Build failed"
        var i = 0;
        for (var c = 0; c < s.length && i < q.length; c++)
            if (s.charAt(c) === q.charAt(i))
                i++;
        return i === q.length ? 4 : 5;
    }

    // Order one group in place. Reads LauncherStore's in-memory map and nothing else — no query,
    // no subprocess, nothing that can block. This runs on every keystroke.
    //
    // The last tiebreak is the row's INCOMING position, not a fresh localeCompare. Incoming
    // order is already the order this group has today — alphabetical for apps, source order for
    // emoji/glyphs/icons, FolderListModel's for files — so never-used rows keep exactly the
    // order they have now, and a group of several thousand icons costs no string collation at
    // all on a path that runs per keystroke.
    function rankGroup(rows, kind, q) {
        if (!rows.length)
            return rows;
        // The pin is the last pick FOR THE ACTIVE TAB, so it comes from activeKind() rather than
        // from this group's own kind, and it applies to one group only. Those two are the same
        // thing today — every mode maps 1:1 onto a kind, and combi's run group is only ever
        // built with a query typed, which switches the pin off anyway — but a future mode
        // emitting two kinds, or a run group with an empty-query population, would silently move
        // the pin off the tab it belongs to. Asking activeKind() keeps it where the rule says.
        //
        // And it does not exist at all while a query is typed.
        const pinKind = root.activeKind();
        const pin = (q.length || kind !== pinKind) ? "" : LauncherStore.pinFor(pinKind);
        const keyed = [];
        var reorder = false;
        for (var i = 0; i < rows.length; i++) {
            const key = root.selectionKey(rows[i]);
            const score = key ? LauncherStore.scoreOf(kind, key) : 0;
            const tier = q.length ? root.matchTier(rows[i].label, q) : 0;
            const pinned = (pin.length && key === pin) ? 1 : 0;
            if (score > 0 || pinned || tier !== 0)
                reorder = true;
            keyed.push({
                row: rows[i],
                at: i,
                tier: tier,
                score: score,
                pin: pinned
            });
        }
        // Nothing in this group has history and nothing separates it by match quality: leave the
        // array alone rather than paying for a sort that cannot change anything.
        if (!reorder)
            return rows;

        if (q.length)
            // matchTier first, and score only breaks ties WITHIN a tier
            keyed.sort(function (a, b) {
                if (a.tier !== b.tier)
                    return a.tier - b.tier;
                if (a.score !== b.score)
                    return b.score - a.score;
                return a.at - b.at;
            });
        else
            // the last pick for this tab, then decayed usage for the entire rest of the list
            keyed.sort(function (a, b) {
                if (a.pin !== b.pin)
                    return b.pin - a.pin;
                if (a.score !== b.score)
                    return b.score - a.score;
                return a.at - b.at;
            });

        const out = [];
        for (var j = 0; j < keyed.length; j++)
            out.push(keyed[j].row);
        return out;
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
            // Alphabetical FIRST, then ranked: the alphabetical order is what rankGroup falls
            // back to for every app with no history, so it is still what an untouched list reads.
            const appRows = [];
            for (const d of apps)
                appRows.push({
                    kind: "app",
                    label: d.name,
                    sub: d.genericName || d.comment || "",
                    icon: d.icon || "",
                    // The id is COPIED as a plain string, not read back off `entry` later.
                    // DesktopEntries hands out a fresh DesktopEntry wrapper on every read of
                    // `.values` — the pointer differs between two refreshes of the same app —
                    // and the one captured here reads back as null a moment afterwards. So
                    // `entry.id` worked inside refresh() and was EMPTY by the time Ctrl+Del or
                    // the results IPC asked for it, which made the forget key silently do
                    // nothing on roughly half of the runs. An identity may not be a reference
                    // to something with its own lifetime.
                    id: d.id || "",
                    entry: d
                });
            out = out.concat(root.rankGroup(appRows, "app", q));
        }

        if (m === "run" || (m === "combi" && q.length)) {
            const bins = root.pathBins.filter(b => q.length ? b.toLowerCase().includes(q) : false).slice(0, 50);
            const runRows = [];
            for (const b of bins)
                runRows.push({
                    kind: "run",
                    label: b,
                    sub: "run",
                    icon: "",
                    cmd: b
                });
            // freeform: always allow running exactly what was typed
            if (q.length && !bins.includes(effectiveQuery()))
                runRows.push({
                    kind: "run",
                    label: effectiveQuery(),
                    sub: "run command",
                    icon: "",
                    cmd: effectiveQuery()
                });
            // its own group, appended AFTER the apps — in combi the app list keeps the top
            out = out.concat(root.rankGroup(runRows, "run", q));
        }

        if (m === "files") {
            // Handled by FolderListModel below; mirrored into results for uniform nav.
            //
            // TWO SUB-GROUPS, directories first. FolderListModel already sorts that way
            // (sortField: Type), and ranking the mixed list as one group would undo it: a
            // directory can never carry a score, since navigation is not a selection, so any
            // file with history would be hoisted above every folder in the directory. Opening
            // `files` in ~ would put a once-opened notes.md above Documents/ and Downloads/,
            // which is a navigation regression dressed as a ranking feature.
            const fileRows = fileResults();
            const dirRows = [];
            const plainRows = [];
            for (var fi = 0; fi < fileRows.length; fi++)
                (fileRows[fi].isDir ? dirRows : plainRows).push(fileRows[fi]);
            // Directories still go through rankGroup so a typed query orders them by match
            // quality; with no query they have no score and no pin and come back untouched.
            out = root.rankGroup(dirRows, "file", q).concat(root.rankGroup(plainRows, "file", q));
        }

        if (m === "emoji") {
            if (!root.emojiData.length) {
                loadEmoji(); // async; re-runs refresh when loaded
            } else {
                const emojiRows = [];
                for (const em of root.emojiData) {
                    if (q.length && (em.n + " " + em.k).toLowerCase().indexOf(q) < 0)
                        continue;
                    emojiRows.push({
                        kind: "emoji",
                        label: em.n,
                        sub: em.g + (em.k.length ? " · " + em.k : ""),
                        icon: "",
                        char: em.e
                    });
                }
                out = out.concat(root.rankGroup(emojiRows, "emoji", q));
            }
        }

        if (m === "glyphs") {
            if (!root.glyphData.length) {
                loadGlyphs(); // async; re-runs refresh when loaded
            } else {
                const glyphRows = [];
                for (const gl of root.glyphData) {
                    // group is searchable too ("nerd md", "math", ...)
                    if (q.length && (gl.n + " " + gl.k + " " + gl.g).toLowerCase().indexOf(q) < 0)
                        continue;
                    glyphRows.push({
                        kind: "glyph",
                        label: gl.n,
                        sub: gl.g + (gl.k.length ? " · " + gl.k : ""),
                        icon: "",
                        char: gl.e
                    });
                }
                out = out.concat(root.rankGroup(glyphRows, "glyph", q));
            }
        }

        if (m === "icons") {
            if (!root.iconData.length) {
                loadIcons(); // async; re-runs refresh when loaded
            } else {
                const iconRows = [];
                for (const ic of root.iconData) {
                    if (q.length && ic.n.toLowerCase().indexOf(q) < 0)
                        continue;
                    iconRows.push({
                        kind: "icon",
                        label: ic.n,
                        sub: ic.p,
                        icon: "",
                        path: ic.p
                    });
                }
                out = out.concat(root.rankGroup(iconRows, "icon", q));
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
                // The `. random` row above is pushed OUTSIDE the ranked group on purpose: it
                // has no history of its own (what it records is whatever file it lands on), and
                // rofi parity puts it first.
                const wallRows = [];
                for (const wp of root.wallpaperData) {
                    if (q.length && wp.n.toLowerCase().indexOf(q) < 0)
                        continue;
                    wallRows.push({
                        kind: "wallpaper",
                        label: wp.n,
                        sub: wp.p,
                        icon: "",
                        path: wp.p,
                        preview: wp.v,
                        random: false
                    });
                }
                out = out.concat(root.rankGroup(wallRows, "wallpaper", q));
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
        // `item.id` first, and `entry.id` only as a fallback: see the note where app rows are
        // built. The reference can be dead by the time this is called; the string cannot.
        if (item.kind === "app")
            return item.id || ((item.entry && item.entry.id) ? item.entry.id : "");
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
            if (target.length) {
                // the RESOLVED target, so `. random` records the wallpaper it actually picked
                // rather than the string "random"
                LauncherStore.record("wallpaper", target, item.random ? target.split("/").pop() : item.label);
                Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/WallpaperApply.sh", target]);
            }
            close();
        }
    }

    // Ctrl+Del drops the highlighted row's HISTORY, not the row: the app, file or emoji stays in
    // the results and falls back to its alphabetical position. A history the user cannot correct
    // is one they will resent.
    //
    // The chord is free — the input binds Ctrl+N / Ctrl+P for navigation and nothing else — and
    // accepting the event also stops TextField's built-in delete-word-forward from firing, since
    // Keys.priority is BeforeItem by default.
    function forgetSelected() {
        const item = root.results[list.currentIndex];
        if (!item)
            return;
        const key = root.selectionKey(item);
        if (!key.length)
            return;
        LauncherStore.forget(item.kind, key);
        root.refresh();
        // Keep the highlight on the same row rather than on whatever landed at the top: it has
        // just moved down the list, and that movement IS the feedback that it worked.
        for (var i = 0; i < root.results.length; i++) {
            if (root.results[i].kind === item.kind && root.selectionKey(root.results[i]) === key) {
                list.currentIndex = i;
                break;
            }
        }
    }

    // The current result list as JSON — kind, label, the history key and the decayed score.
    // A pure in-memory read, so an IpcHandler can return it immediately, and the same kind of
    // surface `qs ipc call notifications history` already is: a way to see what the shell
    // decided without taking a screenshot of it. It is also what the ranking test asserts on.
    function resultsJson(limit) {
        const n = (limit && limit > 0) ? Math.min(limit, 500) : 50;
        const out = [];
        for (var i = 0; i < root.results.length && i < n; i++) {
            const it = root.results[i];
            const key = root.selectionKey(it);
            out.push({
                kind: it.kind,
                label: it.label,
                key: key,
                score: key ? LauncherStore.scoreOf(it.kind, key) : 0
            });
        }
        return JSON.stringify(out);
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
                        } else if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ControlModifier)) {
                            root.forgetSelected();
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
