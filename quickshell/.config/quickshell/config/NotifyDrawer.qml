pragma Singleton

import QtQuick
import Quickshell

// Notification drawer state (story: notif-drawer).
//
// The drawer is a view over the SQLite store, NOT over the live popup list: its whole reason
// to exist is that a popup you already let expire is still reachable. Rows come from
// NotifyStore; the only thing read from Notifications is whether a row is still on screen, so
// dismissing from the drawer can close the live card too.
//
// Everything here is data and selection. components/NotificationDrawer.qml turns it into
// pixels and owns no state of its own, the same split the popup stack uses.
Singleton {
    id: root

    readonly property var config: NotifyConfig.drawer

    property bool shown: false
    // "panel" — full-height slide-out from the right edge.
    // "modal" — centred, launcher-shaped. Same data, same keys; a display choice, not a mode.
    readonly property string mode: root.config.mode

    // ---------------------------------------------------------------------------------------
    // Rows
    // ---------------------------------------------------------------------------------------

    property var rows: []            // straight from sqlite3 -json, newest first
    property bool loading: false
    property string search: ""

    // Filters pushed down to SQL. `urgency: -1` and empty strings mean "no filter".
    property string filterApp: ""
    property string filterCategory: ""
    property int filterUrgency: -1
    property string filterRange: "all"   // all | hour | today | week
    // Pending reminders only. A CLIENT-side filter, unlike app/category/urgency/range: those
    // narrow the SQL query, and this one must not. `state` changes under the drawer while it is
    // open — a row snoozed a second ago is patched in memory by markSnoozed, and the write it
    // came from has not flushed yet — so a WHERE clause would disagree with what the user just
    // did until the next reload.
    property bool filterSnoozed: false

    readonly property var ranges: ({
            all: 0,
            hour: 3600000,
            today: 86400000,
            week: 604800000
        })

    function refresh() {
        if (!NotifyStore.healthy) {
            root.rows = [];
            return;
        }
        root.loading = true;
        const span = root.ranges[root.filterRange] || 0;
        NotifyStore.drawerRows({
            app: root.filterApp,
            category: root.filterCategory,
            urgency: root.filterUrgency,
            since: span > 0 ? Date.now() - span : 0
        }, root.config.limit, text => {
            root.loading = false;
            try {
                root.rows = JSON.parse(text) || [];
            } catch (e) {
                console.warn("notifications: drawer query unreadable —", e);
                root.rows = [];
            }
            root.reselect();
        });
    }

    // Subsequence match, the same shape the launcher uses: "bldfl" finds "Build failed".
    // Deliberately not fuzzy-scored — ranking by score would reorder the list under the user
    // as they type, and this list is chronological for a reason.
    function matches(row, needle) {
        if (root.filterSnoozed && row.state !== "snoozed")
            return false;
        if (!needle)
            return true;
        const hay = ((row.app_name || "") + " " + (row.summary || "") + " " + (row.body || "") + " " + (row.category || "")).toLowerCase();
        const q = needle.toLowerCase();
        if (hay.indexOf(q) >= 0)
            return true;
        var i = 0;
        for (var c = 0; c < hay.length && i < q.length; c++)
            if (hay[c] === q[i])
                i++;
        return i === q.length;
    }

    readonly property var filtered: {
        const out = [];
        for (const r of root.rows)
            if (root.matches(r, root.search))
                out.push(r);
        return out;
    }

    // ---------------------------------------------------------------------------------------
    // Grouping. By app until the grouping story gives rows a real group_key, which this reads
    // first so the drawer starts using it the moment it is populated.
    // ---------------------------------------------------------------------------------------

    property var collapsed: ({})

    function groupOf(row) {
        return row.group_key || row.app_name || "unknown";
    }

    function isCollapsed(name) {
        return root.collapsed[name] === true;
    }

    function toggleGroup(name) {
        const next = Object.assign({}, root.collapsed);
        next[name] = !next[name];
        root.collapsed = next;
    }

    // [{ name, count, unread, urgency, rows: [...] }], groups in first-seen (newest) order.
    readonly property var groups: {
        const order = [];
        const byName = {};
        for (const r of root.filtered) {
            const name = root.groupOf(r);
            if (!byName[name]) {
                byName[name] = {
                    name: name,
                    count: 0,
                    unread: 0,
                    urgency: 0,
                    rows: []
                };
                order.push(byName[name]);
            }
            const g = byName[name];
            g.rows.push(r);
            g.count++;
            if (!r.read_at)
                g.unread++;
            g.urgency = Math.max(g.urgency, r.urgency || 0);
        }
        return order;
    }

    // What the list actually renders: group headers interleaved with their rows, with a
    // collapsed group contributing only its header. One flat model keeps j/k moving through
    // headers and rows in the order they are drawn, which is the only way the keys read right.
    readonly property var items: {
        const out = [];
        for (const g of root.groups) {
            out.push({
                kind: "group",
                key: "g:" + g.name,
                group: g
            });
            if (root.isCollapsed(g.name))
                continue;
            for (const r of g.rows)
                out.push({
                    kind: "row",
                    key: "r:" + r.row_id,
                    row: r,
                    group: g
                });
        }
        return out;
    }

    // ---------------------------------------------------------------------------------------
    // Selection. Keyed like the popup stack's: an identity, not an index, because the list is
    // rebuilt under it on every refresh, filter change and keystroke.
    // ---------------------------------------------------------------------------------------

    property string selectedKey: ""

    readonly property int selectedIndex: {
        for (var i = 0; i < root.items.length; i++)
            if (root.items[i].key === root.selectedKey)
                return i;
        return -1;
    }

    readonly property var selected: root.selectedIndex >= 0 ? root.items[root.selectedIndex] : null

    // Custom actions available on the selected row. Custom ONLY — a spec action is invoked by
    // handing it back to the client, and by the time a row is history that process has usually
    // exited. See Notifications.actionsForRow.
    readonly property var selectedActions: {
        // see NotificationCard: touch the config so the binding re-runs when TOML lands
        NotifyConfig.actions;
        // …and NotifyConfig.snooze, which the built-in snooze verbs read for their durations
        // and labels. Same reason: a dependency is not discovered through a function call into
        // another singleton, so without this the row's verbs keep whatever the defaults were
        // when the binding first ran.
        NotifyConfig.snooze;
        const sel = root.selected;
        if (!sel || sel.kind === "group")
            return [];
        return Notifications.actionsForRow(sel.row ? sel.row : sel);
    }

    function invokeActionByKey(letter) {
        const list = root.selectedActions;
        for (let i = 0; i < list.length; i++) {
            if (list[i].key === letter) {
                const sel = root.selected;
                const row = sel.row ? sel.row : sel;
                const wake = Notifications.invokeRowAction(row, list[i], "");
                // A snooze changes the row under the cursor, and the write flushes ~200ms
                // later — so the list is patched from the returned stamp rather than reloaded.
                // Without this the row keeps its old state and the drawer shows no sign that
                // anything happened, which is exactly how this landed the first time.
                if (list[i].kind === "snooze" && wake > 0)
                    root.markSnoozed(row.row_id, wake);
                return true;
            }
        }
        return false;
    }

    // Patch one row in place. `rows` is reassigned rather than mutated because a QML binding
    // does not re-run when an element of the array it read is changed underneath it.
    function markSnoozed(rowId, wake) {
        root.rows = root.rows.map(r => r.row_id === rowId ? Object.assign({}, r, {
            state: "snoozed",
            wake_at: wake
        }) : r);
    }

    // `p` opens the selected ROW in the centred compose surface, hosted by this window so the
    // drawer keeps the keyboard grab. A row still on screen re-associates to its live entry in
    // NotifyCompose.openRow, which is the only way a reply from history can reach a client.
    function composeSelected() {
        const sel = root.selected;
        if (!sel || sel.kind === "group")
            return false;
        return NotifyCompose.openRow(sel.row, "drawer");
    }

    function reselect() {
        if (root.selectedIndex >= 0)
            return;
        root.selectedKey = root.items.length ? root.items[0].key : "";
    }

    onItemsChanged: root.reselect()

    function selectAt(i) {
        if (root.items.length === 0)
            return;
        root.selectedKey = root.items[Math.max(0, Math.min(root.items.length - 1, i))].key;
    }

    function move(delta) {
        root.selectAt(root.selectedIndex < 0 ? 0 : root.selectedIndex + delta);
    }
    function first() {
        root.selectAt(0);
    }
    function last() {
        root.selectAt(root.items.length - 1);
    }

    // ---------------------------------------------------------------------------------------
    // Open / close
    // ---------------------------------------------------------------------------------------

    function open() {
        if (root.shown)
            return;
        root.search = "";
        root.shown = true;
        root.refresh();
        // Opening the drawer IS reading them: the bell count is "since you last looked", and
        // this is looking.
        Notifications.markRead();
    }

    function close() {
        root.shown = false;
    }

    function toggle() {
        if (root.shown)
            root.close();
        else
            root.open();
    }

    // New notifications while the drawer is open should appear in it, but only while it is
    // open — a background refresh on every notification would query the database all day.
    Connections {
        target: Notifications
        function onPopupsChanged() {
            if (root.shown)
                refreshDebounce.restart();
        }
    }

    Timer {
        id: refreshDebounce
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    // ---------------------------------------------------------------------------------------
    // Acting on rows
    //
    // A row may still be on screen. Clearing it from the drawer must close that card too, or
    // the popup outlives the thing the user just dealt with.
    // ---------------------------------------------------------------------------------------

    function liveEntryFor(row) {
        if (!row || row.state !== "active")
            return null;
        return Notifications.entryForId(row.nid);
    }

    function clearRow(row) {
        if (!row)
            return;
        const live = root.liveEntryFor(row);
        if (live)
            Notifications.dismiss(live);
        NotifyStore.clearRows([row.row_id]);
        root.rows = root.rows.filter(r => r.row_id !== row.row_id);
    }

    function clearGroup(group) {
        if (!group)
            return;
        const ids = [];
        for (const r of group.rows) {
            const live = root.liveEntryFor(r);
            if (live)
                Notifications.dismiss(live);
            ids.push(r.row_id);
        }
        NotifyStore.clearRows(ids);
        root.rows = root.rows.filter(r => ids.indexOf(r.row_id) < 0);
    }

    // Everything currently listed, which is what the button says — not the whole history, and
    // not rows hidden behind the active filter.
    function clearAll() {
        const ids = root.filtered.map(r => r.row_id);
        for (const r of root.filtered) {
            const live = root.liveEntryFor(r);
            if (live)
                Notifications.dismiss(live);
        }
        NotifyStore.clearRows(ids);
        root.rows = root.rows.filter(r => ids.indexOf(r.row_id) < 0);
    }

    // Enter: a group folds, a row unfolds to its full body. Invoking a stored notification's
    // actions needs the actions story; expanding it does not, and "read the rest of this" is
    // what Enter means on the popup stack too.
    property var expandedRows: ({})

    function isExpanded(rowId) {
        return root.expandedRows[rowId] === true;
    }

    function toggleRow(rowId) {
        const next = Object.assign({}, root.expandedRows);
        next[rowId] = !next[rowId];
        root.expandedRows = next;
    }

    function activate() {
        const sel = root.selected;
        if (!sel)
            return;
        if (sel.kind === "group") {
            root.toggleGroup(sel.group.name);
            return;
        }
        root.toggleRow(sel.row.row_id);
    }

    // Same payload rule as the popup stack: `c` is summary + body, `C` the body alone. A group
    // header copies every row under it, which is the whole point of grouping a burst.
    function copySelected(bodyOnly) {
        const sel = root.selected;
        if (!sel)
            return;
        const rows = sel.kind === "group" ? sel.group.rows : [sel.row];
        const parts = [];
        for (const r of rows) {
            const summary = r.summary || "";
            const body = r.body || "";
            parts.push(bodyOnly ? body : (summary && body ? summary + "\n" + body : (summary || body)));
        }
        const text = parts.filter(p => p.length).join("\n\n");
        if (!text)
            return;
        Quickshell.execDetached(["wl-copy", "--", text]);
    }

    function clearSelected() {
        const sel = root.selected;
        if (!sel)
            return;
        const at = root.selectedIndex;
        if (sel.kind === "group")
            root.clearGroup(sel.group);
        else
            root.clearRow(sel.row);
        root.selectAt(Math.min(at, root.items.length - 1));
    }

    function clearSelectedGroup() {
        const sel = root.selected;
        if (sel)
            root.clearGroup(sel.group);
    }

    // Cycle the time filter from the keyboard; the same values the header chips set by click.
    function cycleRange() {
        const order = ["all", "hour", "today", "week"];
        root.filterRange = order[(order.indexOf(root.filterRange) + 1) % order.length];
        root.refresh();
    }

    function clearFilters() {
        root.filterApp = "";
        root.filterCategory = "";
        root.filterUrgency = -1;
        root.filterRange = "all";
        root.filterSnoozed = false;
        root.refresh();
    }

    // No refresh(): the filter is client-side, so `filtered` re-runs on its own and a reload
    // would throw away the in-memory patch markSnoozed just made.
    function toggleSnoozedFilter() {
        root.filterSnoozed = !root.filterSnoozed;
    }

    // ---------------------------------------------------------------------------------------
    // Free-text snooze ("remind me at…"), `r`. The Ctrl+S chips cover the two durations worth a
    // key; this is for the one that is neither — "after work", "Monday morning", any wall clock.
    //
    // Notifications.qml:698 explains why the POPUP path has no clickable version of this: the
    // prompt needs the layershell window's keyboard grab, and on the stack that only turns on
    // for NotifyFocus.active or compose, so a mouse user could type into nothing. None of that
    // applies here — the drawer is a surface the user deliberately opened and it already holds
    // an exclusive grab, which is the whole reason this verb can exist on this surface and not
    // on that one.
    //
    // It reuses the SEARCH field in a mode rather than adding a second TextInput. Two inputs on
    // one grabbing surface means two focus states to keep straight, and the second one is
    // invisible for all but a few seconds of the drawer's life.
    // ---------------------------------------------------------------------------------------

    property var timePromptRow: null
    // What the search box held when the prompt opened, put back when it closes: the field is
    // borrowed, so a search in progress must survive the loan.
    property string searchBeforePrompt: ""

    readonly property bool timePrompting: root.timePromptRow !== null

    // Counted over `rows`, NOT over `filtered`: `filtered` is what the snoozed filter already
    // narrowed, so counting there would make the tab read "snoozed 3" while it is on and
    // "snoozed 0" the moment you turn it off — a control that erases its own reason to exist.
    readonly property int snoozedCount: {
        let n = 0;
        for (const r of root.rows)
            if (r.state === "snoozed")
                n++;
        return n;
    }

    function beginTimePrompt() {
        const sel = root.selected;
        if (!sel || sel.kind === "group")
            return false;
        root.searchBeforePrompt = root.search;
        root.timePromptRow = sel.row ? sel.row : sel;
        return true;
    }

    function cancelTimePrompt() {
        root.timePromptRow = null;
    }

    // Rejects what it cannot parse rather than guessing — snoozing for the wrong interval is
    // worse than saying the input was not understood. Same rule, same wording as the popup
    // path's submitPrompt, because it is the same mistake being reported.
    function submitTimePrompt(text) {
        const row = root.timePromptRow;
        root.timePromptRow = null;
        if (!row)
            return;
        const ms = Notifications.parseDelay(text);
        if (ms === null) {
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "quickshell",
                    "Snooze", "could not parse \"" + text + "\" — try 20m, 2h or 17:30"]);
            return;
        }
        const wake = Notifications.snoozeRow(row, ms);
        if (wake > 0)
            root.markSnoozed(row.row_id, wake);
    }

    // Clicking a group header's app name filters to it — the fastest filter is the one you can
    // reach without knowing the app's exact name.
    function filterToApp(name) {
        root.filterApp = root.filterApp === name ? "" : name;
        root.refresh();
    }
}
