pragma Singleton

import QtQuick
import Quickshell
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
            if (!popups[i].queued)
                n++;
        return n;
    }

    // Notifications that have timed out into the bell since it was last read. Dismissing a card
    // by hand does NOT count — that is the user saying they have dealt with it.
    property int unread: 0
    function markRead() {
        root.unread = 0;
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

    function applyRules(entry) {
        if (!rulesHook)
            return;
        const presentation = {
            durationMs: entry.durationMs,
            screenName: entry.screenName,
            anchorH: entry.anchorH,
            anchorV: entry.anchorV
        };
        try {
            rulesHook(presentation, snapshot(entry));
        } catch (e) {
            console.warn("notifications: rule hook threw, using defaults —", e);
            return;
        }
        if (typeof presentation.durationMs === "number" && presentation.durationMs >= 0)
            entry.durationMs = Math.round(presentation.durationMs);
        if (typeof presentation.screenName === "string")
            entry.screenName = presentation.screenName;
        if (["left", "center", "right"].indexOf(presentation.anchorH) >= 0)
            entry.anchorH = presentation.anchorH;
        if (["top", "center", "bottom"].indexOf(presentation.anchorV) >= 0)
            entry.anchorV = presentation.anchorV;
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
    function refresh(entry) {
        entry.durationMs = defaultDurationMs(entry);
        applyRules(entry);
        // a rule may have moved the entry to another anchor or monitor, so its stack — and with
        // it whether it is visible at all — is only settled after the hook has run
        reflow();
        scheduleExpiry(entry);
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

    function reflow() {
        const seen = {};
        for (var i = 0; i < popups.length; i++) {
            const entry = popups[i];
            const key = stackKey(entry);
            const rank = seen[key] === undefined ? 0 : seen[key];
            seen[key] = rank + 1;

            const queued = rank >= placement.maxVisible;
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

    // ---------------------------------------------------------------------------------------
    // Expiry — every timeout in the shell routes through here (story: notif-timing extends it
    // with hover-pause, burst shortening and `0` = drawer-only).
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

    function scheduleExpiry(entry) {
        entry.expiryTimer.stop();
        if (entry.durationMs <= 0)
            return; // sticky
        if (entry.queued)
            return; // off screen: the clock starts when a slot frees (see reflow)
        entry.expiryTimer.interval = entry.durationMs;
        entry.expiryTimer.start();
    }

    // ---------------------------------------------------------------------------------------
    // Removal. Three ways out: the client closes it (CloseNotification), it expires, or the
    // user dismisses it. The first is signalled TO us; the other two we signal outward so the
    // client gets its NotificationClosed with the right reason.
    // ---------------------------------------------------------------------------------------

    function dismiss(entry) {
        if (!entry)
            return;
        entry.expiryTimer.stop();
        // a hand-dismissed card is gone, not dwelling: no flight, and it never reaches the bell
        entry.leaveTimer.stop();
        entry.leaving = false;
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

        // The dwell needs a bell to fly into. With no bar on screen (or exit configured to
        // something else) the card takes the plain exit instead of flying at a target that
        // isn't there.
        const toBell = motion.exit === "dwell" && bellAvailable && !entry.queued;
        const ms = entry.queued || motion.exit === "none" ? 0 : (toBell ? motion.dwellMs : motion.exitMs);
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

            property Connections notificationConn: Connections {
                target: entry.notification

                // The client closed it, or the server dropped it: the object is going away, so
                // the model must let go. Bound to this specific notification, so a stale object
                // left over from a replaces_id swap can't evict the card that replaced it.
                function onClosed(reason) {
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

            // Advertise ONLY what is implemented. Actions, action icons, inline reply and
            // markup bodies each have their own story; claiming them here would make clients
            // send us content we render as literal garbage.
            bodySupported: true
            bodyMarkupSupported: false
            bodyHyperlinksSupported: false
            bodyImagesSupported: false
            actionsSupported: false
            actionIconsSupported: false
            inlineReplySupported: false
            imageSupported: true
            // flipped on by the SQLite store story — until then nothing survives a restart
            persistenceSupported: false

            onNotification: notification => root.present(notification)
        }
    }
}
