pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Clock-drawer state: world clocks, the calendar month, and whether the drawer is open.
//
// Named `Clocks` and not `ClockDrawer` because components/ClockDrawer.qml is the VIEW — a
// singleton of the same name would shadow the component in every file that imports both
// directories. Same split as NotifyDrawer/NotificationDrawer: everything that is not pixels
// lives here, the window owns no state.
//
// NO Intl. quickshell 0.3.0's JS engine has no timezone database, so `new Date()` can only
// ever be local time; zone times come from ONE `TZ=… date` shell call, refreshed each minute
// while the drawer is open. This is the mechanism the bar clock's hover popout used before the
// list moved here — do not swap it for an Intl formatter that silently returns local time
// everywhere.
Singleton {
    id: root

    property bool shown: false

    // ---------------------------------------------------------------------------------------
    // Ticking clock. One second while the drawer is open, stopped while it is not: nothing
    // reads `now` when there is no window, and a timer that keeps waking the process to
    // recompute a calendar nobody is looking at is pure battery.
    // ---------------------------------------------------------------------------------------

    property var now: new Date()

    Timer {
        interval: 1000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // ---------------------------------------------------------------------------------------
    // World clocks. [label, IANA timezone] — edit `zones` to reconfigure.
    // ---------------------------------------------------------------------------------------

    property var zones: [["UTC", "Etc/UTC"], ["Indianapolis", "America/Indiana/Indianapolis"], ["Florida", "America/New_York"], ["California", "America/Los_Angeles"], ["Minneapolis", "America/Chicago"]]
    // [{ label, time, day }]
    property var zoneTimes: []

    // Labels and IANA names come from this file, never from anything a notification or a
    // network reply can set, so the quoting here is the whole of the injection surface.
    function zoneScript() {
        const parts = root.zones.map(z => '"' + z[0] + '|' + z[1] + '"').join(" ");
        return 'for z in ' + parts + '; do l=${z%%|*}; t=${z##*|}; printf "%s\\t%s\\t%s\\n" "$l" "$(TZ=$t date +%H:%M)" "$(TZ=$t date +%a)"; done';
    }

    Process {
        id: tzProc
        command: ["sh", "-c", root.zoneScript()]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of this.text.split("\n")) {
                    if (!line.trim())
                        continue;
                    const p = line.split("\t");
                    out.push({
                        label: p[0],
                        time: p[1] || "",
                        day: p[2] || ""
                    });
                }
                root.zoneTimes = out;
            }
        }
    }

    function refreshZones() {
        tzProc.running = false;
        tzProc.running = true;
    }

    Timer {
        interval: 60000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshZones()
    }

    // ---------------------------------------------------------------------------------------
    // Calendar. Month state, not day state: v1 marks today and browses months, with no event
    // integration.
    // ---------------------------------------------------------------------------------------

    property int calYear: (new Date()).getFullYear()
    property int calMonth: (new Date()).getMonth()   // 0-11

    function buildCells(y, m, today) {
        const first = new Date(y, m, 1).getDay();       // 0 = Sunday
        const dim = new Date(y, m + 1, 0).getDate();    // days in this month
        const dimPrev = new Date(y, m, 0).getDate();
        const tY = today.getFullYear(), tM = today.getMonth(), tD = today.getDate();
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const n = i - first + 1;
            if (n < 1)
                cells.push({
                    day: dimPrev + n,
                    other: true,
                    today: false
                });
            else if (n > dim)
                cells.push({
                    day: n - dim,
                    other: true,
                    today: false
                });
            else
                cells.push({
                    day: n,
                    other: false,
                    today: (y === tY && m === tM && n === tD)
                });
        }
        return cells;
    }

    readonly property var calCells: root.buildCells(root.calYear, root.calMonth, root.now)

    function shiftMonth(d) {
        let m = root.calMonth + d, y = root.calYear;
        if (m < 0) {
            m = 11;
            y--;
        } else if (m > 11) {
            m = 0;
            y++;
        }
        root.calMonth = m;
        root.calYear = y;
    }

    function resetMonth() {
        const n = new Date();
        root.calYear = n.getFullYear();
        root.calMonth = n.getMonth();
    }

    // ---------------------------------------------------------------------------------------
    // Open / close
    // ---------------------------------------------------------------------------------------

    function open() {
        if (root.shown)
            return;
        root.shown = true;
        root.now = new Date();
        root.resetMonth();
        root.refreshZones();
        // Opening is the moment the number on screen matters. A reading older than the refresh
        // interval is refetched; a fresh one is not, so opening the drawer twice in a minute
        // does not make two requests.
        if (!Weather.current || Date.now() - Weather.updatedAt > Weather.refreshMinutes * 60000)
            Weather.refresh();
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
}
