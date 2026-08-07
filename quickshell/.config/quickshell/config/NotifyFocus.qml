pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Keyboard control of the notification stacks (story: notif-keyboard-control).
//
// Popups NEVER take the keyboard on arrival — that would eat a keystroke out of whatever the user
// is typing, and the whole point of a notification is that it is ignorable. Focus is taken only
// when this singleton says so, which happens on one explicit path: `qs ipc call notifications
// focus` from a Hyprland bind. NotificationOverlay reads `active` + `selectedId` and nothing else;
// every key the overlay receives comes straight back here.
//
// State lives here rather than in Notifications because it is not notification data: it survives
// no restart, is written to no store, and a shell with no popup windows at all still has a
// well-defined answer for "is the notification layer focused" (no).
Singleton {
    id: root

    // focus mode is on: exactly one notification window holds an exclusive keyboard grab
    property bool active: false
    // the selected notification's D-Bus id, or -1. Not an index: the model reorders underneath
    // the selection (a card expires, a replaces_id lands) and an index would silently slide onto
    // a different notification.
    property int selectedId: -1

    // Nav order = the model order, newest first, minus the entries that were never on screen.
    // Queued (overflow) entries ARE navigable: reaching one scrolls it into view, which is what
    // makes the queue reachable without a mouse.
    readonly property var order: {
        const out = [];
        for (const e of Notifications.popups)
            // a pill docked in the bar is not on the stack, so the stack's keyboard cannot
            // select it — clicking it hands it back first
            if (!e.drawerOnly && e.resolved && !(e.collapsed && Notifications.dockCollapsed))
                out.push(e);
        return out;
    }

    readonly property var selected: {
        for (const e of root.order)
            if (e.nid === root.selectedId)
                return e;
        return null;
    }

    // the stack key of the selected card — the one window that may hold the keyboard
    readonly property string focusedKey: root.selected ? Notifications.stackKey(root.selected) : ""

    // ---------------------------------------------------------------------------------------
    // Enter / leave
    // ---------------------------------------------------------------------------------------

    function open() {
        if (root.active)
            return;
        if (root.order.length === 0)
            return; // nothing to focus: leave the keyboard where it is rather than grabbing it
        root.rememberWindow();
        root.selectedId = root.order[0].nid; // most recent
        root.active = true;
        Notifications.holdAll(); // every dwell freezes while the user is working the stack
        root.reveal();
    }

    function close() {
        if (!root.active)
            return;
        root.active = false;
        root.selectedId = -1;
        Notifications.clearScroll();
        Notifications.releaseAll();
        root.restoreWindow();
    }

    function toggle() {
        if (root.active)
            root.close();
        else
            root.open();
    }

    // An empty stack has nothing to select. Closing on the last card going away is what keeps the
    // keyboard from being held by an invisible layer surface.
    Connections {
        target: Notifications
        function onPopupsChanged() {
            if (!root.active)
                return;
            if (root.order.length === 0) {
                root.close();
                return;
            }
            if (!root.selected)
                root.selectedId = root.order[0].nid;
            root.reveal();
        }
    }

    // ---------------------------------------------------------------------------------------
    // Previously focused window.
    //
    // Layer-shell says nothing about where the keyboard goes when an exclusive surface releases
    // it, and Hyprland does not promise to hand it back to the toplevel that had it — so we put
    // it back by hand. The address is tracked from the event socket (activewindowv2 carries the
    // window address, no "0x" prefix) rather than polled, because by the time focus mode opens
    // the grab has already happened and `hyprctl activewindow` would answer about the layer.
    // ---------------------------------------------------------------------------------------

    property string lastWindow: ""   // live: whatever toplevel Hyprland last focused
    property string priorWindow: ""  // frozen at open(), restored at close()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2")
                root.lastWindow = event.data && event.data !== "," ? event.data : "";
        }
    }

    function rememberWindow() {
        root.priorWindow = root.lastWindow;
        if (!root.priorWindow)
            probe.running = true; // cold start: no focus change seen yet this session
    }

    // Two dispatch dialects, because Hyprland has two config languages and the dispatcher
    // string is evaluated by whichever one is loaded. On a Lua config (this repo's hypr/lua/)
    // the classic `focuswindow address:0x…` is parsed AS LUA and dies with
    // "')' expected near 'address'" — the restore silently never happens, which is exactly what
    // it did on the live desktop until this was caught. Neither form works on both, so the
    // first restore of a session tries one, reads the answer, and remembers which host this is.
    property string dialect: "lua" // "lua" | "plain"; corrected on first use if wrong

    function dispatchFor(style, address) {
        if (style === "lua")
            return ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:0x' + address + '" })'];
        return ["hyprctl", "dispatch", "focuswindow", "address:0x" + address];
    }

    function restoreWindow() {
        if (!root.priorWindow)
            return;
        const address = root.priorWindow;
        root.priorWindow = "";
        refocus.retried = false;
        refocus.address = address;
        refocus.command = root.dispatchFor(root.dialect, address);
        refocus.running = true;
    }

    // hyprctl answers "ok" on success and prints a parser error otherwise — while still exiting
    // 0, so the text is the only signal. A failure flips the dialect and retries once; after
    // that the window simply keeps focus where the compositor left it, which is a cosmetic loss,
    // never a stuck keyboard.
    Process {
        id: refocus
        property string address: ""
        property bool retried: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().startsWith("ok"))
                    return;
                if (refocus.retried) {
                    console.warn("notifications: could not restore focus to 0x" + refocus.address, "—", this.text.trim());
                    return;
                }
                refocus.retried = true;
                root.dialect = root.dialect === "lua" ? "plain" : "lua";
                refocus.command = root.dispatchFor(root.dialect, refocus.address);
                refocus.running = true;
            }
        }
    }

    // Only ever used for the cold-start case above: asking the compositor once, right after the
    // grab, still answers with the toplevel because layer surfaces are not toplevels.
    Process {
        id: probe
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(this.text);
                    if (w && w.address)
                        root.priorWindow = String(w.address).replace(/^0x/, "");
                } catch (e) {
                    // no active window (or hyprctl unavailable) — nothing to restore, and that
                    // is a perfectly normal state on an empty workspace
                }
            }
        }
    }

    // ---------------------------------------------------------------------------------------
    // Navigation
    // ---------------------------------------------------------------------------------------

    function indexOfSelected() {
        for (var i = 0; i < root.order.length; i++)
            if (root.order[i].nid === root.selectedId)
                return i;
        return -1;
    }

    function selectAt(i) {
        const n = root.order.length;
        if (n === 0)
            return;
        root.selectedId = root.order[Math.max(0, Math.min(n - 1, i))].nid;
        root.reveal();
    }

    function move(delta) {
        const at = root.indexOfSelected();
        root.selectAt(at < 0 ? 0 : at + delta);
    }
    function first() {
        root.selectAt(0);
    }
    function last() {
        root.selectAt(root.order.length - 1);
    }

    // Scroll the selection's own stack until the selected card is one of the visible ones. This
    // is what "navigate the overflow queue" means in a stack capped at maxVisible: the cap stays,
    // the window onto the queue moves.
    function reveal() {
        const entry = root.selected;
        if (!entry)
            return;
        const key = Notifications.stackKey(entry);
        var rank = 0;
        for (const e of Notifications.popups) {
            if (e.drawerOnly || !e.resolved || Notifications.stackKey(e) !== key)
                continue;
            if (e === entry)
                break;
            rank++;
        }
        const max = Math.max(1, Notifications.placement.maxVisible);
        var off = Notifications.scrollFor(key);
        if (rank < off)
            off = rank;
        else if (rank >= off + max)
            off = rank - max + 1;
        Notifications.setScroll(key, off);
    }

    // ---------------------------------------------------------------------------------------
    // Acting on the selection
    // ---------------------------------------------------------------------------------------

    // Dismiss keeps the position rather than the id: after removing a card the user is almost
    // always looking at the next one down, not back at the top of the stack.
    function dismissSelected() {
        const entry = root.selected;
        if (!entry)
            return;
        const at = root.indexOfSelected();
        Notifications.dismiss(entry);
        if (root.order.length === 0) {
            root.close();
            return;
        }
        root.selectAt(Math.min(at, root.order.length - 1));
    }

    function dismissAll() {
        Notifications.dismissAll();
        root.close();
    }

    // Enter unfolds: a shrunk-to-icon critical becomes a card again, and a card whose body was
    // too long to fit shows the rest. Once the actions story lands this is also where the
    // default action fires — the server does not advertise actions yet, so there is nothing
    // else Enter could do today that would not be a lie.
    signal expandRequested(int nid)

    function activateSelected() {
        const entry = root.selected;
        if (!entry)
            return;
        if (entry.collapsed) {
            Notifications.expand(entry);
            return;
        }
        // Enter fires the client's `default` action when there is one — activating a
        // notification is what that action means, and it is the same thing clicking the card
        // does. With no default action there is nothing to fire, so Enter falls back to
        // unfolding an elided body, which is what it did before actions existed.
        const def = Notifications.defaultActionFor(entry);
        if (def) {
            def.invoke();
            if (!entry.resident)
                Notifications.dismiss(entry);
            return;
        }
        root.expandRequested(entry.nid);
    }

    // Open the inline prompt on the selected card. `i` because this shell is vim-shaped
    // everywhere else and that is what "start typing" means; it is a no-op on a card that
    // does not qualify for a prompt (see Notifications.promptable).
    function promptSelected() {
        const entry = root.selected;
        if (!entry || !Notifications.promptable(entry))
            return false;
        Notifications.beginPrompt(entry, null);
        return true;
    }

    // `p` pulls the selected notification out into the centred compose surface — same window,
    // same grab (it renders in the stack window's flight layer), so focus mode stays on and the
    // selection is still this entry when it closes.
    function composeSelected() {
        const entry = root.selected;
        if (!entry)
            return false;
        return NotifyCompose.openEntry(entry, "stack");
    }

    // Number keys fire the selected card's actions by hint. Digits rather than letters because
    // focus mode is vim-shaped and owns j/k/d/y/s/o/g — see the hint assignment in
    // Notifications.actionsFor.
    function invokeActionByKey(digit) {
        const entry = root.selected;
        if (!entry)
            return false;
        const list = Notifications.actionsFor(entry);
        for (let i = 0; i < list.length; i++) {
            if (list[i].key === digit) {
                Notifications.invokeAction(entry, list[i], "");
                return true;
            }
        }
        return false;
    }

    // `c` copies summary + body, `C` the body alone — the summary is a label, and half the time
    // it is noise in whatever you are pasting into.
    function copySelected(bodyOnly) {
        Notifications.copy(root.selected, bodyOnly);
    }

    // Seams for the stories that own these verbs. They are bound in the key handler already so
    // the scheme does not change under the user when those stories land: snooze and "remind me
    // at ___" are notif-actions, the drawer is notif-drawer, dismiss-group is notif-grouping.
    property var snoozeHook: null   // function(entry, ms)
    property var drawerHook: null   // function()
    property var groupHook: null    // function(entry) — dismiss everything in the group

    // `s` snoozes for the configured default; `r` (ms = 0) is "remind me at ___", which opens
    // the prompt in TIME mode rather than guessing an interval.
    function snoozeSelected(ms) {
        const entry = root.selected;
        if (!entry)
            return;
        if (root.snoozeHook) {
            root.snoozeHook(entry, ms);
            return;
        }
        if (ms > 0) {
            Notifications.snooze(entry, ms);
            return;
        }
        Notifications.beginPrompt(entry, null, true);
    }

    function dismissGroup() {
        if (root.groupHook && root.selected) {
            root.groupHook(root.selected);
            return;
        }
        // no grouping yet: the honest fallback is everything from the same app, which is what
        // grouping will key on first anyway
        const entry = root.selected;
        if (!entry)
            return;
        for (const e of Notifications.popups.slice())
            if (e.appName === entry.appName)
                Notifications.dismiss(e);
        if (root.order.length === 0)
            root.close();
        else
            root.selectAt(0);
    }

    // The keyboard hands over rather than stacking surfaces: two exclusive layer surfaces on
    // one output fight over the grab, so focus mode releases before the drawer takes it.
    function openDrawer() {
        root.close();
        if (root.drawerHook) {
            root.drawerHook();
            return;
        }
        NotifyDrawer.open();
    }
}
