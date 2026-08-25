pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// org.freedesktop.Notifications server for the shell.
//
// This singleton owns EVERYTHING that isn't pixels: D-Bus name ownership (via the quickshell
// NotificationServer), the live popup list, expiry, and the seams the rest of the notification
// epic plugs into. NotificationOverlay.qml is a pure view over `popups` — keep it that way, the
// SQLite store story needs the model to exist without a window.
//
// Gated by Shell.notificationsEnabled (HYPR_NOTIFY=quickshell in ~/.config/hypr/shell.local.env).
// The server object only exists while that is set, so the D-Bus name is never contested with
// swaync: whoever owns the name first keeps it, and while we hold it swaync can't be D-Bus
// activated back into existence.
Singleton {
    id: root

    // ---------------------------------------------------------------------------------------
    // Config. Placement, motion and timing are USER config now (story: notif-placement-motion):
    // they live in ~/.config/quickshell/notifications.json and hot-reload on save, with the QML
    // constants in NotifyConfig as the fallback. Read them from here, never hardcode an anchor
    // or a duration downstream — and never write to them, the file is the source of truth.
    // ---------------------------------------------------------------------------------------

    readonly property var placement: NotifyConfig.placement
    readonly property var motion: NotifyConfig.motion
    // Durations in ms. 0 = sticky (never auto-expires).
    readonly property var timing: NotifyConfig.timing

    // ---------------------------------------------------------------------------------------
    // Live state
    // ---------------------------------------------------------------------------------------

    // Newest first. Entries are plain QtObjects (see entryComponent) — data, not views.
    property var popups: []
    readonly property int count: popups.length

    // Popups actually on screen: the rest are queued behind the overflow indicator, holding
    // their place (and their unstarted expiry timer) until a slot frees.
    readonly property int visibleCount: {
        var n = 0;
        for (var i = 0; i < popups.length; i++)
            if (!popups[i].queued && !popups[i].drawerOnly && popups[i].resolved)
                n++;
        return n;
    }

    // Notifications that have timed out into the bell since it was last read. Dismissing a card
    // by hand does NOT count — that is the user saying they have dealt with it.
    property int unread: 0
    function markRead() {
        root.unread = 0;
        NotifyStore.markAllRead();
    }

    // The count survives a daemon restart: it is restored from the rows the store has never seen
    // marked read, which is why a sticky critical from before a `qs` restart still shows up.
    Connections {
        target: NotifyStore
        function onUnreadAtStartChanged() {
            root.unread = NotifyStore.unreadAtStart;
        }
    }

    // Emitted when a dwelling card finishes its flight into the bar bell, so the bell can react
    // to the landing rather than guess at the timing.
    signal dwellLanded(string screenName)

    // Bell positions in screen coordinates, keyed by monitor name, published by the bar widget
    // (components/bar/NotificationBell.qml). The singleton only stores them: it holds no opinion
    // about pixels, but the dwell has to know whether a target exists at all before it starts.
    property var bellAnchors: ({})
    function setBellAnchor(screenName, x, y) {
        const next = Object.assign({}, root.bellAnchors);
        next[screenName] = {
            x: x,
            y: y
        };
        root.bellAnchors = next;
    }
    function clearBellAnchor(screenName) {
        const next = Object.assign({}, root.bellAnchors);
        delete next[screenName];
        root.bellAnchors = next;
    }
    readonly property bool bellAvailable: Object.keys(bellAnchors).length > 0

    readonly property bool serverActive: serverLoader.item !== null

    // ---------------------------------------------------------------------------------------
    // Rules seam (story: notif-lua-rules).
    //
    // Set `rulesHook` to a function(presentation, snapshot). It may mutate `presentation`;
    // `snapshot` is the read-only notification data. MUST fail open: any throw, any nonsense
    // value, and we fall back to defaults rather than dropping the notification.
    // ---------------------------------------------------------------------------------------
    property var rulesHook: null

    function presentationOf(entry) {
        return {
            durationMs: entry.durationMs,
            screenName: entry.screenName,
            anchorH: entry.anchorH,
            anchorV: entry.anchorV,
            // AD-012: the rules engine may VETO actions, never define them. Presentation is
            // where/how-long/how-loud; an action is not presentation.
            actions: entry.actionsAllowed
        };
    }

    // Write a presentation back onto an entry, key by key, validating each. A rule that
    // answers nonsense loses that key and keeps the rest — never the notification.
    function applyPresentation(entry, presentation) {
        if (!presentation)
            return;
        // negative is a legal answer here: it means drawer-only (see the duration vocabulary in
        // NotifyConfig), so a rule can silence a source without dropping its notifications.
        if (typeof presentation.durationMs === "number" && isFinite(presentation.durationMs))
            entry.durationMs = Math.round(presentation.durationMs);
        if (typeof presentation.screenName === "string")
            entry.screenName = presentation.screenName;
        if (["left", "center", "right"].indexOf(presentation.anchorH) >= 0)
            entry.anchorH = presentation.anchorH;
        if (["top", "center", "bottom"].indexOf(presentation.anchorV) >= 0)
            entry.anchorV = presentation.anchorV;
        // only an explicit `false` suppresses; anything else leaves actions alone, so a rule
        // that forgets the key cannot accidentally strip a client's own verbs
        if (presentation.actions === false)
            entry.actionsAllowed = false;
    }

    // In-process JS hook, kept alongside the Lua engine: it is what tests and a nested
    // harness use, and it runs synchronously before the engine so a Lua rule can still
    // override it.
    function applyRules(entry) {
        if (!rulesHook)
            return;
        const presentation = presentationOf(entry);
        try {
            rulesHook(presentation, snapshot(entry));
        } catch (e) {
            console.warn("notifications: rule hook threw, using defaults —", e);
            return;
        }
        applyPresentation(entry, presentation);
    }

    // ---------------------------------------------------------------------------------------
    // Serialization seam (story: notif-store). The popup model must be expressible as plain
    // data so it can be written to SQLite and read back without a live D-Bus object.
    // ---------------------------------------------------------------------------------------
    function snapshot(entry) {
        return {
            id: entry.nid,
            appName: entry.appName,
            appIcon: entry.appIcon,
            summary: entry.summary,
            body: entry.body,
            urgency: entry.urgency,
            // the same value as a word, for rules: `n.urgency == 2` is a magic number in
            // someone's config file, `n.urgencyName == "critical"` is not
            urgencyName: ["low", "normal", "critical"][entry.urgency] || "normal",
            category: entry.category,
            image: entry.image,
            value: entry.value,
            transient: entry.isTransient,
            resident: entry.resident,
            durationMs: entry.durationMs,
            timestamp: entry.timestamp.getTime()
        };
    }

    // ---------------------------------------------------------------------------------------
    // Ingest
    // ---------------------------------------------------------------------------------------

    function present(n) {
        // Nothing is kept unless we say so — an untracked notification is dropped the moment
        // this handler returns.
        n.tracked = true;

        // A replaces_id arriving for a notification we already hold does NOT re-emit this
        // signal: quickshell mutates the existing Notification in place. That is why every
        // entry field is a binding onto the notification rather than a copy — the card
        // follows the update with no new card and no second entry. Belt and braces, a
        // re-emitted id still refreshes the existing entry instead of stacking one.
        const existing = entryForId(n.id);
        if (existing && existing.notification === n) {
            refresh(existing);
            return;
        }

        const entry = entryComponent.createObject(root, {
            notification: n,
            timestamp: new Date(),
            anchorH: placement.anchorH,
            anchorV: placement.anchorV,
            // "" = follow the focused monitor. A rule (or the config) can name one instead.
            screenName: placement.screenName
        });

        const list = popups.slice();
        if (existing) {
            list[list.indexOf(existing)] = entry;
            popups = list;
            releaseEntry(existing);
        } else {
            list.unshift(entry);
            popups = list;
        }
        refresh(entry);
    }

    // (Re)derive everything that isn't a straight binding: duration, rule overrides, timer.
    // Called on arrival and whenever a live notification is updated underneath us.
    // The Lua engine answers on a pipe, so this half of refresh() is asynchronous. An entry
    // that has not been answered for yet is `resolved: false` and the view skips it — a card
    // must not appear at the default anchor and then jump to the one a rule chose. The
    // engine's deadline (NotifyRules.timeoutMs, ~50ms) bounds that wait, and a shell with no
    // rules, no lua, or a broken rules file calls back immediately, so this is the same
    // single frame it always was.
    function refresh(entry) {
        entry.durationMs = defaultDurationMs(entry);
        // A timer card is pinned to its own anchor BEFORE the rules run, so a rule can still
        // move it. Everything else about a timer belongs to the Timers singleton; this is the
        // one thing that has to happen on the ingest path, because the stack a card lands in is
        // decided here (story: notif-timers, "a timer pinned top does not fight the stack").
        Timers.applyPlacement(entry);
        // DND's suppression default (story: notif-dnd-core), applied before the rules engine
        // sees this notification: a Lua rule's answer is the last write and can restore
        // visibility, same "accumulate, last write wins" contract the engine already has.
        NotifyDnd.applySuppression(entry);
        applyRules(entry);
        NotifyRules.evaluate(snapshot(entry), presentationOf(entry), presentation => {
            // the notification may have been closed while the engine was thinking
            if (popups.indexOf(entry) < 0)
                return;
            applyPresentation(entry, presentation);
            finishRefresh(entry);
        });
    }

    function finishRefresh(entry) {
        entry.resolved = true;
        // a rule may have moved the entry to another anchor or monitor, so its stack — and with
        // it whether it is visible at all — is only settled after the rules have run
        reflow();
        scheduleExpiry(entry);
        recordDrawerOnly(entry);

        // DND exit digest (story: notif-dnd-core): count this entry only if it was subject to
        // the DND default AND stayed drawer-only after the rules ran — a rule exception that
        // restored visibility means this notification was never actually suppressed. Guarded by
        // dndCounted so an in-place update (replaces_id, a hint change) can't double-count the
        // same entry on a later refresh().
        if (entry.dndBaseline && entry.drawerOnly && !entry.dndCounted) {
            entry.dndCounted = true;
            NotifyDnd.noteSuppressed();
        }

        // History write, always after the rules: what is stored is what was actually
        // presented, not what arrived. Asynchronous and best-effort — see NotifyStore.
        if (entry.stored)
            NotifyStore.update(entry, snapshot(entry));
        else {
            entry.stored = true;
            NotifyStore.record(entry, snapshot(entry));
        }
    }

    // Drawer-only entries never appear, so nothing else would mark them seen or bound how many
    // of them accumulate. Until the store and drawer stories land they live here: counted once
    // into `unread`, newest `drawerRetention` kept, the rest closed as expired.
    readonly property int drawerRetention: 100

    function recordDrawerOnly(entry) {
        if (!entry.drawerOnly || entry.counted)
            return;
        entry.counted = true;
        root.unread++;

        const stale = [];
        var kept = 0;
        for (var i = 0; i < popups.length; i++) {
            if (!popups[i].drawerOnly)
                continue;
            kept++;
            if (kept > root.drawerRetention)
                stale.push(popups[i]);
        }
        for (const e of stale) {
            if (e.notification)
                e.notification.expire();
            forget(e);
        }
    }

    function entryForId(nid) {
        for (var i = 0; i < popups.length; i++)
            if (popups[i].nid === nid)
                return popups[i];
        return null;
    }

    // ---------------------------------------------------------------------------------------
    // Overflow. Each (monitor, anchor) stack shows at most placement.maxVisible cards; the rest
    // stay in the model as `queued` and surface as a "+N more" indicator in the view.
    //
    // A queued entry's expiry timer is NOT running. Counting down while off screen would expire
    // notifications the user never saw — "queues without loss" has to mean the dwell starts when
    // the card appears, not when it arrived.
    // ---------------------------------------------------------------------------------------

    function stackKey(entry) {
        return entry.screenName + "|" + entry.anchorH + "|" + entry.anchorV;
    }

    // Which rank each stack starts showing at. 0 for every stack unless keyboard focus has
    // scrolled one (story: notif-keyboard-control) — the cap on visible cards never moves, the
    // window onto the queue does, so the overflow is reachable without a pointer.
    property var scrollOffsets: ({})

    function scrollFor(key) {
        const n = root.scrollOffsets[key];
        return n === undefined ? 0 : n;
    }

    function setScroll(key, offset) {
        const next = Math.max(0, Math.round(offset));
        if (root.scrollFor(key) === next)
            return;
        const map = Object.assign({}, root.scrollOffsets);
        if (next === 0)
            delete map[key];
        else
            map[key] = next;
        root.scrollOffsets = map;
        root.reflow();
    }

    function clearScroll() {
        if (Object.keys(root.scrollOffsets).length === 0)
            return;
        root.scrollOffsets = ({});
        root.reflow();
    }

    function reflow() {
        const seen = {};
        for (var i = 0; i < popups.length; i++) {
            const entry = popups[i];
            // not through the rules engine yet: no anchor is settled, so it can neither take a
            // slot nor push another card into the queue (see refresh)
            if (!entry.resolved) {
                entry.queued = false;
                continue;
            }
            // drawer-only entries are in the model but were never on screen: they take no slot,
            // hold no timer, and must not push a visible card into the overflow queue
            if (entry.drawerOnly) {
                entry.queued = false;
                entry.expiryTimer.stop();
                continue;
            }
            const key = stackKey(entry);
            const rank = seen[key] === undefined ? 0 : seen[key];
            seen[key] = rank + 1;

            const off = root.scrollFor(key);
            const queued = rank < off || rank >= off + placement.maxVisible;
            if (queued === entry.queued)
                continue;
            entry.queued = queued;
            if (queued)
                entry.expiryTimer.stop();
            else
                scheduleExpiry(entry); // its dwell starts now that it is actually on screen
        }
    }

    // How many entries are queued behind the visible cards of one stack — the "+N more" count.
    function overflowFor(screenName, anchorH, anchorV) {
        var n = 0;
        for (var i = 0; i < popups.length; i++) {
            const e = popups[i];
            if (e.queued && e.screenName === screenName && e.anchorH === anchorH && e.anchorV === anchorV)
                n++;
        }
        return n;
    }

    onPopupsChanged: reflow()
    // config edits are live: raising maxVisible must release queued cards immediately
    onPlacementChanged: reflow()
    // ...and a timing edit re-derives every duration on screen, so tuning a value is visible on
    // the cards that are already up rather than only on the next notification. Clocks restart.
    onTimingChanged: {
        for (const e of popups.slice())
            refresh(e);
    }

    // ---------------------------------------------------------------------------------------
    // Expiry — every timeout in the shell routes through here.
    //
    // Duration vocabulary (same in the config file, in a rule's presentation, and on the entry):
    //   > 0  show for that long   |   0  sticky   |   < 0  drawer-only, never popped.
    //
    // A card's clock is NOT its Timer's interval: hover pause has to know how much is left, so
    // `remainingMs` + `startedAt` are the truth and the Timer is re-armed from them.
    // ---------------------------------------------------------------------------------------

    function defaultDurationMs(entry) {
        // expireTimeout is MILLISECONDS, straight off the wire (org.freedesktop.Notifications
        // Notify's expire_timeout argument): >0 explicit, 0 = never expire, <0 = server default.
        // It was read as seconds until this story, which multiplied every client-set timeout by
        // 1000 — `notify-send -t 1500` sat on screen for 25 minutes instead of 1.5 seconds.
        const t = entry.notification ? entry.notification.expireTimeout : -1;
        if (t === 0)
            return 0;
        if (timing.respectAppTimeout && t > 0)
            return Math.round(t);
        if (entry.urgency === NotificationUrgency.Critical)
            return timing.critical;
        if (entry.urgency === NotificationUrgency.Low)
            return timing.low;
        return timing.normal;
    }

    // Burst relief: a stack that is already full drains faster instead of growing without end.
    // Critical is never shortened — the whole point of critical is that it outlasts the noise.
    function effectiveDurationMs(entry) {
        const ms = entry.durationMs;
        if (ms <= 0 || timing.burstMs <= 0)
            return ms;
        if (entry.urgency === NotificationUrgency.Critical)
            return ms;
        const threshold = timing.burstAt > 0 ? timing.burstAt : placement.maxVisible;
        return root.visibleCount >= threshold ? Math.min(ms, timing.burstMs) : ms;
    }

    function scheduleExpiry(entry) {
        entry.expiryTimer.stop();
        entry.paused = false;
        scheduleCollapse(entry);
        if (entry.durationMs <= 0)
            return; // sticky, or drawer-only and never on screen to begin with
        if (entry.queued)
            return; // off screen: the clock starts when a slot frees (see reflow)
        entry.spanMs = effectiveDurationMs(entry);
        entry.remainingMs = entry.spanMs;
        entry.startedAt = Date.now();
        entry.expiryTimer.interval = entry.spanMs;
        entry.expiryTimer.start();
        entry.runToken++; // tells the card to restart its countdown indicator from the top
        // a card that arrives while the stack is keyboard-focused starts out frozen like the
        // rest of them, rather than being the one card that can vanish mid-read
        //
        // The same for the card being composed, and this is the path that actually bit: every
        // refresh() lands here, `paused` is cleared unconditionally two lines up, and a store
        // write or an in-place update is enough to re-arm the clock under a surface the user is
        // typing into. Freezing has to be re-asserted wherever the clock is armed, not only where
        // it is stopped.
        if (root.keyboardHold || NotifyCompose.owns(entry))
            root.pause(entry, true);
    }

    // Hover (and, later, keyboard focus) freezes a card: the countdown stops where it is and the
    // collapse clock with it, so reading a card can never make it disappear mid-sentence.
    // `force` is the keyboard's pause: hoverPause is a preference about the POINTER, and someone
    // who has deliberately focused the stack from the keyboard is reading it by definition.
    function pause(entry, force) {
        if (!entry || entry.paused || entry.leaving)
            return;
        if (entry.isRow)
            return; // an adapted database row has no clock to freeze (see rowAsEntry)
        if (!force && !timing.hoverPause)
            return;
        if (entry.expiryTimer.running) {
            entry.remainingMs = Math.max(0, entry.remainingMs - (Date.now() - entry.startedAt));
            entry.expiryTimer.stop();
        }
        entry.collapseTimer.stop();
        entry.paused = true;
    }

    // While the keyboard holds the stack, the pointer leaving a card must NOT restart its clock —
    // otherwise moving the mouse out of the way while reading expires the card being read.
    property bool keyboardHold: false

    function holdAll() {
        root.keyboardHold = true;
        for (const e of popups.slice())
            root.pause(e, true);
    }

    function releaseAll() {
        root.keyboardHold = false;
        for (const e of popups.slice())
            root.resume(e);
    }

    function resume(entry) {
        if (!entry || !entry.paused || root.keyboardHold || entry.isRow)
            return;
        // Being composed freezes the clock as hard as keyboardHold does, and for a sharper
        // reason: opening compose puts a full-window scrim over the stack, which the card below
        // reads as the POINTER LEAVING — so the card resumed its own countdown the instant the
        // compose surface appeared and expired underneath it mid-sentence.
        if (NotifyCompose.owns(entry))
            return;
        entry.paused = false;
        if (entry.leaving || entry.queued || entry.durationMs <= 0) {
            scheduleCollapse(entry); // sticky: nothing to count down, but it may still collapse
            return;
        }
        entry.startedAt = Date.now();
        entry.expiryTimer.interval = Math.max(1, entry.remainingMs);
        entry.expiryTimer.start();
        entry.runToken++;
    }

    // Collapsed cards live in the bar rather than the stack when there IS a bar to live in —
    // otherwise the pill has nowhere to go and stays where it folded.
    readonly property bool dockCollapsed: NotifyConfig.collapse.home === "bar" && Shell.barVisible

    // Shrink-to-icon. A sticky card is the only kind that can outstay its welcome — after
    // criticalCollapseMs it becomes a pill (icon + app name) that keeps its place in the stack
    // without covering anything. Any sticky entry collapses, not only critical ones: an urgency
    // configured sticky has exactly the same problem.
    function scheduleCollapse(entry) {
        entry.collapseTimer.stop();
        entry.collapsed = false;
        if (entry.durationMs !== 0 || entry.queued || entry.leaving)
            return;
        if (timing.criticalCollapseMs <= 0)
            return;
        entry.collapseTimer.interval = timing.criticalCollapseMs;
        entry.collapseTimer.start();
    }

    // ---------------------------------------------------------------------------------------
    // Copy. A notification is often the only place a build id, a hostname or an error string
    // exists, and re-typing it from a card that is about to expire is the worst way to move it.
    // wl-copy rather than a QML clipboard API: the text has to outlive this process (a popup is
    // gone in seconds), and wl-copy forks a daemon that keeps serving the selection.
    // ---------------------------------------------------------------------------------------

    signal copied(string text)

    function copyText(entry, bodyOnly) {
        if (!entry)
            return "";
        const body = entry.body || "";
        if (bodyOnly)
            return body;
        const summary = entry.summary || "";
        return summary && body ? summary + "\n" + body : (summary || body);
    }

    function copy(entry, bodyOnly) {
        const text = root.copyText(entry, bodyOnly);
        if (!text)
            return;
        // argv, never a shell string: a summary is attacker-controlled in the general case —
        // any app on the session bus can set it — and `sh -c` here would be a command injection
        // with extra steps.
        Quickshell.execDetached(["wl-copy", "--", text]);
        root.copied(text);
    }

    // One click on a collapsed pill brings the whole card back — and restarts the collapse clock,
    // so an expanded-then-forgotten critical folds itself away again.
    function expand(entry) {
        if (!entry || !entry.collapsed)
            return;
        scheduleCollapse(entry);
    }

    // ---------------------------------------------------------------------------------------
    // Removal. Three ways out: the client closes it (CloseNotification), it expires, or the
    // user dismisses it. The first is signalled TO us; the other two we signal outward so the
    // client gets its NotificationClosed with the right reason.
    // ---------------------------------------------------------------------------------------


    // ---------------------------------------------------------------------------------------
    // Actions (story: notif-actions; shape settled in AD-012)
    //
    // TWO KINDS, ONE KEY SCHEME. A **spec** action arrived in the D-Bus `actions` array and is
    // invoked by handing it back to the client; a **custom** action came from
    // NotifyConfig.actions and is run here as a subprocess. They render identically on the card
    // because the user does not care which side of D-Bus a verb lives on.
    //
    // Hints are assigned SPEC FIRST, then custom, so a client's own "Reply" never has its key
    // stolen by a config rule.
    // ---------------------------------------------------------------------------------------

    // `~foo` is a regex; anything else is an exact, case-insensitive compare. Same vocabulary
    // the Lua rules engine matches on, so there is one thing to learn.
    function matchOne(pattern, value) {
        const v = String(value === undefined || value === null ? "" : value);
        const pat = String(pattern);
        if (pat.length > 1 && pat.charAt(0) === "~") {
            try {
                return new RegExp(pat.substring(1), "i").test(v);
            } catch (e) {
                // a bad regex must not match everything — that would fire an action on every
                // notification. Fail closed and say so once.
                console.warn("notifications: action matcher", pat, "is not a valid regex —", e);
                return false;
            }
        }
        return v.toLowerCase() === pat.toLowerCase();
    }

    // All present keys must match (AND). An empty matcher matches everything, which is a
    // legitimate way to declare a global action.
    function actionMatches(match, entry) {
        if (!match)
            return true;
        for (const key in match) {
            const want = match[key];
            let have;
            if (key === "app")
                have = entry.appName;
            else if (key === "category")
                have = entry.category;
            else if (key === "urgency")
                have = entry.urgency;
            else if (key === "summary")
                have = entry.summary;
            else if (key === "body")
                have = entry.body;
            else if (key.indexOf("hint.") === 0)
                have = entry.hints[key.substring(5)];
            else {
                console.warn("notifications: unknown action matcher key", key, "— never matches");
                return false;
            }
            if (!root.matchOne(want, have))
                return false;
        }
        return true;
    }

    // The merged, key-hinted list the card renders and the keyboard answers.
    function actionsFor(entry) {
        const out = [];
        if (!entry || !entry.actionsAllowed)
            return out;

        // Spec actions. quickshell exposes NotificationAction { identifier, text, invoke() }.
        // The `default` identifier is the click-the-card action and is NOT given a key or a
        // button — it is what activating the card itself means.
        const spec = entry.notification ? entry.notification.actions : [];
        for (let i = 0; i < spec.length; i++) {
            const a = spec[i];
            if (String(a.identifier) === "default")
                continue;
            out.push({
                kind: "spec",
                label: String(a.text).length ? String(a.text) : String(a.identifier),
                key: "",
                spec: a,
                run: null,
                prompt: null,
                capture: ""
            });
        }

        // Built-in timer actions (story: notif-timers). They are offered on a timer's own card
        // only — Timers.actionsFor returns nothing for anything else — and they render, hint and
        // key exactly like a config action, because pause/reset/+5min are verbs on a
        // notification and not a second control surface.
        const timerActions = Timers.actionsFor(entry);
        for (let i = 0; i < timerActions.length; i++)
            out.push(timerActions[i]);

        // Built-in snooze actions (this ticket: give snooze a visible affordance — it shipped
        // as the `s`/`r` keys only, which never reach a card the user has not focused). `kind:
        // "snooze"` tells invokeAction to call `perform()` in process, the seam Timers.actionsFor
        // above already proved: routing a snooze back out through IPC would spawn a process for
        // this shell to talk to itself.
        //
        // Behind the SAME `actionsAllowed` gate at the top of this function as every other
        // action here (spec/timer/custom) — a Lua rule that sets `actionsAllowed = false` hides
        // this chip too. That is a real divergence from the keys: `NotifyFocus.snoozeSelected`
        // has no such check, so `s`/`r` still snooze a card whose chips a rule just hid. Left
        // that way on purpose — the veto is meant to say "no action surface on this card", and
        // exempting snooze from it would need its own rule-engine hook this ticket does not add.
        // The keyboard path predates this chip and is unchanged by it.
        //
        // ONLY the default-duration chip is offered here. A "Remind at…" chip that OPENS the
        // time-mode prompt by mouse looked right in review and was not: submitting that prompt
        // needs the layershell window's keyboard grab, which only ever turns on for
        // `NotifyFocus.active` or the compose surface (`NotificationOverlay.qml:102,108`) —
        // `entry.prompting` is not part of that condition. A mouse user could open the field and
        // then type into nothing, with the card frozen (`beginPrompt` calls `root.pause`) until
        // they found the X. Config `presets` gives mouse-only users more than one duration
        // without needing to type at all; free-text "remind me at ___" stays keyboard-only (`r`)
        // until a grab scoped to `entry.prompting` lands — see
        // Tasks/quickshell-notif-prompt-needs-scoped-grab.
        //
        // Timer cards are skipped entirely: `Timers.actionsFor(entry)` is non-empty exactly when
        // this is a running timer's own card, and Notifications.snooze() calls forget(entry) ->
        // entry.destroy() while the timer keeps counting down against a now-destroyed entry.
        // 15 minutes later the elapsed-snooze path (see snoozeElapsed below) would raise a
        // plain notify-send copy of the stored row — a stale "time's up" card with none of the
        // timer's Pause/Reset/Cancel verbs, for a timer that already finished. A timer is
        // already its own snooze (pause/extend); it does not need a second one.
        //
        // NOT offered on `actionsForRow` (drawer rows) either: the whole point there is history
        // that survives the live client, and every one of these actions runs against `entry`
        // fields (`nid`, live pause/resume) a `rowAsEntry()` adapter fakes only partially.
        // Snoozing history is out of scope for this ticket.
        if (timerActions.length === 0) {
            out.push({
                kind: "snooze",
                label: "Snooze " + root.snoozeLabel(NotifyConfig.snooze.defaultMs),
                key: "s",
                spec: null,
                run: null,
                prompt: null,
                capture: "",
                perform: () => root.snooze(entry, NotifyConfig.snooze.defaultMs)
            });
            const presets = NotifyConfig.snooze.presets;
            for (let i = 0; i < presets.length; i++) {
                const text = presets[i];
                const ms = root.parseDelay(text);
                if (ms === null) {
                    console.warn("notifications: snooze preset", JSON.stringify(text), "does not parse — skipped");
                    continue;
                }
                out.push({
                    kind: "snooze",
                    label: "Snooze " + root.snoozeLabel(ms),
                    key: "",
                    spec: null,
                    run: null,
                    prompt: null,
                    capture: "",
                    perform: () => root.snooze(entry, ms)
                });
            }
        }

        // Custom actions, in config order.
        const cfg = NotifyConfig.actions;
        for (let i = 0; i < cfg.length; i++) {
            const c = cfg[i];
            if (!root.actionMatches(c.match, entry))
                continue;
            out.push({
                kind: "custom",
                label: c.label,
                key: c.key,
                spec: null,
                run: c.run,
                prompt: c.prompt,
                // WITHOUT THIS the whole capture feature is dead: invokeAction tests
                // `action.capture`, and an action object that never carried the field left every
                // `capture = "draft"` / `"reply"` action running as fire-and-forget. Nothing
                // logged, because nothing failed — the command ran and its stdout was dropped.
                capture: c.capture
            });
        }

        // Assign hints as CTRL + LETTER.
        //
        // Bare letters are not available: focus mode is vim-shaped and owns j/k/d/x/D/y/Y/s/r/
        // o/g/G/a, and losing `d` to an action would break dismiss while a card is selected.
        // Digits were the first fix and worked, but they are positional — "3" tells you nothing
        // about what it does, and the config in AD-012 declares mnemonic keys (`r` for Reply,
        // `o` for Open MR, `l` for Logs) that had to be thrown away to use them.
        //
        // Ctrl is untouched by the focus-mode scheme (its only modifier is Shift), so
        // Ctrl+<letter> keeps the mnemonics AND collides with nothing. A declared key is used
        // as-is; otherwise the first free letter OF THE LABEL is preferred, so "Reply" gets
        // Ctrl+R without anyone configuring it.
        const used = {};
        for (let i = 0; i < out.length; i++) {
            const want = String(out[i].key).toLowerCase();
            if (want.length === 1 && want >= "a" && want <= "z" && !used[want]) {
                out[i].key = want;
                used[want] = true;
            } else {
                if (want.length)
                    console.warn("notifications: action", out[i].label, "requested key", want,
                        "— already taken or not a letter, falling back to a derived hint");
                out[i].key = "";
            }
        }
        // mnemonic pass: first unused letter of the label
        for (let i = 0; i < out.length; i++) {
            if (out[i].key.length)
                continue;
            const label = String(out[i].label).toLowerCase();
            for (let j = 0; j < label.length; j++) {
                const c = label.charAt(j);
                if (c >= "a" && c <= "z" && !used[c]) {
                    out[i].key = c;
                    used[c] = true;
                    break;
                }
            }
        }
        const seq = "abcdefghijklmnopqrstuvwxyz";
        for (let i = 0; i < out.length; i++) {
            if (out[i].key.length)
                continue;
            for (let j = 0; j < seq.length; j++) {
                if (!used[seq.charAt(j)]) {
                    out[i].key = seq.charAt(j);
                    used[seq.charAt(j)] = true;
                    break;
                }
            }
        }
        return out;
    }

    // --- actions on STORED rows (the drawer) ------------------------------------------------
    //
    // Custom actions only, and that is a property of the world rather than a shortcut: a spec
    // action is invoked by handing it back to the client over D-Bus, and by the time a row is
    // history the process that offered "Reply" has usually exited. There is nothing to hand it
    // to. Custom actions run here, so they work on a row from last week.
    //
    // A drawer row is a plain object from SQLite, not an entry, so it is adapted to the shape
    // the matcher and the substituter already expect rather than duplicating either.
    function rowAsEntry(row) {
        return {
            nid: row.nid !== undefined ? row.nid : 0,
            appName: row.app_name !== undefined ? row.app_name : "",
            summary: row.summary !== undefined ? row.summary : "",
            body: row.body !== undefined ? row.body : "",
            category: row.category !== undefined ? row.category : "",
            urgency: row.urgency !== undefined ? row.urgency : 1,
            // hints are not stored per column; a matcher on hint.* simply never matches a
            // stored row, which is honest rather than a silent partial match
            hints: ({}),
            actionsAllowed: true,
            resident: true, // nothing to dismiss: the popup is long gone
            // This is an adapter over a database row, NOT a live entry: it has no timers, no
            // notification object and no place in `popups`. Everything that would touch those
            // tests this flag — pause(), resume() and submitPrompt() all took a live entry for
            // granted, and a capturing action invoked from the drawer died on the first
            // `entry.expiryTimer` with a TypeError in the log and no action run.
            //
            // NOT named `stored`: a live entry already has a property of that name meaning "a
            // history row exists for this one", which is true of nearly every card a few hundred
            // milliseconds after it appears. Reusing the word made pause() return early for every
            // live notification, so the card being composed expired under the compose surface.
            isRow: true,
            // plain fields so the paths that write them are harmless here
            paused: false,
            leaving: false,
            prompting: false,
            promptAction: null,
            promptTimeMode: false,
            awaitingCapture: false
        };
    }

    function actionsForRow(row) {
        const entry = root.rowAsEntry(row);
        const out = [];
        const cfg = NotifyConfig.actions;
        for (let i = 0; i < cfg.length; i++) {
            const c = cfg[i];
            if (!root.actionMatches(c.match, entry))
                continue;
            // A CAPTURING action is offered here only when it has somewhere to put its output,
            // and on a stored row it does not: `capture` means "write this into the reply field",
            // and a row invoked as a row has no live client to send that reply to. Offering the
            // verb anyway would spend a model call to produce text that vanishes. Compose
            // re-associates a live entry when one exists and then uses actionsFor(), which does
            // offer them — so this only hides what genuinely cannot work.
            if (c.capture)
                continue;
            out.push({
                kind: "custom",
                label: c.label,
                key: c.key,
                spec: null,
                run: c.run,
                prompt: c.prompt,
                capture: ""
            });
        }
        return out;
    }

    function invokeRowAction(row, action, input) {
        if (!action || action.kind !== "custom")
            return;
        root.invokeAction(root.rowAsEntry(row), action, input);
    }

    // The default action, if the client supplied one: what clicking the card means.
    function defaultActionFor(entry) {
        if (!entry || !entry.actionsAllowed || !entry.notification)
            return null;
        const spec = entry.notification.actions;
        for (let i = 0; i < spec.length; i++) {
            if (String(spec[i].identifier) === "default")
                return spec[i];
        }
        return null;
    }

    // Substitutions produce ARGV ELEMENTS. This is the security boundary in AD-012: any app on
    // the session bus can set a summary, so a value is only ever one argument — never spliced
    // into a shell string, and no `sh -c` wrapper is added anywhere on this path.
    function substituteArgv(argv, entry, input) {
        const map = {
            "{id}": String(entry.nid),
            "{app}": entry.appName,
            "{summary}": entry.summary,
            "{body}": entry.body,
            "{input}": input === undefined || input === null ? "" : String(input)
        };
        const out = [];
        for (let i = 0; i < argv.length; i++) {
            let a = String(argv[i]);
            for (const k in map)
                a = a.split(k).join(map[k]);
            a = a.replace(/\{hint:([^}]+)\}/g, (m, name) => {
                const v = entry.hints[name];
                return v === undefined || v === null ? "" : String(v);
            });
            out.push(a);
        }
        return out;
    }

    // A failing action has to say so. Silently doing nothing is indistinguishable from a
    // missed keypress, and the user has already moved on.
    function actionFailed(entry, action, reason) {
        console.warn("notifications: action", action.label, "failed —", reason);
        // Round-trip through notify-send rather than synthesising an entry directly: this
        // shell IS the server, so the failure lands in the popup stack AND the history store
        // by the same path as everything else, instead of being a special case that only
        // exists on screen. argv, never a shell string — the label came from config and the
        // reason can contain anything the process printed.
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "quickshell",
                "Action failed", action.label + " — " + reason]);
    }

    function invokeAction(entry, action, input) {
        if (!entry || !action)
            return;
        if (action.kind === "spec") {
            // Hand it back to the client. `resident` decides whether the notification survives;
            // that is the client's call, not ours (see the entry property of the same name).
            try {
                action.spec.invoke();
            } catch (e) {
                root.actionFailed(entry, action, String(e));
                return;
            }
            if (!entry.resident)
                root.dismiss(entry);
            return;
        }

        // A built-in verb (timer or snooze) runs IN PROCESS. Everything it needs is already on
        // this singleton or Timers, so routing it back out through `qs ipc call …` would spawn a
        // process for this shell to talk to itself — and would fail on a machine where `qs` is
        // not on PATH for the shell's own environment.
        if (action.kind === "timer" || action.kind === "snooze") {
            try {
                action.perform();
            } catch (e) {
                root.actionFailed(entry, action, String(e));
                return;
            }
            // No dismiss on this path at all: pausing a timer must leave its card exactly
            // where it was and cancel takes its own card down inside perform(); a snooze
            // removes the card itself (root.snooze() -> forget(), or refuses and leaves the
            // card alone if the store cannot persist it).
            return;
        }

        const argv = root.substituteArgv(action.run, entry, input);
        const runner = runnerComponent.createObject(root, {
            "command": argv,
            "entry": entry,
            "action": action
        });
        if (!runner) {
            root.actionFailed(entry, action, "could not start");
            return;
        }
        runner.running = true;
        // A capturing action OWNS the card until it answers — its whole point is to put text
        // back into this notification, so dismissing it here would throw away the destination.
        // The card is also frozen, because a model takes seconds and the dwell would expire
        // underneath it.
        if (action.capture) {
            entry.awaitingCapture = true;
            root.pause(entry);
            return;
        }
        if (!entry.resident)
            root.dismiss(entry);
    }

    // One Process per invocation, destroyed on exit. A pool would be premature: actions are
    // user-initiated and rare, and a shared Process would serialise two of them.
    Component {
        id: runnerComponent

        Process {
            id: runner
            property var entry: null
            property var action: null
            stdout: StdioCollector {}
            onExited: (code, status) => {
                const entry = runner.entry;
                const action = runner.action;
                if (entry)
                    entry.awaitingCapture = false;
                if (code !== 0) {
                    root.actionFailed(entry, action, "exit " + code);
                    if (entry)
                        root.resume(entry);
                    runner.destroy();
                    return;
                }
                if (action && action.capture && entry) {
                    const text = runner.stdout.text.trim();
                    if (!text.length) {
                        root.actionFailed(entry, action, "produced no output");
                        root.resume(entry);
                    } else if (action.capture === "reply") {
                        root.submitPrompt(entry, text);
                    } else if (NotifyCompose.owns(entry)) {
                        // the compose surface is open on this notification: the draft belongs in
                        // the field the user is looking at, not in the card behind it
                        NotifyCompose.loadDraft(text);
                    } else {
                        // draft: open the field pre-filled so it is read before it is sent
                        root.beginPrompt(entry, null, false);
                        root.draftText = text;
                        root.draftToken++;
                    }
                }
                runner.destroy();
            }
        }
    }


    // An elapsed snooze comes back as a fresh notification, rebuilt from the stored row and
    // re-emitted through notify-send — the same round-trip actionFailed uses.
    //
    // It cannot be the ORIGINAL notification: that object died with the client, or with the
    // last qs. So the reminder is honestly a new one, tagged so it reads as a reminder rather
    // than as the app having spoken again. Actions are lost with the client, which is inherent
    // — by the time a snooze fires, the process that offered "Reply" may not exist.
    //
    // Sticky (-t 0) on purpose: you asked to be reminded, so it waits to be dealt with.
    Connections {
        target: NotifyStore

        function onSnoozeElapsed(appName, summary, body, urgency) {
            const urg = urgency >= 2 ? "critical" : (urgency <= 0 ? "low" : "normal");
            Quickshell.execDetached(["notify-send", "-t", "0", "-u", urg, "-a", appName.length ? appName : "quickshell", "-h", "string:category:x-vault.reminder", summary.length ? summary : "Reminder", body]);
        }
    }

    // --- prompts / inline reply (AD-012 §3) -------------------------------------------------
    //
    // A prompt is offered where a text reply is the notification's NATURAL response and the
    // reply has somewhere to go. Three ways to qualify, and no fourth:
    //   1. the client asked for one (inline-reply hint), or
    //   2. the category is on the written allowlist, or
    //   3. a matching custom action declares `prompt`.
    // "Build failed" gets actions, not a prompt — there is no recipient. Adding one anywhere
    // else is a deliberate config edit, which is the whole point of writing the list down.
    function promptable(entry) {
        if (!entry || !entry.actionsAllowed)
            return false;
        if (entry.hasInlineReply)
            return true;
        const cats = NotifyConfig.prompt.categories;
        if (entry.category.length && cats.indexOf(entry.category) >= 0)
            return true;
        return false;
    }

    // Snooze: hand the row to the store and let the popup go. The store owns the schedule
    // (AD-012 §4) — one armed timer for the earliest wake_at, rows already due fired at start —
    // so nothing here has to survive a restart.
    function snooze(entry, ms) {
        if (!entry)
            return;
        // NotifyStore.snooze() is a silent no-op with the store disabled or unhealthy (it
        // returns before the UPDATE), but forget() below does not know that and would still
        // drop the popup — a click (or the `s`/`r` keys, same function) would delete the
        // notification with nothing persisted to bring it back. Refuse instead of forgetting.
        if (!NotifyConfig.store.enabled || !NotifyStore.healthy) {
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "quickshell",
                    "Snooze failed", "notification history is unavailable — nothing was snoozed"]);
            return;
        }
        const wake = Date.now() + Math.max(0, Math.round(ms));
        NotifyStore.snooze(entry.nid, wake);
        // forget(), not dismiss(): dismiss would write state = 'dismissed' over the
        // 'snoozed' row the store just set, and the notification would never come back.
        // The popup goes; the row is what remembers.
        root.forget(entry);
        root.reflow();
    }

    // The inverse of parseDelay, for the chip label only ("45s", "15m", "1h", "1h30m"). Never
    // fed back into parseDelay or the store — it is display text, not a second duration format.
    function snoozeLabel(ms) {
        const totalSec = Math.max(1, Math.round(ms / 1000));
        if (totalSec < 60)
            return totalSec + "s";
        const totalMin = Math.round(totalSec / 60);
        if (totalMin < 60)
            return totalMin + "m";
        const h = Math.floor(totalMin / 60);
        const m = totalMin % 60;
        return m === 0 ? h + "h" : h + "h" + m + "m";
    }

    // "20m", "2h", "90s", "17:30". Returns null for anything it cannot read — AD-012 is
    // explicit that this rejects rather than guesses.
    function parseDelay(text) {
        const t = String(text).trim().toLowerCase();
        if (!t.length)
            return null;
        let m = t.match(/^([0-9]+)\s*([smhd])$/);
        if (m) {
            const n = parseInt(m[1], 10);
            const unit = { s: 1000, m: 60000, h: 3600000, d: 86400000 }[m[2]];
            return Math.min(n * unit, NotifyConfig.snooze.maxMs);
        }
        m = t.match(/^([0-9]{1,2}):([0-9]{2})$/);
        if (m) {
            const now = new Date();
            const at = new Date(now);
            at.setHours(parseInt(m[1], 10), parseInt(m[2], 10), 0, 0);
            // a time already past today means tomorrow, which is what a human means by it
            if (at.getTime() <= now.getTime())
                at.setDate(at.getDate() + 1);
            return Math.min(at.getTime() - now.getTime(), NotifyConfig.snooze.maxMs);
        }
        return null;
    }

    // Text an action produced, waiting to be loaded into the reply field. draftToken ticks on
    // every new draft so the field reloads even when two drafts happen to be identical.
    property string draftText: ""
    property int draftToken: 0

    function beginPrompt(entry, action, timeMode) {
        if (!entry)
            return;
        entry.promptTimeMode = timeMode === true;
        entry.promptAction = action || null;
        entry.prompting = true;
        // A card you are typing into must not expire underneath you. This reuses the hover
        // pause rather than inventing a second freeze, so there is still one clock.
        root.pause(entry);
    }

    function cancelPrompt(entry) {
        if (!entry)
            return;
        entry.prompting = false;
        entry.promptAction = null;
        root.resume(entry);
    }

    function submitPrompt(entry, text) {
        if (!entry)
            return;
        const action = entry.promptAction;
        const timeMode = entry.promptTimeMode;
        entry.prompting = false;
        entry.promptAction = null;
        entry.promptTimeMode = false;

        if (timeMode) {
            const ms = root.parseDelay(text);
            if (ms === null) {
                // reject rather than guess: silently snoozing for the wrong interval is worse
                // than saying the input was not understood
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "quickshell",
                        "Snooze", "could not parse \"" + text + "\" — try 20m, 2h or 17:30"]);
                root.resume(entry);
                return;
            }
            root.snooze(entry, ms);
            return;
        }
        if (action) {
            // a custom action with a prompt: {input} carries the typed text
            root.invokeAction(entry, action, text);
            return;
        }
        // A stored row has no client to answer. Nothing above this line needed one — a custom
        // action runs here — but an inline reply does, so say so instead of dropping the text on
        // the floor. The compose surface already refuses to offer the field in this case; this
        // catches the path that reaches here anyway (a `capture = "reply"` action on a row).
        if (entry.isRow) {
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "quickshell",
                    "Reply not sent", "no live client for this notification — it is history"]);
            return;
        }
        // the client's own inline reply
        if (entry.notification && entry.hasInlineReply) {
            try {
                entry.notification.sendInlineReply(text);
            } catch (e) {
                console.warn("notifications: inline reply failed —", e);
            }
        } else if (text.length) {
            // The field can also be opened on an ALLOWLISTED CATEGORY (NotifyConfig.prompt), and
            // a client in one of those categories need not support inline reply — notify-send
            // certainly does not. That is the client's limit rather than a bug here, but text
            // typed into a field and then dropped in silence is indistinguishable from a bug, so
            // it is reported by the same route a failing action is.
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "quickshell",
                    "Reply not sent", (entry.appName.length ? entry.appName : "this client") + " offers no reply channel — use an action with a prompt"]);
        }
        root.resume(entry);
        if (!entry.resident)
            root.dismiss(entry);
    }

    function dismiss(entry) {
        if (!entry)
            return;
        entry.expiryTimer.stop();
        entry.collapseTimer.stop();
        // a hand-dismissed card is gone, not dwelling: no flight, and it never reaches the bell
        entry.leaveTimer.stop();
        entry.leaving = false;
        NotifyStore.close(entry.nid, "dismissed");
        if (entry.notification)
            entry.notification.dismiss(); // → NotificationClosed(reason=Dismissed)
        forget(entry);
    }

    // Timeout. With the dwell motion configured the card does not vanish: it flies into the bar
    // bell first, and only then is the notification closed.
    //
    // The D-Bus close fires at the END of the flight, not the start, because
    // `notification.expire()` emits NotificationClosed, which drops the entry from the model and
    // takes the card with it — the flight has to outlive the object it is animating. dwellMs is
    // an animation duration (~half a second), so no client is kept waiting in any real sense.
    function expire(entry) {
        if (!entry || entry.leaving)
            return;
        entry.expiryTimer.stop();
        entry.collapseTimer.stop();

        // The dwell needs a bell to fly into. With no bar on screen (or exit configured to
        // something else) the card takes the plain exit instead of flying at a target that
        // isn't there.
        const onScreen = !entry.queued && !entry.drawerOnly;
        const toBell = motion.exit === "dwell" && bellAvailable && onScreen;
        const ms = !onScreen || motion.exit === "none" ? 0 : (toBell ? motion.dwellMs : motion.exitMs);
        if (ms > 0) {
            entry.dwellsToBell = toBell;
            entry.leaving = true;
            entry.leaveTimer.interval = ms;
            entry.leaveTimer.start();
            return;
        }
        finishExpire(entry);
    }

    function finishExpire(entry) {
        if (!entry)
            return;
        const landed = entry.leaving && entry.dwellsToBell;
        const screenName = entry.screenName;
        entry.leaveTimer.stop();
        NotifyStore.close(entry.nid, "expired");
        if (entry.notification)
            entry.notification.expire(); // → NotificationClosed(reason=Expired)
        forget(entry);
        if (landed) {
            root.unread++;
            root.dwellLanded(screenName);
        }
    }

    function dismissAll() {
        for (const e of popups.slice())
            dismiss(e);
    }

    // Drop an entry from the model without touching the D-Bus side (used when the notification
    // is already gone: client called CloseNotification, or it was replaced).
    function forget(entry) {
        const list = popups.slice();
        const at = list.indexOf(entry);
        if (at < 0)
            return;
        list.splice(at, 1);
        popups = list;
        releaseEntry(entry);
    }

    function releaseEntry(entry) {
        if (!entry)
            return;
        entry.expiryTimer.stop();
        entry.leaveTimer.stop();
        entry.collapseTimer.stop();
        entry.destroy();
    }

    // ---------------------------------------------------------------------------------------

    Component {
        id: entryComponent

        // One live notification, as data. Every field below is a BINDING onto the underlying
        // Notification — a replaces_id update mutates that object without re-signalling, so a
        // copied value would leave the card showing the notification's first revision forever.
        QtObject {
            id: entry

            property var notification: null

            readonly property var hints: entry.notification ? entry.notification.hints : ({})
            readonly property int nid: entry.notification ? entry.notification.id : 0
            readonly property string appName: entry.notification ? entry.notification.appName : ""
            readonly property string appIcon: entry.notification ? entry.notification.appIcon : ""
            readonly property string summary: entry.notification ? entry.notification.summary : ""
            readonly property string body: entry.notification ? entry.notification.body : ""
            readonly property int urgency: entry.notification ? entry.notification.urgency : NotificationUrgency.Normal
            readonly property string image: entry.notification ? entry.notification.image : ""
            // `transient` is a reserved QML keyword, hence the rename; this is the spec hint
            readonly property bool isTransient: entry.notification ? entry.notification.transient : false
            // survives action invocation → a click on the card doesn't close it
            readonly property bool resident: entry.notification ? entry.notification.resident : false
            // hints without a dedicated property on the quickshell type
            readonly property string category: entry.hints["category"] !== undefined ? String(entry.hints["category"]) : ""
            readonly property real value: entry.hints["value"] !== undefined ? Number(entry.hints["value"]) : -1
            readonly property bool hasProgress: entry.value >= 0

            property var timestamp: new Date()
            property int durationMs: 0
            // per-notification placement, so a rule can pin one source elsewhere later
            property string anchorH: "right"
            property string anchorV: "center"
            property string screenName: "" // "" = follow the focused monitor

            // the rules engine has answered for this entry (or failed open): until then it is
            // in the model but on no screen — see refresh()
            property bool resolved: false
            // AD-012: a Lua rule may set presentation.actions = false to suppress this
            // notification's actions. Defaults true; only an explicit false flips it.
            property bool actionsAllowed: true
            // the client asked for a reply field (x-kde-reply / inline-reply hint)
            readonly property bool hasInlineReply: entry.notification ? entry.notification.hasInlineReply : false
            // an inline prompt is open on this card, and which action opened it (null = the
            // client's own inline reply rather than a custom action)
            // a capturing action is running and this card is waiting for its output
            property bool awaitingCapture: false
            property bool prompting: false
            property var promptAction: null
            // "remind me at ___": the field parses a delay instead of sending a reply
            property bool promptTimeMode: false
            // recorded but never popped (durationMs < 0) — see the duration vocabulary above
            readonly property bool drawerOnly: entry.durationMs < 0
            // already added to `unread`; drawer-only entries are counted on arrival, once
            property bool counted: false
            // a history row exists for this entry, so further refreshes update it in place
            property bool stored: false
            // DND was active when this notification was last refreshed (story: notif-dnd-core);
            // dndCounted guards the exit digest against counting the same entry twice across
            // more than one refresh()
            property bool dndBaseline: false
            property bool dndCounted: false

            // countdown bookkeeping: how long this showing was granted, how much of it is left,
            // and when the current run started. runToken ticks whenever the clock is (re)armed,
            // which is the card's cue to restart its remaining-time indicator.
            property int spanMs: 0
            property int remainingMs: 0
            property real startedAt: 0
            property int runToken: 0
            property bool paused: false
            // sticky and folded down to an icon pill (see scheduleCollapse)
            property bool collapsed: false

            // beyond placement.maxVisible for its stack: in the model, not on screen (see reflow)
            property bool queued: false
            // timed out and currently playing its exit; the D-Bus close waits for the animation
            property bool leaving: false
            // ...and that exit is the dwell flight into the bar bell, rather than a plain fade
            property bool dwellsToBell: false

            property Timer expiryTimer: Timer {
                repeat: false
                onTriggered: root.expire(entry)
            }

            property Timer leaveTimer: Timer {
                repeat: false
                onTriggered: root.finishExpire(entry)
            }

            property Timer collapseTimer: Timer {
                repeat: false
                onTriggered: entry.collapsed = true
            }

            property Connections notificationConn: Connections {
                target: entry.notification

                // The client closed it, or the server dropped it: the object is going away, so
                // the model must let go. Bound to this specific notification, so a stale object
                // left over from a replaces_id swap can't evict the card that replaced it.
                function onClosed(reason) {
                    // no-op in the store if dismiss()/finishExpire() already closed the row:
                    // every close statement is scoped to state = 'active'
                    NotifyStore.close(entry.nid, "closed");
                    root.forget(entry);
                }

                // An in-place update is a fresh notification as far as the spec is concerned:
                // re-run duration, rules and the dwell timer.
                function onSummaryChanged() {
                    root.refresh(entry);
                }
                function onBodyChanged() {
                    root.refresh(entry);
                }
                function onUrgencyChanged() {
                    root.refresh(entry);
                }
                function onExpireTimeoutChanged() {
                    root.refresh(entry);
                }
                function onHintsChanged() {
                    root.refresh(entry);
                }
            }
        }
    }

    Loader {
        id: serverLoader
        active: Shell.notificationsEnabled

        sourceComponent: NotificationServer {
            // Notifications are re-emitted after a config reload, so a `qs` reload doesn't
            // silently swallow whatever was on screen.
            keepOnReload: true

            // Advertise ONLY what is implemented. Action icons, inline reply and markup
            // bodies each still have their own story; claiming them here would make clients
            // send us content we render as literal garbage.
            //
            // `actions` flips true with the actions story (AD-012): spec actions render as
            // buttons on the card with key hints, the `default` action is what clicking the
            // card means, and an invocation that fails raises a critical notification rather
            // than doing nothing. Clients DO change what they send based on this — that is
            // the point, and it is also why it stayed false until the rendering existed.
            bodySupported: true
            bodyMarkupSupported: false
            bodyHyperlinksSupported: false
            bodyImagesSupported: false
            actionsSupported: true
            actionIconsSupported: false
            inlineReplySupported: true
            imageSupported: true
            // flipped on by the SQLite store story — until then nothing survives a restart
            persistenceSupported: false

            onNotification: notification => root.present(notification)
        }
    }
}
