pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// SQLite history for notifications: every notification that reaches the server is written here,
// and this file — not the daemon's memory — is the contract every other frontend is built
// against (drawer, modal, tmux indicator, popup TUI, notifctl).
//
// WHY THE sqlite3 CLI AND NOT QtQuick.LocalStorage. LocalStorage is the only SQL binding in QML,
// and it puts the database at a *hashed* filename under the offline-storage path. A store whose
// point is "queryable from a tmux popup, from a script, over SSH" cannot live at a path nobody
// can name. The CLI writes a plain file at a documented location, costs one subprocess per
// flush (batched, so ~one per burst), and makes the read interface `sqlite3 <path> "<query>"`
// with no shell running at all. See Projects/hyprland-dotfiles/decisions.md (AD-010).
//
// WRITES NEVER BLOCK A POPUP. Everything queues into `pending` and is flushed by a subprocess;
// the popup path never waits on it and never sees an error from it. If sqlite3 is missing or the
// database is unwritable, `healthy` goes false, the reason is logged once, and the shell keeps
// running as pure in-memory state — a broken store degrades the history, never the notification.
//
//   file: ${XDG_DATA_HOME:-~/.local/share}/quickshell/notifications.db
//   env:  QS_NOTIFY_DB=<path>   use this database instead (the same path seam as
//                               QS_NOTIFY_CONFIG: a nested session or CI writes its own file)
Singleton {
    id: root

    readonly property int schemaVersion: 1

    readonly property string dbPath: {
        const explicit = Quickshell.env("QS_NOTIFY_DB");
        if (explicit)
            return explicit;
        const share = Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share");
        return share + "/quickshell/notifications.db";
    }

    readonly property var retention: NotifyConfig.store

    // false once a write has failed: the store is off, the shell is not
    property bool healthy: true
    property bool ready: false
    // rows never marked read — restored from the database at startup, so the bar's bell count
    // survives a daemon restart
    property int unreadAtStart: 0

    // ---------------------------------------------------------------------------------------
    // SQL plumbing
    // ---------------------------------------------------------------------------------------

    // The ONLY quoting rule this file needs. Values reach SQL as a JSON document inside a single
    // quoted string: JSON.stringify has already escaped every control character and quote mark,
    // so doubling `'` is sufficient and there is no second escaping context to get wrong.
    function sqlJson(obj) {
        return "'" + JSON.stringify(obj).replace(/'/g, "''") + "'";
    }

    function sqlText(s) {
        return "'" + String(s).replace(/'/g, "''") + "'";
    }

    property var pending: []

    function enqueue(sql) {
        if (!root.healthy || !NotifyConfig.store.enabled)
            return;
        const next = root.pending.slice();
        next.push(sql);
        root.pending = next;
        flushTimer.restart();
    }

    function flush() {
        if (writer.running || root.pending.length === 0 || !root.healthy)
            return;
        const batch = root.pending;
        root.pending = [];
        // one transaction per batch: a burst of notifications costs one fsync, not twenty
        writer.command = ["sqlite3", root.dbPath, "BEGIN IMMEDIATE;\n" + batch.join("\n") + "\nCOMMIT;"];
        writer.running = true;
    }

    function fail(what, detail) {
        if (!root.healthy)
            return;
        root.healthy = false;
        root.pending = [];
        console.warn("notifications: store disabled —", what, detail || "");
    }

    Timer {
        id: flushTimer
        interval: 200 // coalesce a burst into one subprocess
        repeat: false
        onTriggered: root.flush()
    }

    Process {
        id: writer
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fail("write failed (exit " + exitCode + ")", writer.stderr.text.trim());
                return;
            }
            if (root.pending.length)
                root.flush();
            else
                root.refreshRecent();
        }
    }

    // ---------------------------------------------------------------------------------------
    // Schema. Created on every start (IF NOT EXISTS), so a deleted database heals itself and a
    // fresh machine needs no install step.
    // ---------------------------------------------------------------------------------------

    readonly property string schemaSql: "PRAGMA journal_mode=WAL;\n" +
        // WAL is what lets a tmux popup or an SSH session read while the daemon writes.
        "CREATE TABLE IF NOT EXISTS notifications (\n" +
        "  row_id       INTEGER PRIMARY KEY AUTOINCREMENT,\n" +
        "  nid          INTEGER NOT NULL,\n" +
        "  app_name     TEXT NOT NULL DEFAULT '',\n" +
        "  app_icon     TEXT NOT NULL DEFAULT '',\n" +
        "  icon_path    TEXT NOT NULL DEFAULT '',\n" +
        "  summary      TEXT NOT NULL DEFAULT '',\n" +
        "  body         TEXT NOT NULL DEFAULT '',\n" +
        "  category     TEXT NOT NULL DEFAULT '',\n" +
        "  group_key    TEXT NOT NULL DEFAULT '',\n" +
        "  urgency      INTEGER NOT NULL DEFAULT 1,\n" +
        "  hints        TEXT NOT NULL DEFAULT '{}',\n" +
        "  actions      TEXT NOT NULL DEFAULT '[]',\n" +
        "  duration_ms  INTEGER NOT NULL DEFAULT 0,\n" +
        "  screen_name  TEXT NOT NULL DEFAULT '',\n" +
        "  anchor_h     TEXT NOT NULL DEFAULT '',\n" +
        "  anchor_v     TEXT NOT NULL DEFAULT '',\n" +
        "  state        TEXT NOT NULL DEFAULT 'active',\n" +
        "  received_at  INTEGER NOT NULL,\n" +
        "  expired_at   INTEGER,\n" +
        "  dismissed_at INTEGER,\n" +
        "  acted_at     INTEGER,\n" +
        "  read_at      INTEGER\n" +
        ");\n" +
        "CREATE INDEX IF NOT EXISTS notif_received ON notifications(received_at DESC);\n" +
        "CREATE INDEX IF NOT EXISTS notif_app      ON notifications(app_name, received_at DESC);\n" +
        "CREATE INDEX IF NOT EXISTS notif_category ON notifications(category, received_at DESC);\n" +
        "CREATE INDEX IF NOT EXISTS notif_urgency  ON notifications(urgency, received_at DESC);\n" +
        "CREATE INDEX IF NOT EXISTS notif_state    ON notifications(state, received_at DESC);\n" +
        "CREATE INDEX IF NOT EXISTS notif_unread   ON notifications(read_at) WHERE read_at IS NULL;\n" +
        "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);\n" +
        "INSERT INTO meta(key, value) VALUES ('schema_version', '" + root.schemaVersion + "')\n" +
        "  ON CONFLICT(key) DO UPDATE SET value = excluded.value;\n" +
        // Rows still 'active' belong to a previous run: their D-Bus notifications died with that
        // process, so nothing can dismiss or expire them any more. They are reconciled here
        // rather than left to look live forever — and they stay unread, which is how a sticky
        // critical from before a restart still shows up in the bell count.
        "UPDATE notifications SET state = 'orphaned' WHERE state = 'active';\n";

    Process {
        id: initProc
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fail("could not open " + root.dbPath, initProc.stderr.text.trim());
                return;
            }
            root.ready = true;
            root.prune();
            root.refreshRecent();
            unreadProc.running = true;
        }
    }

    // mkdir -p the parent: sqlite3 will not create a missing directory, and a first run on a new
    // machine has no ~/.local/share/quickshell yet
    Process {
        id: mkdirProc
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fail("could not create the database directory", "");
                return;
            }
            initProc.command = ["sqlite3", root.dbPath, root.schemaSql];
            initProc.running = true;
        }
    }

    // ---------------------------------------------------------------------------------------
    // Recording. Called from the Notifications singleton — one row per notification, updated in
    // place as it is read, dismissed, expired or acted on.
    // ---------------------------------------------------------------------------------------

    function record(entry, snapshot) {
        if (!NotifyConfig.store.enabled)
            return;
        const doc = {
            nid: snapshot.id,
            app_name: snapshot.appName,
            app_icon: snapshot.appIcon,
            icon_path: snapshot.image,
            summary: snapshot.summary,
            body: snapshot.body,
            category: snapshot.category,
            group_key: "", // grouping story
            urgency: snapshot.urgency,
            hints: JSON.stringify(entry.hints || {}),
            actions: "[]", // actions story
            duration_ms: snapshot.durationMs,
            screen_name: entry.screenName,
            anchor_h: entry.anchorH,
            anchor_v: entry.anchorV,
            received_at: snapshot.timestamp
        };
        // json_extract off a single quoted document: one escaping rule, no per-column quoting,
        // and adding a column later is a one-line change on both sides.
        root.enqueue("INSERT INTO notifications (nid, app_name, app_icon, icon_path, summary, body," + " category, group_key, urgency, hints, actions, duration_ms, screen_name, anchor_h," + " anchor_v, received_at)\n" + "SELECT json_extract(d, '$.nid'), json_extract(d, '$.app_name'), json_extract(d, '$.app_icon')," + " json_extract(d, '$.icon_path'), json_extract(d, '$.summary'), json_extract(d, '$.body')," + " json_extract(d, '$.category'), json_extract(d, '$.group_key'), json_extract(d, '$.urgency')," + " json_extract(d, '$.hints'), json_extract(d, '$.actions'), json_extract(d, '$.duration_ms')," + " json_extract(d, '$.screen_name'), json_extract(d, '$.anchor_h'), json_extract(d, '$.anchor_v')," + " json_extract(d, '$.received_at')\n" + "FROM (SELECT " + root.sqlJson(doc) + " AS d);");
    }

    // An in-place update (replaces_id) mutates the same notification, so the row follows it
    // rather than a second row appearing for the same id.
    function update(entry, snapshot) {
        if (!NotifyConfig.store.enabled)
            return;
        const doc = {
            summary: snapshot.summary,
            body: snapshot.body,
            category: snapshot.category,
            urgency: snapshot.urgency,
            icon_path: snapshot.image,
            hints: JSON.stringify(entry.hints || {}),
            duration_ms: snapshot.durationMs
        };
        root.enqueue("UPDATE notifications SET\n" + "  summary = json_extract(" + root.sqlJson(doc) + ", '$.summary'),\n" + "  body = json_extract(" + root.sqlJson(doc) + ", '$.body'),\n" + "  category = json_extract(" + root.sqlJson(doc) + ", '$.category'),\n" + "  urgency = json_extract(" + root.sqlJson(doc) + ", '$.urgency'),\n" + "  icon_path = json_extract(" + root.sqlJson(doc) + ", '$.icon_path'),\n" + "  hints = json_extract(" + root.sqlJson(doc) + ", '$.hints'),\n" + "  duration_ms = json_extract(" + root.sqlJson(doc) + ", '$.duration_ms')\n" + "WHERE row_id = (SELECT MAX(row_id) FROM notifications WHERE nid = " + Number(snapshot.id) + " AND state = 'active');");
    }

    // state: expired | dismissed | closed | acted
    function close(nid, state) {
        if (!NotifyConfig.store.enabled)
            return;
        const now = Date.now();
        const stamp = state === "dismissed" ? "dismissed_at" : (state === "acted" ? "acted_at" : "expired_at");
        root.enqueue("UPDATE notifications SET state = " + root.sqlText(state) + ", " + stamp + " = " + now + "\n" + "WHERE row_id = (SELECT MAX(row_id) FROM notifications WHERE nid = " + Number(nid) + " AND state = 'active');");
    }

    function markAllRead() {
        if (!NotifyConfig.store.enabled)
            return;
        root.enqueue("UPDATE notifications SET read_at = " + Date.now() + " WHERE read_at IS NULL;");
    }

    // ---------------------------------------------------------------------------------------
    // Retention. Age AND count, both enforced on start and then hourly, in the background.
    // ---------------------------------------------------------------------------------------

    function prune() {
        if (!root.ready || !NotifyConfig.store.enabled)
            return;
        const days = NotifyConfig.store.retentionDays;
        const count = NotifyConfig.store.retentionCount;
        var sql = "";
        if (days > 0)
            sql += "DELETE FROM notifications WHERE received_at < " + (Date.now() - days * 86400000) + ";\n";
        if (count > 0)
            sql += "DELETE FROM notifications WHERE row_id NOT IN (SELECT row_id FROM notifications ORDER BY received_at DESC LIMIT " + count + ");\n";
        if (sql.length)
            root.enqueue(sql);
    }

    Timer {
        interval: 3600000
        repeat: true
        running: root.ready && root.healthy
        onTriggered: root.prune()
    }

    // tightening retention in notifications.json applies on save, not at the next hourly tick
    Connections {
        target: NotifyConfig
        function onStoreChanged() {
            root.prune();
        }
    }

    // ---------------------------------------------------------------------------------------
    // Queries. Read-only and out-of-band: the same statements work from any sqlite3 client with
    // no shell running, which is the point of the store (see quickshell/CLAUDE.md).
    // ---------------------------------------------------------------------------------------

    Process {
        id: unreadProc
        command: ["sqlite3", root.dbPath, "SELECT COUNT(*) FROM notifications WHERE read_at IS NULL;"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(this.text.trim(), 10);
                if (!isNaN(n))
                    root.unreadAtStart = n;
            }
        }
    }

    // Synchronous-looking query for IPC callers: runs sqlite3 and hands the JSON text to a
    // callback. `-json` output is exactly what a CLI client would get, so the IPC surface and
    // the direct-sqlite surface never drift.
    function query(sql, callback) {
        if (!root.healthy || !NotifyConfig.store.enabled) {
            callback("[]");
            return;
        }
        const proc = queryComponent.createObject(root, {
            sql: sql,
            callback: callback
        });
        proc.run();
    }

    function history(limit, callback) {
        const n = Math.max(1, Math.min(1000, limit || 50));
        root.query("SELECT * FROM notifications ORDER BY received_at DESC LIMIT " + n + ";", callback);
    }

    function search(text, limit, callback) {
        const n = Math.max(1, Math.min(1000, limit || 50));
        const like = root.sqlText("%" + text + "%");
        root.query("SELECT * FROM notifications WHERE summary LIKE " + like + " OR body LIKE " + like + " OR app_name LIKE " + like + " ORDER BY received_at DESC LIMIT " + n + ";", callback);
    }

    // ---------------------------------------------------------------------------------------
    // Recent-rows cache. An IpcHandler function must return a value NOW — it cannot wait on a
    // subprocess — so the newest `cacheRows` rows are kept as sqlite3's own JSON text and
    // refreshed after each write batch. Anything beyond this window is a database query, which
    // every client can already make.
    // ---------------------------------------------------------------------------------------

    readonly property int cacheRows: 200
    property string recent: "[]"

    function refreshRecent() {
        root.history(root.cacheRows, rows => root.recent = rows);
    }

    function recentJson(limit) {
        const n = limit > 0 ? limit : 50;
        if (n >= root.cacheRows)
            return root.recent;
        try {
            return JSON.stringify(JSON.parse(root.recent).slice(0, n));
        } catch (e) {
            return root.recent;
        }
    }

    Component {
        id: queryComponent

        Process {
            id: proc

            property string sql: ""
            property var callback: null

            function run() {
                proc.command = ["sqlite3", "-json", "-readonly", root.dbPath, proc.sql];
                proc.running = true;
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    const out = this.text.trim();
                    if (proc.callback)
                        proc.callback(out.length ? out : "[]");
                    proc.destroy();
                }
            }
            stderr: StdioCollector {}
            onExited: exitCode => {
                if (exitCode !== 0) {
                    console.warn("notifications: query failed —", proc.stderr.text.trim());
                    if (proc.callback)
                        proc.callback("[]");
                    proc.destroy();
                }
            }
        }
    }

    // ---------------------------------------------------------------------------------------

    Component.onCompleted: {
        if (!NotifyConfig.store.enabled)
            return;
        const at = root.dbPath.lastIndexOf("/");
        mkdirProc.command = ["mkdir", "-p", at > 0 ? root.dbPath.substring(0, at) : "."];
        mkdirProc.running = true;
    }
}
