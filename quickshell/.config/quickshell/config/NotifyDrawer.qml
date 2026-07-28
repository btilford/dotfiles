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

    // What Enter does on the selection: a group folds, a row is a no-op until the actions
    // story gives stored notifications something to invoke.
    function activate() {
        const sel = root.selected;
        if (!sel)
            return;
        if (sel.kind === "group") {
            root.toggleGroup(sel.group.name);
            return;
        }
        console.info("notifications: acting on a stored notification needs the actions story (notif-actions)");
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
        root.refresh();
    }

    // Clicking a group header's app name filters to it — the fastest filter is the one you can
    // reach without knowing the app's exact name.
    function filterToApp(name) {
        root.filterApp = root.filterApp === name ? "" : name;
        root.refresh();
    }
}
