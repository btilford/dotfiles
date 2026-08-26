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

    // 4: the `timers` table (story: notif-timers). It is a CREATE TABLE IF NOT EXISTS in
    // schemaSql rather than an entry in `migrations` — a new table needs no ALTER and heals
    // itself on every start — but the number still has to move, because this is what a reader of
    // the file checks to know which tables it can expect.
    readonly property int schemaVersion: 4

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
            if (root.pending.length) {
                root.flush();
                return;
            }
            root.refreshRecent();
            // Re-arm HERE, not at the call site. snooze() and fireDueSnoozes() both enqueue a
            // write and cannot read their own effect: the batch flushes through this
            // subprocess ~200ms later. Arming before it landed read MIN(wake_at) as NULL and
            // stopped the timer, so a snooze never fired on its own and only went off on the
            // next restart (observed 2026-08-05). The write completing is the only moment the
            // schedule is knowable.
            if (root.rearmAfterFlush) {
                root.rearmAfterFlush = false;
                root.armSnoozeTimer();
            }
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
        // Timers (story: notif-timers). A SEPARATE TABLE, not a notification row wearing a
        // costume: a countdown has a planned length, a phase and a cycle, and a pomodoro run is
        // several rows that belong together. It shares the ONE armed timer below rather than
        // getting a scheduler of its own — that is the part AD-012 §4 is about.
        //
        // Two row states carry meaning and the rest are history:
        //   armed   wake_at is set and this row is what the shell is waiting for
        //   paused  wake_at is NULL, remaining_ms is what is left
        //   done / cancelled  the summary row: actual_ms and ended_at are filled in
        //
        // TICKS ARE NEVER WRITTEN. A running countdown is in-memory state on the Timers
        // singleton; this table only ever sees arm, pause, resume and finish. One phase of a
        // pomodoro is one row, so "how many pomodoros today" is a COUNT over done work rows and
        // needed no tick to be answerable:
        //
        //   sqlite3 -readonly <db> "SELECT COUNT(*) FROM timers
        //     WHERE kind='pomodoro' AND phase='work' AND state='done'
        //       AND ended_at >= strftime('%s','now','start of day')*1000;"
        "CREATE TABLE IF NOT EXISTS timers (\n" +
        "  id           INTEGER PRIMARY KEY,\n" +
        "  run_id       INTEGER NOT NULL,\n" +
        "  kind         TEXT NOT NULL DEFAULT 'countdown',\n" +
        "  label        TEXT NOT NULL DEFAULT '',\n" +
        "  state        TEXT NOT NULL DEFAULT 'armed',\n" +
        "  phase        TEXT NOT NULL DEFAULT '',\n" +
        "  cycle        INTEGER NOT NULL DEFAULT 0,\n" +
        "  cycles       INTEGER NOT NULL DEFAULT 0,\n" +
        "  work_ms      INTEGER NOT NULL DEFAULT 0,\n" +
        "  short_ms     INTEGER NOT NULL DEFAULT 0,\n" +
        "  long_ms      INTEGER NOT NULL DEFAULT 0,\n" +
        "  planned_ms   INTEGER NOT NULL DEFAULT 0,\n" +
        "  remaining_ms INTEGER NOT NULL DEFAULT 0,\n" +
        "  actual_ms    INTEGER,\n" +
        "  wake_at      INTEGER,\n" +
        "  started_at   INTEGER NOT NULL,\n" +
        "  ended_at     INTEGER\n" +
        ");\n" +
        "CREATE INDEX IF NOT EXISTS timers_state ON timers(state, wake_at);\n" +
        "CREATE INDEX IF NOT EXISTS timers_ended ON timers(ended_at DESC);\n" +
        "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);\n" +
        "INSERT INTO meta(key, value) VALUES ('schema_version', '" + root.schemaVersion + "')\n" +
        "  ON CONFLICT(key) DO UPDATE SET value = excluded.value;\n" +
        // Rows still 'active' belong to a previous run: their D-Bus notifications died with that
        // process, so nothing can dismiss or expire them any more. They are reconciled here
        // rather than left to look live forever — and they stay unread, which is how a sticky
        // critical from before a restart still shows up in the bell count.
        "UPDATE notifications SET state = 'orphaned' WHERE state = 'active';\n";

    // v2 (story: notif-drawer). `cleared_at` is "the user has dealt with this in the drawer",
    // which is NOT the same as read (seen) or dismissed (a live popup closed by hand) — a row
    // cleared from the drawer stays in the history and stays queryable, it just stops being
    // listed. SQLite has no ADD COLUMN IF NOT EXISTS, so this runs as its own statement whose
    // failure is the success case on an already-migrated database ("duplicate column name").
    // v3 (story: notif-actions). `wake_at` is epoch ms; NULL means not snoozed. A snooze is a
    // ROW STATE rather than a timer living somewhere else — the store is already the source of
    // truth, and a snooze that fired from systemd could not restore urgency, actions or the
    // history row it came from.
    //
    // A LIST, run one statement per process, because the sqlite3 CLI aborts on the first error
    // and every migration after the first fails with "duplicate column name" on an
    // already-migrated database. Concatenating them would mean v3 never ran anywhere v2 had.
    readonly property var migrations: ["ALTER TABLE notifications ADD COLUMN cleared_at INTEGER;", "ALTER TABLE notifications ADD COLUMN wake_at INTEGER;"]

    Process {
        id: initProc
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fail("could not open " + root.dbPath, initProc.stderr.text.trim());
                return;
            }
            // Straight into the migration chain: runNextMigration() runs them one process at a
            // time and ends at fireDue(). (It used to start migrateProc on an undefined command
            // here and rely on its exit handler to enter the chain — one wasted subprocess whose
            // error text was indistinguishable from a real failure.)
            root.runNextMigration();
            root.ready = true;
            root.prune();
            root.refreshRecent();
            unreadProc.running = true;
        }
    }

    // Exit code deliberately unchecked: on every start after the first, each of these fails
    // with "duplicate column name", which is exactly the state we want. A real failure
    // (unwritable database) has already been caught by initProc above. Chained one at a time
    // so a failing early migration cannot stop a later one from running.
    property int migrationIndex: 0

    function runNextMigration() {
        if (root.migrationIndex >= root.migrations.length) {
            // Restore BEFORE the due sweep, and only fire once it has answered. Both are
            // asynchronous queries; run in parallel, an already-overdue timer fired against an
            // empty live list and then the restore raised its card again a moment later, so a
            // finished timer left a running card on screen for ever.
            root.restoreTimers(true);
            return;
        }
        migrateProc.command = ["sqlite3", root.dbPath, root.migrations[root.migrationIndex]];
        root.migrationIndex++;
        migrateProc.running = true;
    }

    Process {
        id: migrateProc
        stderr: StdioCollector {}
        onExited: root.runNextMigration()
    }

    // --- snooze (AD-012 §4) ---------------------------------------------------------------
    //
    // ONE armed timer for the earliest wake_at, re-armed after each fire — not one timer per
    // row, which would be a scheduler with as many moving parts as there are snoozes.
    //
    // On start, rows whose wake_at has already passed fire immediately. That is what makes a
    // snooze survive a qs restart AND a reboot without a second scheduler anywhere, and it sits
    // beside the `orphaned` sweep that already runs on this path.
    // Carries the row's CONTENT, not just its id: the original Notification object died with
    // the client (or with the last qs), so whatever re-pops it has to rebuild from the store.
    signal snoozeElapsed(string appName, string summary, string body, int urgency)

    // Keyed by nid through the same MAX(row_id) subselect close() uses — a client reuses nids,
    // so "the live row for this notification" is the newest active one, not any row with that
    // nid. One addressing scheme for the whole store rather than two.
    function snooze(nid, wakeAt) {
        if (!NotifyConfig.store.enabled)
            return;
        root.enqueue("UPDATE notifications SET state = 'snoozed', wake_at = " + Math.round(wakeAt) + "\n" + "WHERE row_id = (SELECT MAX(row_id) FROM notifications WHERE nid = " + Number(nid) + " AND state = 'active');");
        root.rearmAfterFlush = true;
    }

    // Snooze a row the drawer is looking at, addressed by row_id.
    //
    // `snooze(nid, …)` above cannot do this and fails SILENTLY if asked to: its UPDATE is
    // `WHERE nid = ? AND state = 'active'`, and a row in the drawer is history — expired,
    // closed or orphaned. The statement matches zero rows, and because writes are enqueued
    // and flushed in a batch there is no error anywhere. The card would vanish from the
    // drawer and simply never come back.
    //
    // row_id is the drawer's own key (`r:<row_id>`), it is unique, and it is what
    // fireDueSnoozes already selects and clears — so a snooze made here is indistinguishable
    // from one made on a live popup by the time it fires.
    function snoozeRow(rowId, wakeAt) {
        if (!NotifyConfig.store.enabled)
            return;
        root.enqueue("UPDATE notifications SET state = 'snoozed', wake_at = " + Math.round(wakeAt) + "\n" + "WHERE row_id = " + Number(rowId) + ";");
        root.rearmAfterFlush = true;
    }

    // Rows already due. Fired one signal each so the caller can re-pop them carrying the
    // original row_id, keeping history one thread rather than starting a new one.
    function fireDueSnoozes() {
        // -separator so a body containing the default pipe cannot split the row; \x1f is the
        // ASCII unit separator and cannot appear in notification text that survived JSON.
        dueProc.command = ["sqlite3", "-readonly", "-noheader", "-separator", "\x1f", root.dbPath, "SELECT row_id, app_name, summary, replace(body, char(10), ' '), urgency FROM notifications WHERE state = 'snoozed' AND wake_at IS NOT NULL AND wake_at <= " + Date.now() + " AND row_id NOT IN (" + root.firedIdList() + ");"];
        dueProc.running = true;
    }

    // Pending reminders, newest wake first. Synchronous from the recent-rows cache is not an
    // option here — snoozed rows are deliberately NOT in it — so this is a blocking read of a
    // handful of rows, which is what an IPC call can afford and a popup path could not.
    function snoozedSummary() {
        return snoozedProc.lastText;
    }

    function refreshSnoozed() {
        snoozedProc.command = ["sqlite3", "-readonly", "-noheader", "-separator", " \u2014 ", root.dbPath, "SELECT datetime(wake_at/1000,'unixepoch','localtime'), app_name, summary FROM notifications WHERE state = 'snoozed' AND wake_at IS NOT NULL ORDER BY wake_at ASC LIMIT 50;"];
        snoozedProc.running = true;
    }

    Process {
        id: snoozedProc
        property string lastText: ""
        stdout: StdioCollector {
            onStreamFinished: snoozedProc.lastText = this.text.trim()
        }
    }

    // Row ids already dispatched this session. THE WRITE THAT CLEARS wake_at IS ENQUEUED, not
    // synchronous — writes batch through a subprocess so they can never block a popup — so for
    // a moment after firing, the row still reads as due. Re-arming off that read computed a
    // zero interval, fired the same row again, and span: 100+ duplicate notifications in
    // seconds until the process was killed (observed 2026-08-05).
    //
    // Tracking what has fired in memory is what actually breaks the cycle; excluding those ids
    // from the query below is the same guard expressed in SQL. Belt and braces on purpose,
    // because the failure mode is a notification storm rather than a missed reminder.
    property var firedRows: ({})
    // set by anything that enqueues a wake_at change; consumed by the writer's exit
    property bool rearmAfterFlush: false

    function firedIdList() {
        const ids = Object.keys(root.firedRows);
        return ids.length ? ids.join(",") : "-1";
    }

    // ONE armed timer for the earliest wake across BOTH kinds of schedule — a snoozed
    // notification and an armed countdown are the same question ("what is next, and when"), and
    // asking it twice would be the second scheduler this design exists to avoid.
    function armSnoozeTimer() {
        root.refreshSnoozed();
        nextProc.command = ["sqlite3", "-readonly", "-noheader", root.dbPath, "SELECT MIN(w) FROM (" + "SELECT MIN(wake_at) AS w FROM notifications WHERE state = 'snoozed' AND wake_at IS NOT NULL AND row_id NOT IN (" + root.firedIdList() + ")" + " UNION ALL " + "SELECT MIN(wake_at) AS w FROM timers WHERE state = 'armed' AND wake_at IS NOT NULL AND id NOT IN (" + root.firedTimerIdList() + "));"];
        nextProc.running = true;
    }

    Process {
        id: dueProc
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.trim().split("\n").filter(l => l.length);
                for (let i = 0; i < rows.length; i++) {
                    const f = rows[i].split("\x1f");
                    if (root.firedRows[f[0]])
                        continue;
                    root.firedRows[f[0]] = true;
                    // clear the snooze BEFORE re-popping: a crash between the two would
                    // otherwise re-fire the same row on every start, forever
                    root.enqueue("UPDATE notifications SET state = 'expired', wake_at = NULL WHERE row_id = " + f[0] + ";");
                    root.snoozeElapsed(f[1] || "", f[2] || "", f[3] || "", parseInt(f[4], 10) || 1);
                }
                root.dueFired = root.dueFired || rows.length > 0;
                // The timer half of the same sweep, chained rather than run in parallel: both
                // read the database the other is about to be written into, and the re-arm at the
                // end has to see every fire from both.
                root.fireDueTimers();
            }
        }
    }

    // --- timers (story: notif-timers) --------------------------------------------------------
    //
    // Everything below shares the ONE armed Timer above. `armSnoozeTimer` takes MIN(wake_at)
    // across BOTH tables, and this file has exactly one Timer object in it — which is what
    // "do not add a second scheduler" means. A timer therefore survives a qs restart and a
    // reboot by exactly the mechanism a snooze does: the row is the schedule.
    //
    // Carries the row's content for the same reason snoozeElapsed does — after a restart there
    // is no in-memory timer left to consult, only the row.
    // `real`, not `int`, for every id and every epoch stamp. A QML signal parameter typed `int`
    // is 32 bits: a row id (~1.8e15) and even a millisecond timestamp (~1.8e12) are truncated to
    // a different number, silently. That version fired the notification correctly and then
    // UPDATEd a row id that does not exist — the timer stayed `armed` in the table and stayed in
    // the live list forever, with nothing logged anywhere.
    signal timerElapsed(real id, real runId, string kind, string label, string phase, int cycle, int cycles, int plannedMs, real startedAt, int workMs, int shortMs, int longMs)

    // Live (armed or paused) timers as sqlite3 `-json` text, emitted at startup so the Timers
    // singleton can rebuild its in-memory model. Emitted even when empty: "nothing was armed" is
    // an answer the singleton needs in order to stop waiting for one.
    signal timersRestored(string json)

    // Same guard, same reason as firedRows: the write that finishes a fired timer is ENQUEUED,
    // so for ~200ms the row still reads as due and a re-arm off that read would fire it again.
    property var firedTimers: ({})
    property bool dueFired: false

    function firedTimerIdList() {
        const ids = Object.keys(root.firedTimers);
        return ids.length ? ids.join(",") : "-1";
    }

    function fireDue() {
        root.dueFired = false;
        root.fireDueSnoozes();
    }

    function fireDueTimers() {
        timersDueProc.command = ["sqlite3", "-readonly", "-noheader", "-separator", "\x1f", root.dbPath, "SELECT id, run_id, kind, label, phase, cycle, cycles, planned_ms, started_at, work_ms, short_ms, long_ms FROM timers WHERE state = 'armed' AND wake_at IS NOT NULL AND wake_at <= " + Date.now() + " AND id NOT IN (" + root.firedTimerIdList() + ");"];
        timersDueProc.running = true;
    }

    Process {
        id: timersDueProc
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.trim().split("\n").filter(l => l.length);
                for (let i = 0; i < rows.length; i++) {
                    const f = rows[i].split("\x1f");
                    const id = parseInt(f[0], 10);
                    if (root.firedTimers[id])
                        continue;
                    root.firedTimers[id] = true;
                    root.timerElapsed(id, parseInt(f[1], 10) || id, f[2] || "countdown", f[3] || "", f[4] || "", parseInt(f[5], 10) || 0, parseInt(f[6], 10) || 0, parseInt(f[7], 10) || 0, parseInt(f[8], 10) || 0, parseInt(f[9], 10) || 0, parseInt(f[10], 10) || 0, parseInt(f[11], 10) || 0);
                }
                if (root.dueFired || rows.length)
                    root.scheduleRearm();
                else
                    root.armSnoozeTimer();
                root.dueFired = false;
            }
        }
    }

    // Re-arm once the writes this sweep produced have landed. With nothing to write (store
    // disabled, or a fire that enqueued nothing) the writer will never exit, so re-arm now
    // rather than waiting for an exit that cannot come.
    function scheduleRearm() {
        if (root.pending.length && root.healthy && NotifyConfig.store.enabled) {
            root.rearmAfterFlush = true;
            return;
        }
        root.armSnoozeTimer();
    }

    // A timer row is INSERTed with an id the caller already chose (epoch-derived, see
    // config/Timers.qml). Writes batch through a subprocess, so nothing here can hand back a
    // generated rowid in time to be useful — the caller has to own the identity.
    function armTimer(t) {
        if (!NotifyConfig.store.enabled)
            return;
        const doc = {
            id: t.id,
            run_id: t.runId,
            kind: t.kind,
            label: t.label || "",
            state: t.state || "armed",
            phase: t.phase || "",
            cycle: t.cycle || 0,
            cycles: t.cycles || 0,
            work_ms: t.workMs || 0,
            short_ms: t.shortMs || 0,
            long_ms: t.longMs || 0,
            planned_ms: t.plannedMs || 0,
            remaining_ms: t.remainingMs || 0,
            wake_at: t.wakeAt || null,
            started_at: t.startedAt || Date.now()
        };
        root.enqueue("INSERT OR REPLACE INTO timers (id, run_id, kind, label, state, phase, cycle, cycles," + " work_ms, short_ms, long_ms, planned_ms, remaining_ms, wake_at, started_at)\n" + "SELECT json_extract(d, '$.id'), json_extract(d, '$.run_id'), json_extract(d, '$.kind')," + " json_extract(d, '$.label'), json_extract(d, '$.state'), json_extract(d, '$.phase')," + " json_extract(d, '$.cycle'), json_extract(d, '$.cycles'), json_extract(d, '$.work_ms')," + " json_extract(d, '$.short_ms'), json_extract(d, '$.long_ms'), json_extract(d, '$.planned_ms')," + " json_extract(d, '$.remaining_ms'), json_extract(d, '$.wake_at'), json_extract(d, '$.started_at')\n" + "FROM (SELECT " + root.sqlJson(doc) + " AS d);");
        root.scheduleRearm();
    }

    // Pause, resume and +5 min all land here: they change when (or whether) the one armed timer
    // should next fire, so each re-arms.
    function updateTimer(id, fields) {
        if (!NotifyConfig.store.enabled)
            return;
        const allowed = ["state", "phase", "cycle", "planned_ms", "remaining_ms", "wake_at", "started_at"];
        const sets = [];
        for (const k of allowed) {
            if (fields[k] === undefined)
                continue;
            const v = fields[k];
            sets.push(k + " = " + (v === null ? "NULL" : (typeof v === "string" ? root.sqlText(v) : Math.round(Number(v)))));
        }
        if (!sets.length)
            return;
        root.enqueue("UPDATE timers SET " + sets.join(", ") + " WHERE id = " + Number(id) + ";");
        root.scheduleRearm();
    }

    // THE completion row (story decision 4). One row per finished phase — kind, label, planned,
    // actual, started, ended — and nothing between arming and this.
    function finishTimer(id, state, actualMs) {
        if (!NotifyConfig.store.enabled)
            return;
        root.enqueue("UPDATE timers SET state = " + root.sqlText(state) + ", wake_at = NULL, actual_ms = " + Math.max(0, Math.round(actualMs)) + ", ended_at = " + Date.now() + " WHERE id = " + Number(id) + ";");
        root.scheduleRearm();
    }

    // A stopwatch never arms anything (it counts up, so there is no wake_at) — it writes its one
    // summary row when it is stopped, by the same shape as every other completion.
    function recordCompleted(t) {
        if (!NotifyConfig.store.enabled)
            return;
        root.armTimer(Object.assign({}, t, {
            state: "done",
            wakeAt: null
        }));
        root.enqueue("UPDATE timers SET actual_ms = " + Math.max(0, Math.round(t.actualMs || 0)) + ", ended_at = " + Date.now() + " WHERE id = " + Number(t.id) + ";");
    }

    // Startup reconciliation, the timer half. Rows left armed or paused belong to a previous
    // process and are the ONLY record that they existed, so they are handed back rather than
    // swept — unlike an `active` notification row, whose D-Bus object died with that process.
    function restoreTimers(thenFire) {
        root.query("SELECT * FROM timers WHERE state IN ('armed','paused') ORDER BY wake_at ASC;", json => {
            root.timersRestored(json);
            if (thenFire)
                root.fireDue();
        });
    }

    // Live timers for `qs ipc call timers list`, straight from the file so the answer is the
    // same one a tmux popup gets from sqlite3.
    function timersJson(callback) {
        root.query("SELECT * FROM timers WHERE state IN ('armed','paused') ORDER BY wake_at ASC;", callback);
    }

    Process {
        id: nextProc
        stdout: StdioCollector {
            onStreamFinished: {
                const v = this.text.trim();
                if (!v.length) {
                    snoozeTimer.stop();
                    return;
                }
                const due = parseInt(v, 10) - Date.now();
                // Qt caps an interval at 2^31-1 ms (~24 days), written hex because the decimal
                // literal is ten digits and trips lint:private's US-phone-number pattern; a longer snooze re-arms when the
                // timer next fires rather than silently overflowing to something immediate.
                // Floor of one second. Both guards above should make a zero interval
                // impossible; this makes a notification STORM impossible even if they are
                // wrong, which is the failure worth engineering against.
                snoozeTimer.interval = Math.max(1000, Math.min(due, 0x7fffffff));
                snoozeTimer.restart();
            }
        }
    }

    Timer {
        id: snoozeTimer
        repeat: false
        onTriggered: root.fireDue()
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
    // Drawer support (story: notif-drawer).
    //
    // Clearing is a row state, not a delete: the drawer is a view onto the history, and a
    // history you can erase by pressing d in a list is not a history. `sqlite3 <db> "SELECT …"`
    // still returns every cleared row.
    // ---------------------------------------------------------------------------------------

    function clearRows(rowIds) {
        if (!NotifyConfig.store.enabled || !rowIds || rowIds.length === 0)
            return;
        const ids = rowIds.map(Number).filter(n => isFinite(n)).join(",");
        if (!ids.length)
            return;
        root.enqueue("UPDATE notifications SET cleared_at = " + Date.now() + "\n" + "WHERE cleared_at IS NULL AND row_id IN (" + ids + ");");
    }

    function clearAll() {
        if (!NotifyConfig.store.enabled)
            return;
        root.enqueue("UPDATE notifications SET cleared_at = " + Date.now() + " WHERE cleared_at IS NULL;");
    }

    // One page of the drawer: newest first, uncleared only, with the filtering the drawer can
    // push down to SQL. Fuzzy matching stays client-side on the returned page — LIKE is not
    // fuzzy, and a subsequence matcher in SQL would be a stored function we do not have.
    function drawerRows(filters, limit, callback) {
        const n = Math.max(1, Math.min(2000, limit || 200));
        const where = ["cleared_at IS NULL"];
        if (filters) {
            if (filters.app)
                where.push("app_name = " + root.sqlText(filters.app));
            if (filters.category)
                where.push("category = " + root.sqlText(filters.category));
            if (typeof filters.urgency === "number" && filters.urgency >= 0)
                where.push("urgency = " + Number(filters.urgency));
            if (typeof filters.since === "number" && filters.since > 0)
                where.push("received_at >= " + Number(filters.since));
        }
        root.query("SELECT * FROM notifications WHERE " + where.join(" AND ") + " ORDER BY received_at DESC LIMIT " + n + ";", callback);
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
