pragma Singleton

import QtQuick
import Quickshell

// One notification, pulled out into a centred surface with room to write (story: notif-actions).
//
// WHY THIS IS NOT A NEW WINDOW. AD-012 §5 rejected a dedicated centred overlay on the grounds
// that it adds a third focus-grabbing surface: the popup stack and the drawer already fight over
// one keyboard grab, and a third would be a third thing that can be left holding it. So compose
// is a STATE, not a surface — `components/notifications/ComposeSurface.qml` is instantiated
// inside whichever window already has the grab:
//
//   host = "stack"   → the popup stack window's flightHost layer (the full-window layer the
//                      dwell animation already reparents into). Same window, same grab.
//   host = "drawer"  → the drawer window, over its panel. Same window, same grab.
//
// Nothing here knows about pixels. It holds what is being composed, what may be done with it, and
// the one honest answer to "can this actually be replied to" (see `canReply` below).
Singleton {
    id: root

    // "" = closed. Also names which window renders it, so the other one does not.
    property string host: ""
    readonly property bool active: root.host !== ""

    // The live entry, when there is one. A drawer row that is still on screen re-associates to
    // its entry here; a row whose client has exited leaves this null and that is the whole
    // subject of `canReply`.
    property var live: null
    // The stored row, when composing from history.
    property var row: null

    // What the matcher and the argv substituter see. Captured at open() rather than bound: a
    // binding would build a NEW adapted object on every evaluation, and the draft router below
    // compares by identity.
    property var target: null

    // The action whose prompt is being filled. null = the client's own inline reply.
    property var pendingAction: null

    property string text: ""
    // ticks when an agent draft is loaded, so the field reloads even when two drafts are
    // identical — the same reason Notifications.draftToken exists
    property int loadToken: 0

    // ---------------------------------------------------------------------------------------
    // What the surface shows
    // ---------------------------------------------------------------------------------------

    readonly property string appName: root.live ? root.live.appName : (root.row ? (root.row.app_name || "") : "")
    readonly property string summary: root.live ? root.live.summary : (root.row ? (root.row.summary || "") : "")
    readonly property string body: root.live ? root.live.body : (root.row ? (root.row.body || "") : "")
    readonly property string appIcon: root.live ? root.live.appIcon : (root.row ? (root.row.app_icon || "") : "")
    readonly property string image: root.live ? root.live.image : ""

    // composing a row that has no live notification behind it any more
    readonly property bool fromHistory: root.row !== null && root.live === null

    // Touch NotifyConfig.actions so QML tracks it: dependencies are NOT discovered through a
    // function call into another singleton, and TOML config loads asynchronously (tomlq is a
    // subprocess), so without this the list is evaluated once against an empty config and the
    // chips never appear — with nothing in the log to say why.
    readonly property var actions: {
        NotifyConfig.actions;
        // Same reason, for the built-in snooze chips' defaultMs/presets labels.
        NotifyConfig.snooze;
        if (root.live)
            return Notifications.actionsFor(root.live);
        if (root.row)
            return Notifications.actionsForRow(root.row);
        return [];
    }

    // ---------------------------------------------------------------------------------------
    // Whether the field can send anything, and by which route. This is the question the drawer
    // could not answer honestly before compose existed.
    //
    // A reply reaches the CLIENT only through Notification.sendInlineReply(), which needs the
    // live object — and by the time a row is history, the process that offered "Reply" has
    // usually exited. So:
    //
    //   route "reply"    a live entry that qualifies for a prompt: the text goes over D-Bus.
    //   route "action"   a custom action declaring `prompt`: the text becomes {input} in an
    //                    argv the shell runs itself. This works on a row from last week,
    //                    because nothing about it needs the client to still exist.
    //   route "none"     neither. The field is NOT shown, and the surface says why — a reply
    //                    box that silently goes nowhere is worse than no reply box.
    // ---------------------------------------------------------------------------------------

    readonly property bool canReply: root.live !== null && Notifications.promptable(root.live)

    readonly property string route: {
        if (root.pendingAction)
            return "action";
        if (root.canReply)
            return "reply";
        return "none";
    }

    // Does any action offer a prompt? That is what makes "none" recoverable: the user picks a
    // verb and the field opens for it.
    readonly property bool hasPromptAction: {
        for (const a of root.actions)
            if (a.prompt)
                return true;
        return false;
    }

    readonly property string placeholder: {
        if (root.pendingAction && root.pendingAction.prompt && root.pendingAction.prompt.placeholder)
            return String(root.pendingAction.prompt.placeholder);
        return NotifyConfig.prompt.placeholder;
    }

    // Said in the surface, in place of the field, when there is nowhere for text to go.
    readonly property string note: {
        if (root.route !== "none")
            return "";
        if (root.fromHistory)
            return root.hasPromptAction
                ? "From history — the client is gone, so there is no reply channel. Pick a verb below to write into one."
                : "From history — the client is gone. Custom actions only; nothing here can send a reply.";
        return root.hasPromptAction
            ? "This notification offers no reply channel. Pick a verb below to write into one."
            : "This notification offers no reply channel — actions only.";
    }

    // ---------------------------------------------------------------------------------------
    // Open / close
    // ---------------------------------------------------------------------------------------

    function openEntry(entry, where) {
        if (!entry)
            return false;
        root.live = entry;
        root.row = null;
        root.target = entry;
        root.reset(where);
        // A card you are writing into must not expire underneath you. Force, because composing
        // is as deliberate as keyboard focus — it is not a hoverPause preference.
        Notifications.pause(entry, true);
        return true;
    }

    // Composing a stored row. A live entry is re-associated when one still exists for that nid,
    // which is what makes "reply from the drawer" work at all for a notification still on screen.
    function openRow(row, where) {
        if (!row)
            return false;
        const live = row.state === "active" ? Notifications.entryForId(row.nid) : null;
        if (live)
            return root.openEntry(live, where);
        root.live = null;
        root.row = row;
        root.target = Notifications.rowAsEntry(row);
        root.reset(where);
        return true;
    }

    // Opening compose from the stack with focus mode OFF makes that window take the keyboard, so
    // the toplevel that had it has to be put back afterwards — the same hand-back focus mode does,
    // for the same reason (layer-shell does not say where the keyboard goes when a grab is
    // released). Only when focus mode is not already holding it: then it owns the restore.
    property bool tookGrab: false

    function reset(where) {
        root.pendingAction = null;
        root.text = "";
        root.host = where === "drawer" ? "drawer" : "stack";
        if (root.host === "stack" && !NotifyFocus.active && !root.tookGrab) {
            root.tookGrab = true;
            NotifyFocus.rememberWindow();
        }
    }

    function close() {
        const live = root.live;
        root.host = "";
        if (root.tookGrab) {
            root.tookGrab = false;
            NotifyFocus.restoreWindow();
        }
        root.live = null;
        root.row = null;
        root.target = null;
        root.pendingAction = null;
        root.text = "";
        if (live)
            Notifications.resume(live);
    }

    // The composed notification went away underneath us (dismissed elsewhere, client closed it).
    // Holding a surface over a notification that no longer exists is worse than closing it.
    Connections {
        target: Notifications
        function onPopupsChanged() {
            if (!root.active || !root.live)
                return;
            if (Notifications.popups.indexOf(root.live) < 0)
                root.close();
        }
    }

    // ---------------------------------------------------------------------------------------
    // Acting
    // ---------------------------------------------------------------------------------------

    // A verb with a prompt opens the field for it instead of firing; everything else fires now.
    function invoke(action) {
        if (!action || !root.target)
            return;
        if (action.prompt) {
            root.pendingAction = action;
            return;
        }
        Notifications.invokeAction(root.target, action, "");
        // A capturing action is writing INTO this surface, so the surface has to survive it.
        if (!action.capture)
            root.close();
    }

    function invokeActionByKey(letter) {
        for (const a of root.actions) {
            if (a.key === letter) {
                root.invoke(a);
                return true;
            }
        }
        return false;
    }

    function submit() {
        const body = root.text;
        if (root.pendingAction) {
            const action = root.pendingAction;
            root.pendingAction = null;
            root.text = "";
            Notifications.invokeAction(root.target, action, body);
            if (!action.capture)
                root.close();
            return;
        }
        if (!root.canReply)
            return; // no route: the field is not shown, so this is unreachable by hand
        const live = root.live;
        root.text = "";
        root.close();
        Notifications.submitPrompt(live, body);
    }

    // An agent draft (`capture = "draft"`) lands here rather than in the card's own prompt box
    // when this surface owns the notification — routed from the action runner in Notifications.
    function owns(entry) {
        return root.active && entry !== null && entry === root.target;
    }

    function loadDraft(draft) {
        root.text = String(draft);
        root.loadToken++;
    }
}
