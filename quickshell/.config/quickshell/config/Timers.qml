pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Countdown, pomodoro, alarm and stopwatch for the shell (story: notif-timers).
//
// THIS SINGLETON OWNS THE STATE MACHINE. Every phase transition, every duration and the whole
// pomodoro cycle live here; a notification card is a pure VIEW that renders what this publishes,
// exactly the split the notifications epic already enforces (`Notifications` owns everything that
// is not pixels). A pomodoro smeared across a notification card is the thing this prevents.
//
// It is composition over the machinery that already exists, not a second copy of it:
//
//   scheduling   NotifyStore's ONE armed timer — a `timers` row with wake_at, fired at startup
//                if it is already due. That is what survives a qs restart AND a reboot with no
//                second scheduler anywhere (AD-012 §4).
//   parsing      Notifications.parseDelay() — "20m", "2h", "17:30". No second vocabulary, so
//                "remind me at" and "start a timer for" can never drift apart.
//   display      a real notification, raised through notify-send like every other one this shell
//                shows, so a timer is in the history, the drawer and the bell count for free.
//   actions      pause/resume, +5 min, reset, cancel are actions on the card, so they answer the
//                same Ctrl+<letter> hints and the same keyboard as every other verb.
//
// WHAT IS NOT WRITTEN: ticks. A running countdown is in-memory state on this object; the store
// sees arm, pause, resume and finish, and one summary row per finished phase. See the `timers`
// table comment in NotifyStore.qml for the "how many pomodoros today" query that buys.
//
// THE STOPWATCH IS THE ODD ONE OUT and is deliberately not a card. It counts up, so it has no
// wake_at and gets nothing from the scheduling above, and a card only re-renders on replaces_id —
// repainting a notification once a second to show a clock is an abuse of the stack. It lives as a
// bar pill (components/bar/Stopwatch.qml) and touches the notification surface only at terminal
// events: started, lap, stopped.
Singleton {
    id: root

    readonly property var cfg: NotifyConfig.timers

    // Live timers, newest first. Plain JS objects — data, not views:
    //   handle      the small, public number an IPC call and a card action address; stable for
    //               the whole RUN, so a pomodoro keeps it across every phase
    //   runId       the same identity as it is written to the store (epoch-derived, too big to
    //               hand out over IPC — see the identity block below)
    //   rowId       the timers row for the CURRENT phase; a new one per phase, so each phase
    //               gets its own summary row and the store's fired-id guard never blocks a
    //               later phase of the same run
    //   endsAt      epoch ms, null while paused; remainingMs is what is left in that case
    property var timers: []

    // Ticks once a second while anything is live. Views bind to it to re-evaluate their
    // readouts; nothing about expiry depends on it — the store's armed timer is the clock, so a
    // dropped frame can never change when a timer actually fires.
    property real now: Date.now()
    // bumped whenever the timer LIST changes shape, so a binding that only reads `now` still
    // re-runs when a timer is added, paused or cancelled
    property int revision: 0

    readonly property bool anyRunning: {
        for (const t of root.timers)
            if (!t.paused)
                return true;
        return false;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.anyRunning || root.stopwatch.running
        onTriggered: root.now = Date.now()
    }

    // ---------------------------------------------------------------------------------------
    // Identity, and why there are TWO of them.
    //
    // `runId` / `rowId` are chosen here rather than by SQLite, because writes batch through a
    // subprocess and an AUTOINCREMENT rowid could not be handed back in time to be useful. They
    // are epoch-derived, so they are unique across processes as well as within one — and they
    // are ~1e15, which does not fit an int.
    //
    // `handle` is the SMALL number everything public uses: the IPC surface, the card's
    // `x-timer-id` hint, the summary line. An IpcHandler function is typed, and an `int` there
    // is 32-bit — handing out a run id truncated it to a negative number that addressed
    // nothing, so `timers pause <id>` could never work with an id `timers start` had printed.
    // Handles are per-session labels (they are reassigned on restore), which is exactly what a
    // number a human retypes should be.
    // ---------------------------------------------------------------------------------------

    property int idCounter: 0
    property int handleCounter: 0

    // A hint is CLIENT DATA. Any app on the session bus can send
    // `-h string:x-timer-id:1`, and without this it would be handed a live timer's control
    // surface — pause, +5, reset and cancel on someone else's countdown — plus the timer anchor
    // to pin itself to. So every card this singleton raises carries a token minted once per
    // session, and a hint is only believed when the token matches. It is not a defence against
    // anything that can read this process's memory; it is what stops a hint from being
    // guessable, which is the actual exposure.
    property string token: ""

    function nextId() {
        root.idCounter = (root.idCounter + 1) % 1000;
        return Date.now() * 1000 + root.idCounter;
    }

    function nextHandle() {
        root.handleCounter++;
        return root.handleCounter;
    }

    Component.onCompleted: {
        root.token = Math.random().toString(36).substring(2) + Math.random().toString(36).substring(2);
    }

    // ---------------------------------------------------------------------------------------
    // Formatting
    // ---------------------------------------------------------------------------------------

    function pad2(n) {
        return n < 10 ? "0" + n : String(n);
    }

    // "04:59" under an hour, "1:04:59" over it. Rounded UP so a timer never reads 00:00 while it
    // is still running.
    function fmt(ms) {
        const total = Math.max(0, Math.ceil(ms / 1000));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        return h > 0 ? h + ":" + root.pad2(m) + ":" + root.pad2(s) : root.pad2(m) + ":" + root.pad2(s);
    }

    function phaseLabel(t) {
        if (t.kind !== "pomodoro")
            return "";
        if (t.phase === "work")
            return "Work " + t.cycle + "/" + t.cycles;
        return t.phase === "long" ? "Long break" : "Short break";
    }

    // ---------------------------------------------------------------------------------------
    // Lookup
    // ---------------------------------------------------------------------------------------

    function byHandle(handle) {
        for (const t of root.timers)
            if (t.handle === handle)
                return t;
        return null;
    }

    function byRowId(rowId) {
        for (const t of root.timers)
            if (t.rowId === rowId)
                return t;
        return null;
    }

    // handle 0 = "the newest live timer", so a keybind or a script does not have to know one
    function resolve(handle) {
        if (handle && handle > 0)
            return root.byHandle(handle);
        return root.timers.length ? root.timers[0] : null;
    }

    function remainingOf(t) {
        if (!t)
            return 0;
        return t.paused ? t.remainingMs : Math.max(0, t.endsAt - root.now);
    }

    function progressOf(t) {
        if (!t || t.plannedMs <= 0)
            return 0;
        return Math.max(0, Math.min(1, 1 - root.remainingOf(t) / t.plannedMs));
    }

    function publish() {
        root.timers = root.timers.slice();
        root.revision++;
    }

    // ---------------------------------------------------------------------------------------
    // The notification surface. Timers do not draw their own window: they raise a real
    // notification through notify-send, the same round trip snooze and a failing action use, so
    // a timer lands in the popup stack, the store, the drawer and the bell by one path.
    //
    // `-p` prints the notification id, which is how a running card can later be updated in place
    // or taken down. execDetached cannot read stdout, hence a Process.
    // ---------------------------------------------------------------------------------------

    function raise(t, summary, body, urgency, replaceNid) {
        // Two hints, and the split matters: `x-timer-token` says "this shell raised this card"
        // and is on every timer notification; `x-timer-id` says "this card CONTROLS that live
        // timer" and is only ever on a running timer's own card.
        const argv = ["notify-send", "-p", "-t", "0", "-u", urgency, "-a", "timer", "-h", "string:category:x-timer", "-h", "string:x-timer-token:" + root.token, "-h", "string:x-timer-id:" + t.handle];
        if (replaceNid > 0)
            argv.push("-r", String(replaceNid));
        argv.push(summary, body);
        const proc = raiseComponent.createObject(root, {
            command: argv,
            timerHandle: t.handle
        });
        if (!proc) {
            console.warn("timers: could not raise the card for", summary);
            return;
        }
        proc.running = true;
    }

    Component {
        id: raiseComponent

        Process {
            id: proc
            property int timerHandle: 0
            stderr: StdioCollector {}
            stdout: StdioCollector {
                onStreamFinished: {
                    const nid = parseInt(this.text.trim(), 10);
                    if (isNaN(nid) || nid <= 0)
                        return;
                    const t = root.byHandle(proc.timerHandle);
                    // The timer may have finished, or been cancelled, while notify-send was
                    // still being answered — a 2-second countdown does exactly that. dropCard()
                    // could not take a card down that had no id yet, so close it here instead;
                    // otherwise a running card outlives the timer it is showing.
                    if (!t || t.dropped) {
                        const entry = Notifications.entryForId(nid);
                        if (entry)
                            Notifications.dismiss(entry);
                        return;
                    }
                    t.nid = nid;
                    root.publish();
                }
            }
            onExited: exitCode => {
                if (exitCode !== 0)
                    console.warn("timers: notify-send failed (exit " + exitCode + ") —", proc.stderr.text.trim());
                proc.destroy();
            }
        }
    }

    // Take a timer's card off the screen. The history row stays: the card is the display, the
    // `timers` row is the record.
    function dropCard(t) {
        if (!t)
            return;
        // Latches, and is never cleared: a timer object is not reused once its card has been
        // taken down (a pomodoro's next phase is a NEW object). This is what a notify-send still
        // in flight checks when its id finally arrives.
        t.dropped = true;
        if (!t.nid)
            return;
        const entry = Notifications.entryForId(t.nid);
        if (entry)
            Notifications.dismiss(entry);
        t.nid = 0;
    }

    function runningBody(t) {
        const parts = [];
        const phase = root.phaseLabel(t);
        if (phase.length)
            parts.push(phase);
        parts.push(root.fmt(t.plannedMs) + (t.kind === "alarm" ? " until it goes off" : " on the clock"));
        return parts.join("  ·  ");
    }

    function cardSummary(t) {
        if (t.label.length)
            return t.label;
        if (t.kind === "pomodoro")
            return "Pomodoro";
        return t.kind === "alarm" ? "Alarm" : "Timer";
    }

    // ---------------------------------------------------------------------------------------
    // Arming. One place, so every kind reaches the store the same way.
    // ---------------------------------------------------------------------------------------

    // A timer that cannot be persisted cannot fire, because the store IS the schedule. Say so at
    // ARM time rather than silently at fire time: a countdown that never goes off is the one
    // failure this feature must not have.
    function storeUsable() {
        if (NotifyConfig.store.enabled && NotifyStore.healthy)
            return true;
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "timer", "Timer not started", "The notification store is off, and the store is what arms a timer — nothing would fire."]);
        return false;
    }

    function armPhase(t, ms) {
        t.rowId = root.nextId();
        t.plannedMs = Math.max(1000, Math.round(ms));
        t.remainingMs = t.plannedMs;
        t.startedAt = Date.now();
        t.endsAt = t.startedAt + t.plannedMs;
        t.paused = false;
        NotifyStore.armTimer({
            id: t.rowId,
            runId: t.runId,
            kind: t.kind,
            label: t.label,
            state: "armed",
            phase: t.phase,
            cycle: t.cycle,
            cycles: t.cycles,
            workMs: t.workMs,
            shortMs: t.shortMs,
            longMs: t.longMs,
            plannedMs: t.plannedMs,
            remainingMs: t.plannedMs,
            wakeAt: t.endsAt,
            startedAt: t.startedAt
        });
    }

    function add(t) {
        const list = root.timers.slice();
        list.unshift(t);
        root.timers = list;
        root.revision++;
    }

    function remove(t) {
        const list = root.timers.slice();
        const i = list.indexOf(t);
        if (i >= 0)
            list.splice(i, 1);
        root.timers = list;
        root.revision++;
    }

    // ---------------------------------------------------------------------------------------
    // Public API — countdown, alarm, pomodoro
    // ---------------------------------------------------------------------------------------

    // "20m", "2h", "90s", "17:30" — Notifications.parseDelay, not a second parser. It REJECTS
    // what it cannot read rather than guessing, and so does this.
    function parse(spec) {
        return Notifications.parseDelay(spec);
    }

    function start(spec, label) {
        const ms = root.parse(spec);
        if (ms === null) {
            console.warn("timers: cannot read the duration", spec);
            return 0;
        }
        return root.startMs(ms, label || "", "countdown");
    }

    function startMs(ms, label, kind) {
        if (!root.storeUsable())
            return 0;
        const t = {
            handle: root.nextHandle(),
            runId: root.nextId(),
            rowId: 0,
            kind: kind,
            label: String(label || ""),
            phase: "",
            cycle: 0,
            cycles: 0,
            workMs: 0,
            shortMs: 0,
            longMs: 0,
            plannedMs: 0,
            remainingMs: 0,
            startedAt: 0,
            endsAt: 0,
            paused: false,
            nid: 0,
            dropped: false
        };
        root.armPhase(t, ms);
        root.add(t);
        root.raise(t, root.cardSummary(t), root.runningBody(t), "normal", 0);
        return t.handle;
    }

    // An alarm is a countdown to a wall-clock time, which parseDelay already answers ("17:30" is
    // "this many ms from now, tomorrow if it is already past"). It survives a restart and a
    // reboot for exactly the reason every other armed timer does — the row carries wake_at.
    function alarm(spec, label) {
        const ms = root.parse(spec);
        if (ms === null) {
            console.warn("timers: cannot read the alarm time", spec);
            return 0;
        }
        return root.startMs(ms, label || "", "alarm");
    }

    // "25m/5m/15m x4", any part optional: "25m", "25m/5m", "50m/10m x2". Each part goes through
    // parseDelay, so this adds a shape and not a vocabulary.
    function parsePomodoro(spec) {
        const out = {
            workMs: root.cfg.workMs,
            shortMs: root.cfg.shortMs,
            longMs: root.cfg.longMs,
            cycles: root.cfg.cycles
        };
        const text = String(spec || "").trim();
        if (!text.length)
            return out;
        const parts = text.toLowerCase().split("x");
        if (parts.length > 1) {
            const n = parseInt(parts[1].trim(), 10);
            if (!isNaN(n) && n > 0)
                out.cycles = n;
        }
        const lens = parts[0].split("/").map(s => s.trim()).filter(s => s.length);
        const keys = ["workMs", "shortMs", "longMs"];
        for (let i = 0; i < lens.length && i < keys.length; i++) {
            const ms = root.parse(lens[i]);
            if (ms === null) {
                console.warn("timers: cannot read the pomodoro length", lens[i]);
                return null;
            }
            out[keys[i]] = ms;
        }
        return out;
    }

    function pomodoro(spec, label) {
        if (!root.storeUsable())
            return 0;
        const p = root.parsePomodoro(spec);
        if (!p)
            return 0;
        const t = {
            handle: root.nextHandle(),
            runId: root.nextId(),
            rowId: 0,
            kind: "pomodoro",
            label: String(label || ""),
            phase: "work",
            cycle: 1,
            cycles: p.cycles,
            workMs: p.workMs,
            shortMs: p.shortMs,
            longMs: p.longMs,
            plannedMs: 0,
            remainingMs: 0,
            startedAt: 0,
            endsAt: 0,
            paused: false,
            nid: 0,
            dropped: false
        };
        root.armPhase(t, p.workMs);
        root.add(t);
        root.raise(t, root.cardSummary(t), root.runningBody(t), "normal", 0);
        return t.handle;
    }

    // ---------------------------------------------------------------------------------------
    // Card actions. pause/resume, +N min, reset, cancel — all of them go through the store,
    // because the store is what will still be there after a restart.
    // ---------------------------------------------------------------------------------------

    function pause(id) {
        const t = root.resolve(id);
        if (!t || t.paused)
            return false;
        t.remainingMs = Math.max(0, t.endsAt - Date.now());
        t.paused = true;
        t.endsAt = 0;
        // wake_at NULL is what takes it out of the armed set; remaining_ms is what a restart
        // needs to bring it back where it was
        NotifyStore.updateTimer(t.rowId, {
            state: "paused",
            wake_at: null,
            remaining_ms: t.remainingMs
        });
        root.publish();
        return true;
    }

    function resume(id) {
        const t = root.resolve(id);
        if (!t || !t.paused)
            return false;
        t.paused = false;
        t.endsAt = Date.now() + Math.max(1000, t.remainingMs);
        NotifyStore.updateTimer(t.rowId, {
            state: "armed",
            wake_at: t.endsAt,
            remaining_ms: t.remainingMs
        });
        root.publish();
        return true;
    }

    function toggle(id) {
        const t = root.resolve(id);
        if (!t)
            return false;
        return t.paused ? root.resume(t.handle) : root.pause(t.handle);
    }

    // Back to the top of the CURRENT phase. A pomodoro resets the phase, not the run — losing
    // three finished work phases to a mis-hit key would be worse than any confusion about it.
    function reset(id) {
        const t = root.resolve(id);
        if (!t)
            return false;
        t.startedAt = Date.now();
        t.remainingMs = t.plannedMs;
        t.paused = false;
        t.endsAt = t.startedAt + t.plannedMs;
        NotifyStore.updateTimer(t.rowId, {
            state: "armed",
            wake_at: t.endsAt,
            remaining_ms: t.plannedMs,
            started_at: t.startedAt
        });
        root.publish();
        return true;
    }

    // +5 min (NotifyConfig.timers.addMs). The PLANNED length grows with it, so the progress bar
    // does not jump backwards past its own start.
    function extend(id, ms) {
        const t = root.resolve(id);
        if (!t)
            return false;
        const delta = Math.round(ms > 0 ? ms : root.cfg.addMs);
        t.plannedMs += delta;
        if (t.paused) {
            t.remainingMs += delta;
            NotifyStore.updateTimer(t.rowId, {
                planned_ms: t.plannedMs,
                remaining_ms: t.remainingMs
            });
        } else {
            t.endsAt += delta;
            NotifyStore.updateTimer(t.rowId, {
                planned_ms: t.plannedMs,
                wake_at: t.endsAt
            });
        }
        root.publish();
        return true;
    }

    function cancel(id) {
        const t = root.resolve(id);
        if (!t)
            return false;
        NotifyStore.finishTimer(t.rowId, "cancelled", Date.now() - t.startedAt);
        root.dropCard(t);
        root.remove(t);
        return true;
    }

    function cancelAll() {
        for (const t of root.timers.slice())
            root.cancel(t.handle);
    }

    // ---------------------------------------------------------------------------------------
    // Firing. The store's ONE armed timer is what gets here — including at startup, for a row
    // whose wake_at passed while the machine was off.
    // ---------------------------------------------------------------------------------------

    Connections {
        target: NotifyStore

        function onTimerElapsed(id, runId, kind, label, phase, cycle, cycles, plannedMs, startedAt, workMs, shortMs, longMs) {
            // The completion row (decision 4): kind, label, planned, actual, started, ended.
            NotifyStore.finishTimer(id, "done", Date.now() - startedAt);

            let t = root.byRowId(id);
            if (!t) {
                // Fired before the restore query answered, or fired for a run this process never
                // knew about (a reboot). Everything needed is on the signal, so rebuild rather
                // than drop it — a missed alarm is the failure that matters here.
                t = {
                    handle: root.nextHandle(),
                    runId: runId,
                    rowId: id,
                    kind: kind,
                    label: label,
                    phase: phase,
                    cycle: cycle,
                    cycles: cycles,
                    workMs: workMs,
                    shortMs: shortMs,
                    longMs: longMs,
                    plannedMs: plannedMs,
                    remainingMs: 0,
                    startedAt: startedAt,
                    endsAt: 0,
                    paused: false,
                    nid: 0,
                    dropped: false
                };
            }
            root.fire(t);
        }

        function onTimersRestored(json) {
            root.restore(json);
        }
    }

    // The chime. A finished timer is the one notification you may not be looking at the screen
    // for, so it is the one that earns a sound — and only this path plays one. raise() does not:
    // a card going up when you START a timer is a thing you already know about.
    //
    // A sound-theme NAME, resolved by canberra against the user's theme, never a file path. A
    // path would be right on one machine and wrong on the next, and it would ignore a themed
    // desktop outright. canberra-gtk-play is the only player that does that lookup; pw-play and
    // paplay take a path and nothing else, so falling back to them would mean hard-coding the
    // freedesktop path here and quietly defeating the point. A machine without canberra gets no
    // chime and one warning — the card still fires, which is the part that must never depend on
    // an optional binary.
    //
    // execDetached, so a slow or wedged audio stack cannot hold the notification behind it.
    function playAlarm() {
        const name = NotifyConfig.timers.alarmSound;
        if (!name || !name.length)
            return;
        Quickshell.execDetached(["canberra-gtk-play", "-i", name]);
    }

    function fire(t) {
        root.playAlarm();
        root.dropCard(t);
        const done = root.byRowId(t.rowId);
        if (done)
            root.remove(done);

        if (t.kind === "pomodoro") {
            root.announcePomodoro(t);
            root.advancePomodoro(t);
            return;
        }
        // Sticky and critical: you asked to be told, so it waits to be dealt with rather than
        // timing out into the bell while you are in another window.
        const label = t.label.length ? t.label : (t.kind === "alarm" ? "Alarm" : "Timer");
        // TOKEN ONLY, never the handle. The token is what puts this card in the timer stack;
        // the handle would make it a live control surface, which a finished timer is not.
        Quickshell.execDetached(["notify-send", "-t", "0", "-u", "critical", "-a", "timer", "-h", "string:category:x-timer-done", "-h", "string:x-timer-token:" + root.token, label + " — time's up", root.fmt(t.plannedMs) + " finished at " + Qt.formatDateTime(new Date(), "HH:mm")]);
    }

    // TOKEN ONLY, and this is the case that proves the rule. A pomodoro run keeps its handle
    // across every phase, and advancePomodoro() has already armed the next phase and added it to
    // the live list by the time notify-send delivers — so a "Work 1/4 done" card carrying the
    // handle resolved to the BREAK THAT JUST STARTED: it rendered the break's countdown and its
    // chips acted on the break, so Ctrl+C on a card reading "Work 1/4 done" cancelled the short
    // break. An announcement is a statement about something that has ended; it is never a
    // control surface.
    function announcePomodoro(t) {
        const next = t.phase === "work" ? (t.cycle >= t.cycles ? "a long break" : "a short break") : "work";
        const what = t.phase === "work" ? "Work " + t.cycle + "/" + t.cycles + " done" : (t.phase === "long" ? "Long break over" : "Short break over");
        Quickshell.execDetached(["notify-send", "-t", "0", "-u", "critical", "-a", "timer", "-h", "string:category:x-timer-done", "-h", "string:x-timer-token:" + root.token, (t.label.length ? t.label + " — " : "") + what, "Next: " + next]);
    }

    // work -> short -> work -> … -> long -> work. The cycle counter is what decides which break
    // comes next, and it is reset by the long break rather than by the run ending: a pomodoro
    // run has no end, it has a cancel.
    function advancePomodoro(t) {
        const wasWork = t.phase === "work";
        const next = Object.assign({}, t, {
            nid: 0,
            dropped: false
        });
        if (wasWork) {
            if (t.cycle >= t.cycles) {
                next.phase = "long";
                root.armPhase(next, t.longMs);
            } else {
                next.phase = "short";
                root.armPhase(next, t.shortMs);
            }
        } else {
            next.phase = "work";
            next.cycle = t.phase === "long" ? 1 : t.cycle + 1;
            root.armPhase(next, t.workMs);
        }
        root.add(next);
        root.raise(next, root.cardSummary(next), root.runningBody(next), "normal", 0);
    }

    // ---------------------------------------------------------------------------------------
    // Restore (startup reconciliation). The rows are the only record a previous process left,
    // and their cards died with it — so the cards are raised again here.
    // ---------------------------------------------------------------------------------------

    function restore(json) {
        let rows = [];
        try {
            rows = JSON.parse(json || "[]");
        } catch (e) {
            console.warn("timers: could not read the restored rows —", e);
            return;
        }
        for (const r of rows) {
            if (NotifyStore.firedTimers[r.id])
                continue; // already fired by this startup's due sweep
            if (root.byRowId(r.id))
                continue;
            const paused = r.state === "paused";
            const t = {
                handle: root.nextHandle(),
                runId: r.run_id || r.id,
                rowId: r.id,
                kind: r.kind || "countdown",
                label: r.label || "",
                phase: r.phase || "",
                cycle: r.cycle || 0,
                cycles: r.cycles || 0,
                workMs: r.work_ms || 0,
                shortMs: r.short_ms || 0,
                longMs: r.long_ms || 0,
                plannedMs: r.planned_ms || 0,
                remainingMs: paused ? (r.remaining_ms || 0) : 0,
                startedAt: r.started_at || Date.now(),
                endsAt: paused ? 0 : (r.wake_at || 0),
                paused: paused,
                nid: 0,
                dropped: false
            };
            root.add(t);
            root.raise(t, root.cardSummary(t), root.runningBody(t), "normal", 0);
        }
    }

    // ---------------------------------------------------------------------------------------
    // Stopwatch (decision 2). Counts up, so nothing here is armed and nothing is scheduled. The
    // bar pill is its display; the notification surface sees it only at terminal events.
    // ---------------------------------------------------------------------------------------

    property var stopwatch: ({
            running: false,
            id: 0,
            label: "",
            startedAt: 0,
            accumulatedMs: 0,
            laps: []
        })

    readonly property real stopwatchElapsed: root.stopwatch.accumulatedMs + (root.stopwatch.running ? Math.max(0, root.now - root.stopwatch.startedAt) : 0)

    function publishStopwatch() {
        root.stopwatch = Object.assign({}, root.stopwatch);
    }

    function stopwatchStart(label) {
        if (root.stopwatch.running)
            return false;
        const fresh = root.stopwatch.id === 0;
        root.stopwatch.id = fresh ? root.nextId() : root.stopwatch.id;
        if (fresh) {
            root.stopwatch.label = String(label || "");
            root.stopwatch.accumulatedMs = 0;
            root.stopwatch.laps = [];
        }
        root.stopwatch.startedAt = Date.now();
        root.stopwatch.running = true;
        root.now = Date.now();
        root.publishStopwatch();
        if (fresh)
            Quickshell.execDetached(["notify-send", "-a", "timer", "-h", "string:category:x-timer", root.stopwatch.label.length ? root.stopwatch.label : "Stopwatch", "started"]);
        return true;
    }

    function stopwatchPause() {
        if (!root.stopwatch.running)
            return false;
        root.stopwatch.accumulatedMs += Math.max(0, Date.now() - root.stopwatch.startedAt);
        root.stopwatch.running = false;
        root.publishStopwatch();
        return true;
    }

    function stopwatchToggle(label) {
        return root.stopwatch.running ? root.stopwatchPause() : root.stopwatchStart(label);
    }

    // A lap IS a terminal event in the sense that matters: it is a moment you asked to keep, so
    // it gets a notification. The running readout stays in the pill.
    function stopwatchLap() {
        if (!root.stopwatch.id)
            return false;
        const at = root.stopwatchElapsed;
        const prev = root.stopwatch.laps.length ? root.stopwatch.laps[root.stopwatch.laps.length - 1] : 0;
        root.stopwatch.laps = root.stopwatch.laps.concat([at]);
        root.publishStopwatch();
        Quickshell.execDetached(["notify-send", "-a", "timer", "-h", "string:category:x-timer", (root.stopwatch.label.length ? root.stopwatch.label + " — " : "") + "Lap " + root.stopwatch.laps.length, root.fmt(at) + "  (+" + root.fmt(at - prev) + ")"]);
        return true;
    }

    // Stop writes the ONE summary row this run produces: kind, label, planned (0 — a stopwatch
    // has no plan), actual, started, ended.
    function stopwatchStop() {
        if (!root.stopwatch.id)
            return false;
        const elapsed = root.stopwatchElapsed;
        const id = root.stopwatch.id;
        const label = root.stopwatch.label;
        const laps = root.stopwatch.laps.length;
        NotifyStore.recordCompleted({
            id: id,
            runId: id,
            kind: "stopwatch",
            label: label,
            phase: "",
            cycle: laps,
            plannedMs: 0,
            actualMs: elapsed,
            startedAt: Date.now() - elapsed
        });
        root.stopwatch = {
            running: false,
            id: 0,
            label: "",
            startedAt: 0,
            accumulatedMs: 0,
            laps: []
        };
        Quickshell.execDetached(["notify-send", "-a", "timer", "-h", "string:category:x-timer", (label.length ? label + " — " : "") + "Stopwatch stopped", root.fmt(elapsed) + (laps ? "  ·  " + laps + " laps" : "")]);
        return true;
    }

    // ---------------------------------------------------------------------------------------
    // The card side: which entries are timers, where they go, and what they can be told to do.
    // ---------------------------------------------------------------------------------------

    // Did THIS shell raise this card? True for a running timer and for an announcement; false
    // for anything a client sent, whatever hints it copied.
    function ownsEntry(entry) {
        if (!entry || !entry.hints || !root.token.length)
            return false;
        const v = entry.hints["x-timer-token"];
        return v !== undefined && v !== null && String(v) === root.token;
    }

    // the HANDLE the card carries, not a run id — see the identity block above. Only a card this
    // shell raised for a RUNNING timer has one.
    function timerHandleOf(entry) {
        if (!root.ownsEntry(entry))
            return 0;
        const v = entry.hints["x-timer-id"];
        return v === undefined || v === null ? 0 : parseInt(v, 10) || 0;
    }

    // The live timer a card is showing, or null. Views call this; they must also touch
    // `revision` / `now` so QML re-evaluates the binding as the clock moves.
    function stateFor(entry) {
        const handle = root.timerHandleOf(entry);
        return handle ? root.byHandle(handle) : null;
    }

    // A running timer gets its own (monitor, anchor) stack rather than a slot in the notification
    // stack, so a card that is going to sit there for 25 minutes cannot push the notifications
    // you actually need to read out of their own overflow window.
    function applyPlacement(entry) {
        // ownsEntry, not timerHandleOf: an announcement carries no handle and still belongs in
        // the timer stack — and a client that guesses the hint names still cannot get here.
        if (!root.ownsEntry(entry))
            return;
        if (root.cfg.anchorH.length)
            entry.anchorH = root.cfg.anchorH;
        if (root.cfg.anchorV.length)
            entry.anchorV = root.cfg.anchorV;
    }

    // Built-in actions, offered in the same shape as a config action so the chips, the Ctrl+key
    // hints, focus mode and the compose surface all treat them identically. `kind: "timer"` is
    // what tells Notifications.invokeAction to call `perform` instead of running a subprocess —
    // going back out through `qs ipc call` would spawn a process to talk to ourselves.
    function actionsFor(entry) {
        const t = root.stateFor(entry);
        if (!t)
            return [];
        const handle = t.handle;
        return [
            {
                kind: "timer",
                label: t.paused ? "Resume" : "Pause",
                key: t.paused ? "r" : "p",
                spec: null,
                run: null,
                prompt: null,
                capture: "",
                perform: () => root.toggle(handle)
            },
            {
                kind: "timer",
                label: "+" + Math.round(root.cfg.addMs / 60000) + " min",
                key: "m",
                spec: null,
                run: null,
                prompt: null,
                capture: "",
                perform: () => root.extend(handle, 0)
            },
            {
                kind: "timer",
                label: "Reset",
                key: "e",
                spec: null,
                run: null,
                prompt: null,
                capture: "",
                perform: () => root.reset(handle)
            },
            {
                kind: "timer",
                label: "Cancel",
                key: "c",
                spec: null,
                run: null,
                prompt: null,
                capture: "",
                // cancel() takes its own card down. Nothing else on this path dismisses
                // anything, so there is no flag to say so — invokeAction returns straight after
                // perform() for every timer verb.
                perform: () => root.cancel(handle)
            }
        ];
    }

    // ---------------------------------------------------------------------------------------
    // IPC support
    // ---------------------------------------------------------------------------------------

    // Same shape as `notifications snoozed`: one line each, human first. Live timers come from
    // memory (they are the authority while this process is up); the stopwatch is appended
    // because it is a live timer too, just not one with an end.
    function summary() {
        const lines = [];
        for (const t of root.timers) {
            const bits = [String(t.handle), t.kind, root.cardSummary(t), (t.paused ? "paused " : "") + root.fmt(root.remainingOf(t)) + " left"];
            const phase = root.phaseLabel(t);
            if (phase.length)
                bits.push(phase);
            lines.push(bits.join(" — "));
        }
        if (root.stopwatch.id)
            lines.push(["sw", "stopwatch", root.stopwatch.label.length ? root.stopwatch.label : "Stopwatch", (root.stopwatch.running ? "" : "paused ") + root.fmt(root.stopwatchElapsed) + " elapsed", root.stopwatch.laps.length + " laps"].join(" — "));
        return lines.join("\n");
    }
}
