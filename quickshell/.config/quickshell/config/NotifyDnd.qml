pragma Singleton

import QtQuick
import Quickshell

// Do Not Disturb (story: notif-dnd-core). Owns the real DND state that
// `NotifyRules.state().dnd` used to lie about (a hardcoded `false`). Two independent inputs
// OR together into one `active`:
//   - manualOn: the keybind / `qs ipc call notifications dnd…` toggle
//   - quietHours: a scheduled window read from config, off by default
//
// SUPPRESSION IS A DEFAULT, NOT A WALL. When active, this is the only place that forces a
// notification's duration negative (drawer-only — recorded, counted unread, never popped).
// It runs BEFORE the Lua rules engine sees the notification, so a rule can restore visibility
// (durationMs > 0) for whatever it decides matters — "DND that cannot be escaped is DND you
// stop trusting" (the story's thesis). Nothing here ever drops a notification: the drawer-only
// path is the exact mechanism notif-timing already built for muting an app, reused rather than
// duplicated.
Singleton {
    id: root

    readonly property var config: NotifyConfig.dnd

    // ---------------------------------------------------------------------------------------
    // Manual toggle
    // ---------------------------------------------------------------------------------------

    property bool manualOn: false

    function on(): void {
        root.manualOn = true;
    }
    function off(): void {
        root.manualOn = false;
    }
    function toggle(): void {
        root.manualOn = !root.manualOn;
    }

    // ---------------------------------------------------------------------------------------
    // Scheduled quiet hours. "HH:MM", 24h clock; start > end wraps past midnight. Recomputed
    // on a plain timer rather than reusing NotifyRules.state().hour: a schedule needs minute
    // resolution (23:00-07:00 crossing midnight, or a window under an hour), and that state()
    // field is an integer hour for rule predicates, a different question at a coarser grain.
    // ---------------------------------------------------------------------------------------

    function clockMinutes(hhmm) {
        const m = String(hhmm).match(/^([0-9]{1,2}):([0-9]{2})$/);
        if (!m)
            return -1;
        return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
    }

    function inWindow(nowMin, startMin, endMin) {
        if (startMin < 0 || endMin < 0 || startMin === endMin)
            return false; // unparseable or zero-length: never active, never a permanent lock-in
        if (startMin < endMin)
            return nowMin >= startMin && nowMin < endMin;
        return nowMin >= startMin || nowMin < endMin; // wraps midnight
    }

    readonly property bool quietHoursEnabled: root.config.quietHours.enabled
    property bool scheduled: false

    function recomputeSchedule() {
        if (!root.quietHoursEnabled) {
            root.scheduled = false;
            return;
        }
        const now = new Date();
        const nowMin = now.getHours() * 60 + now.getMinutes();
        root.scheduled = root.inWindow(nowMin, root.clockMinutes(root.config.quietHours.start), root.clockMinutes(root.config.quietHours.end));
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.recomputeSchedule()
    }

    onConfigChanged: root.recomputeSchedule()

    // ---------------------------------------------------------------------------------------
    // Combined state, read by the bar indicator and by NotifyRules.state().dnd.
    // ---------------------------------------------------------------------------------------

    readonly property bool active: root.manualOn || root.scheduled

    function statusText() {
        if (!root.active)
            return "off";
        if (root.manualOn && root.scheduled)
            return "on (manual + quiet hours)";
        return root.manualOn ? "on (manual)" : "on (quiet hours)";
    }

    // ---------------------------------------------------------------------------------------
    // Suppression. Called from Notifications.refresh() before the rules engine runs, so a Lua
    // rule's answer is the last write and wins (same "accumulate, last write wins" contract
    // the engine already has). `entry.dndBaseline` records that THIS notification was subject
    // to the DND default, so the exit digest can count only what actually stayed suppressed —
    // not a notification a rule exception let back through.
    // ---------------------------------------------------------------------------------------

    function applySuppression(entry) {
        entry.dndBaseline = root.active;
        if (root.active)
            entry.durationMs = -1;
    }

    // ---------------------------------------------------------------------------------------
    // Exit digest. One card summarising what was held, not a replay of every suppressed
    // notification — that flood is exactly what DND exists to prevent. Counted in
    // noteSuppressed(), called once per entry from Notifications.finishRefresh() after the
    // rules engine has had its say, guarded by entry.dndCounted so a later refresh() of the
    // same notification (an in-place update, a hint change) can never double-count it.
    // ---------------------------------------------------------------------------------------

    property int suppressedCount: 0

    function noteSuppressed(): void {
        root.suppressedCount++;
    }

    onActiveChanged: {
        if (root.active) {
            root.suppressedCount = 0; // a fresh DND session starts its own tally
            return;
        }
        if (root.suppressedCount > 0) {
            const n = root.suppressedCount;
            Quickshell.execDetached(["notify-send", "-a", "quickshell", "-u", "normal", "Do Not Disturb ended", n + (n === 1 ? " notification was" : " notifications were") + " held while DND was on — see the drawer."]);
            root.suppressedCount = 0;
        }
    }
}
