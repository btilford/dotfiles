pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Keymap state for the KeymapOverlay. Loads all binds from `hyprctl binds -j` (which includes the
// per-bind `description` and `submap`), and tracks the active submap via Hyprland.rawEvent so the
// overlay can default to the current map. Shared with the Submap bar module + the `keymap` IPC.
Singleton {
    id: root

    property bool shown: false
    property string currentSubmap: ""
    // submap snapshotted when the overlay opens — opening an exclusive-keyboard layer surface can
    // reset the live submap, so the overlay filters on this frozen value, not currentSubmap.
    property string filterSubmap: ""
    property var binds: [] // parsed array from hyprctl binds -j

    function open() {
        filterSubmap = currentSubmap;
        load();
        shown = true;
    }
    function close() {
        shown = false;
    }
    function toggle() {
        if (shown)
            close();
        else
            open();
    }

    Process {
        id: proc
        command: ["sh", "-c", "hyprctl binds -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.binds = JSON.parse(this.text);
                } catch (e) {
                    root.binds = [];
                }
            }
        }
    }
    function load() {
        proc.running = false;
        proc.running = true;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                root.currentSubmap = event.data;
        }
    }

    // modmask bitfield → readable modifier string
    function modString(mask) {
        const parts = [];
        if (mask & 64)
            parts.push("SUPER");
        if (mask & 4)
            parts.push("CTRL");
        if (mask & 8)
            parts.push("ALT");
        if (mask & 1)
            parts.push("SHIFT");
        if (mask & 128)
            parts.push("MOD5");
        return parts;
    }
    // "SUPER + SHIFT + Q" style chord for a bind
    function chord(b) {
        const parts = modString(b.modmask);
        let key = b.key;
        if ((!key || key.length === 0) && b.keycode)
            key = "code:" + b.keycode;
        parts.push(key);
        return parts.join(" + ");
    }
    // what the bind does: description if present, else dispatcher + arg
    function action(b) {
        if (b.description && b.description.length)
            return b.description;
        return (b.dispatcher || "") + (b.arg ? " " + b.arg : "");
    }
}
