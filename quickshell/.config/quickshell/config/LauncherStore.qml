pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Selection history for the launcher: every pick the user makes — an app, a run command, a
// file, an emoji, a glyph, an icon name, a wallpaper — is one row here, and `components/
// Launcher.qml` ranks its results on it. Modelled directly on `config/NotifyStore.qml`, whose
// header is the long-form argument for every choice repeated below.
//
// WHY THE sqlite3 CLI AND NOT QtQuick.LocalStorage. LocalStorage puts the database at a hashed
// filename under the offline-storage path. This file is meant to be read by hand:
//
//   sqlite3 -readonly ~/.local/share/quickshell/launcher.db \
//     "SELECT kind, key, hits, round(score,2) FROM selections ORDER BY score DESC LIMIT 20;"
//
// RANKING READS MEMORY, NEVER THE FILE. `Launcher.refresh()` runs on every keystroke, so a
// subprocess on that path would make the launcher feel broken. The whole table is loaded once
// at startup into `stats`, re-read after each write batch flushes, and `scoreOf()` / `pinFor()`
// are plain object lookups. Nothing on the read path starts a process.
//
// WRITES NEVER BLOCK A LAUNCH. Statements queue and flush through one subprocess per batch. A
// failure logs once, sets `healthy = false`, and the launcher carries on with no ranking at
// all — a broken store degrades the ordering, never the launcher.
//
//   file: ${XDG_DATA_HOME:-~/.local/share}/quickshell/launcher.db
//   env:  QS_LAUNCHER_DB=<path>   use this database instead (the same path seam as
//                                 QS_NOTIFY_DB: a nested session or a test writes its own file)
Singleton {
    id: root

    readonly property int schemaVersion: 1

    readonly property string dbPath: {
        const explicit = Quickshell.env("QS_LAUNCHER_DB");
        if (explicit)
            return explicit;
        const share = Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share");
        return share + "/quickshell/launcher.db";
    }

    readonly property bool enabled: Shell.launcherHistoryEnabled
    // 30 days, from Shell.launcherHalfLifeDays (QS_LAUNCHER_HALFLIFE_DAYS). A week is eager and
    // forgetful, a quarter is stubborn; this is one constant to live with and adjust once.
    readonly property real halfLifeMs: Shell.launcherHalfLifeDays * 86400000

    // Age AND count, both enforced at startup and then hourly, exactly as NotifyStore does it.
    readonly property int retentionDays: 365
    readonly property int retentionCount: 5000

    // false once a write or the initial open has failed: the store is off, the launcher is not
    property bool healthy: true
    // the schema statement has run
    property bool ready: false
    // The table has been read into `stats` at least once. record() waits for THIS, not for
    // `ready`: the decaying upsert multiplies the row's stored score by a factor taken from the
    // memory map, so writing before the map exists would reset a hot row to 1.0.
    property bool loaded: false

    // ---------------------------------------------------------------------------------------
    // The in-memory ranking map. THIS is what the keystroke path reads.
    //
    //   stats["<kind>\x1f<key>"] = { raw, hits, lastUsedAt, label, rank }
    //
    // `raw` is the score exactly as the file holds it: decayed up to `lastUsedAt` and no
    // further, because that is what the decaying upsert multiplies. `rank` is the same number
    // brought into ONE common reference frame (`rankAt`, the moment the table was read), so two
    // rows are comparable without a pow() per row per keystroke. A row touched during this
    // session has its `rank` recomputed against that same `rankAt`, which is why its factor can
    // be greater than 1 — the age is negative.
    // ---------------------------------------------------------------------------------------
    property var stats: ({})
    property real rankAt: 0
    // kind -> key of the most recently selected row of that kind. The empty-query pin.
    property var recent: ({})
    // bumped whenever `stats` changes, so a visible launcher can re-rank itself
    property int revision: 0

    signal changed

    function entryKey(kind, key) {
        return String(kind) + "\x1f" + String(key);
    }

    // pow(0.5, age / halfLife). A negative age (a row touched after `rankAt`) gives a factor
    // above 1, which is correct: it is the same score expressed at an earlier reference time.
    function decayFactor(ageMs) {
        if (!(root.halfLifeMs > 0))
            return 1;
        return Math.pow(0.5, ageMs / root.halfLifeMs);
    }

    // Decayed usage for one item, or 0 for one never selected. An object lookup — no I/O.
    function scoreOf(kind, key) {
        if (!key)
            return 0;
        const e = root.stats[root.entryKey(kind, key)];
        return e ? e.rank : 0;
    }

    // The key that gets `isMostRecent` for a kind — exactly one row, and only when the query is
    // empty. Per KIND rather than globally, so opening emoji pins the last emoji and not the
    // last app.
    function pinFor(kind) {
        return root.recent[kind] || "";
    }

    // ---------------------------------------------------------------------------------------
    // SQL plumbing. The same single escaping rule as NotifyStore: a value reaches SQL inside one
    // quoted string and `'` is doubled. There is no second escaping context here — do not
    // reintroduce per-column quoting.
    // ---------------------------------------------------------------------------------------

    function sqlText(s) {
        return "'" + String(s).replace(/'/g, "''") + "'";
    }

    property var pending: []

    function enqueue(sql) {
        if (!root.healthy || !root.enabled)
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
        writer.command = ["sqlite3", root.dbPath, "BEGIN IMMEDIATE;\n" + batch.join("\n") + "\nCOMMIT;"];
        writer.running = true;
    }

    function fail(what, detail) {
        if (!root.healthy)
            return;
        root.healthy = false;
        root.pending = [];
        console.warn("launcher: history disabled —", what, detail || "");
    }

    Timer {
        id: flushTimer
        interval: 200 // coalesce a burst of picks into one subprocess
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
            // Re-read once the batch has landed — the same "nothing may read its own enqueued
            // write" rule NotifyStore learned. record() has already moved the memory map in
            // place, so this is the reconciliation with what the file actually holds, including
            // anything retention removed.
            root.load();
        }
    }

    // ---------------------------------------------------------------------------------------
    // Schema. CREATE TABLE IF NOT EXISTS on every start, so a deleted database heals itself and
    // a fresh machine needs no install step.
    //
    // `hits` is the raw lifetime count and is NEVER decayed — it is there so the table reads
    // sensibly by hand. `score` is the decayed counter, and it is what ranking sorts on.
    // ---------------------------------------------------------------------------------------
    readonly property string schemaSql: "PRAGMA journal_mode=WAL;\n" +
        // WAL is what lets a script or an SSH session read while the daemon writes.
        "CREATE TABLE IF NOT EXISTS selections (\n" + "  kind          TEXT NOT NULL,\n" + "  key           TEXT NOT NULL,\n" + "  label         TEXT,\n" + "  hits          INTEGER NOT NULL DEFAULT 0,\n" + "  score         REAL    NOT NULL DEFAULT 0,\n" + "  first_used_at INTEGER NOT NULL,\n" + "  last_used_at  INTEGER NOT NULL,\n" + "  PRIMARY KEY (kind, key)\n" + ");\n" + "CREATE INDEX IF NOT EXISTS selections_recent ON selections (kind, last_used_at DESC);\n" + "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);\n" + "INSERT INTO meta(key, value) VALUES ('schema_version', '" + root.schemaVersion + "')\n" + "  ON CONFLICT(key) DO UPDATE SET value = excluded.value;\n"

    // mkdir -p the parent: sqlite3 will not create a missing directory, and a first run on a new
    // machine has no ~/.local/share/quickshell yet.
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

    Process {
        id: initProc
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fail("could not open " + root.dbPath, initProc.stderr.text.trim());
                return;
            }
            root.ready = true;
            root.probeMath();
            root.prune();
            root.load();
        }
    }

    // ---------------------------------------------------------------------------------------
    // pow() is not a given, and finding that out at the first write is too late.
    //
    // The decaying upsert multiplies by pow(0.5, age/halfLife), which lives in SQLite's math
    // functions: compiled in since 3.35, but only when the build asks for them. On this very
    // host a bare `sqlite3` resolves through mise to the ANDROID platform-tools build (3.50.6),
    // which has no pow, no exp and no ln, while /usr/bin/sqlite3 (3.53.4) has all three. So
    // which binary wins $PATH inside the qs process decides whether every write dies with
    // "no such function: pow" — that is, whether the feature silently switches itself off.
    //
    // The factor is therefore probed once, and where it is missing it is computed in QML and
    // written as a literal instead. Both forms produce the same number: the memory map holds the
    // row's `lastUsedAt`, this daemon is the only writer, and record() refuses to run until the
    // load has answered. The SQL form is kept where it works because it is self-contained — a
    // row touched by any other writer still decays correctly.
    //
    // Defaults to FALSE so the first write cannot race the probe onto a binary with no pow() and
    // take the whole batch down with it. The QML factor is always correct; the SQL form is the
    // refinement, not the fallback.
    property bool mathOk: false

    function probeMath() {
        mathProc.command = ["sqlite3", "-readonly", "-noheader", root.dbPath, "SELECT pow(0.5, 1.0);"];
        mathProc.running = true;
    }

    Process {
        id: mathProc
        stderr: StdioCollector {}
        onExited: exitCode => {
            root.mathOk = exitCode === 0;
            if (!root.mathOk)
                console.info("launcher: this sqlite3 has no pow() — decaying the score in QML instead");
        }
    }

    // ---------------------------------------------------------------------------------------
    // The load. One subprocess, at startup and after each write batch — never on a keystroke.
    // The async `sqlite3 -json` shape is NotifyStore.query()'s.
    // ---------------------------------------------------------------------------------------

    function load() {
        if (!root.ready || !root.healthy || !root.enabled)
            return;
        loadProc.command = ["sqlite3", "-json", "-readonly", root.dbPath, "SELECT kind, key, label, hits, score, last_used_at FROM selections;"];
        loadProc.running = true;
    }

    function applyRows(rows) {
        const now = Date.now();
        const next = {};
        const newest = {};
        const newestAt = {};
        for (var i = 0; i < rows.length; i++) {
            const r = rows[i];
            if (!r || !r.kind || r.key === undefined || r.key === null)
                continue;
            const last = Number(r.last_used_at) || 0;
            const raw = Number(r.score) || 0;
            next[root.entryKey(r.kind, r.key)] = {
                raw: raw,
                hits: Number(r.hits) || 0,
                lastUsedAt: last,
                label: r.label || "",
                // A row nobody has selected in months fades with no write of its own: the same
                // pow(0.5, age/halfLife) the upsert applies, applied once, here.
                rank: raw * root.decayFactor(now - last)
            };
            if (!newestAt[r.kind] || last > newestAt[r.kind]) {
                newestAt[r.kind] = last;
                newest[r.kind] = String(r.key);
            }
        }
        root.rankAt = now;
        root.loaded = true;
        root.stats = next;
        root.recent = newest;
        root.revision++;
        root.changed();
    }

    Process {
        id: loadProc
        stderr: StdioCollector {}
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim();
                try {
                    root.applyRows(out.length ? JSON.parse(out) : []);
                } catch (e) {
                    console.warn("launcher: history unreadable —", e);
                    root.applyRows([]);
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.fail("could not read " + root.dbPath, loadProc.stderr.text.trim());
        }
    }

    // ---------------------------------------------------------------------------------------
    // Recording. One call per branch of Launcher.activate(), with the STABLE identity as the
    // key — a desktop-entry id, a command, a path, a character — never the display string,
    // which is localised and changes.
    // ---------------------------------------------------------------------------------------

    function record(kind, key, label) {
        if (!root.enabled || !root.healthy || !root.loaded || !kind || !key)
            return;
        const now = Date.now();
        const id = root.entryKey(kind, key);
        const prev = root.stats[id];
        // The decay factor for THIS row, from its own last use. Computed here whether or not the
        // statement below uses it, because the memory map has to move in the same step: ranking
        // must be right immediately, not 200ms later when the batch flushes.
        const factor = prev ? root.decayFactor(now - prev.lastUsedAt) : 0;
        const raw = (prev ? prev.raw * factor : 0) + 1.0;

        const next = Object.assign({}, root.stats);
        next[id] = {
            raw: raw,
            hits: (prev ? prev.hits : 0) + 1,
            lastUsedAt: now,
            label: label || (prev ? prev.label : ""),
            // brought into the load's reference frame, so it stays comparable with every
            // untouched row without re-decaying the whole map
            rank: raw * root.decayFactor(root.rankAt - now)
        };
        root.stats = next;

        const nextRecent = Object.assign({}, root.recent);
        nextRecent[kind] = String(key);
        root.recent = nextRecent;
        root.revision++;

        // The decaying counter: multiply-add in the same statement that records the hit, so
        // there is no decay sweep anywhere and no per-read cost.
        const decay = root.mathOk ? "pow(0.5, (" + now + " - last_used_at) / " + root.halfLifeMs + ")" : String(factor);
        root.enqueue("INSERT INTO selections (kind, key, label, hits, score, first_used_at, last_used_at)\n" + "VALUES (" + root.sqlText(kind) + ", " + root.sqlText(key) + ", " + root.sqlText(label || "") + ", 1, 1.0, " + now + ", " + now + ")\n" + "ON CONFLICT(kind, key) DO UPDATE SET\n" + "  hits         = hits + 1,\n" + "  score        = score * " + decay + " + 1.0,\n" + "  label        = excluded.label,\n" + "  last_used_at = " + now + ";");
    }

    // The forget key (Ctrl+Del). Drops the HISTORY ROW ONLY — the app, file or emoji stays in
    // the results and falls back to its alphabetical position. A history the user cannot correct
    // is one they will resent.
    function forget(kind, key) {
        if (!root.enabled || !kind || !key)
            return;
        const id = root.entryKey(kind, key);
        if (root.stats[id]) {
            const next = Object.assign({}, root.stats);
            delete next[id];
            root.stats = next;
        }
        if (root.recent[kind] === String(key)) {
            const nextRecent = Object.assign({}, root.recent);
            delete nextRecent[kind];
            root.recent = nextRecent;
        }
        root.revision++;
        root.enqueue("DELETE FROM selections WHERE kind = " + root.sqlText(kind) + " AND key = " + root.sqlText(key) + ";");
    }

    // ---------------------------------------------------------------------------------------
    // Retention. Age AND count, at startup and then hourly, in the background.
    // ---------------------------------------------------------------------------------------

    function prune() {
        if (!root.ready || !root.healthy || !root.enabled)
            return;
        var sql = "";
        if (root.retentionDays > 0)
            sql += "DELETE FROM selections WHERE last_used_at < " + (Date.now() - root.retentionDays * 86400000) + ";\n";
        if (root.retentionCount > 0)
            sql += "DELETE FROM selections WHERE rowid NOT IN (SELECT rowid FROM selections ORDER BY last_used_at DESC LIMIT " + root.retentionCount + ");\n";
        if (sql.length)
            root.enqueue(sql);
    }

    Timer {
        interval: 3600000
        repeat: true
        running: root.ready && root.healthy && root.enabled
        onTriggered: root.prune()
    }

    // ---------------------------------------------------------------------------------------

    Component.onCompleted: {
        if (!root.enabled)
            return;
        const at = root.dbPath.lastIndexOf("/");
        mkdirProc.command = ["mkdir", "-p", at > 0 ? root.dbPath.substring(0, at) : "."];
        mkdirProc.running = true;
    }
}
