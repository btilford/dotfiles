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
    // Config seams. Placement/motion (story: notif-placement-motion) and timing (story:
    // notif-timing) become real config surfaces later; they are read from here NOW so nothing
    // downstream hardcodes a corner or a duration. Change the defaults here, not in the view.
    // ---------------------------------------------------------------------------------------

    // "left" | "center" | "right" x "top" | "center" | "bottom".
    // Default is deliberately NOT top-right: that corner covers application controls.
    readonly property QtObject placement: QtObject {
        readonly property string anchorH: "right"
        readonly property string anchorV: "center"
        readonly property string stack: "down"   // "down" = newest on top, "up" = newest at bottom
        readonly property int margin: 24         // gap to the screen edge
        readonly property int spacing: 12        // gap between cards
        readonly property int cardWidth: 420
        readonly property int maxVisible: 5      // extras wait in `popups` until a slot frees
    }

    // Durations in ms. 0 = sticky (never auto-expires).
    readonly property QtObject timing: QtObject {
        readonly property int low: 3000
        readonly property int normal: 6000
        readonly property int critical: 0
        readonly property bool respectAppTimeout: true
    }

    // ---------------------------------------------------------------------------------------
    // Live state
    // ---------------------------------------------------------------------------------------

    // Newest first. Entries are plain QtObjects (see entryComponent) — data, not views.
    property var popups: []
    readonly property int count: popups.length

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
            screenName: ""
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
        scheduleExpiry(entry);
    }

    function entryForId(nid) {
        for (var i = 0; i < popups.length; i++)
            if (popups[i].nid === nid)
                return popups[i];
        return null;
    }

    // ---------------------------------------------------------------------------------------
    // Expiry — every timeout in the shell routes through here (story: notif-timing extends it
    // with hover-pause, burst shortening and `0` = drawer-only).
    // ---------------------------------------------------------------------------------------

    function defaultDurationMs(entry) {
        // expireTimeout is in seconds: >0 explicit, 0 = never expire, <0 = server default.
        const t = entry.notification ? entry.notification.expireTimeout : -1;
        if (t === 0)
            return 0;
        if (timing.respectAppTimeout && t > 0)
            return Math.round(t * 1000);
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
        if (entry.notification)
            entry.notification.dismiss(); // → NotificationClosed(reason=Dismissed)
        forget(entry);
    }

    function expire(entry) {
        if (!entry)
            return;
        entry.expiryTimer.stop();
        if (entry.notification)
            entry.notification.expire(); // → NotificationClosed(reason=Expired)
        forget(entry);
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

            property Timer expiryTimer: Timer {
                repeat: false
                onTriggered: root.expire(entry)
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
