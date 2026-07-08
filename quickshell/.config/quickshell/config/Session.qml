pragma Singleton

import QtQuick
import Quickshell

// Session/power state + actions, shared between the left-bar Power button, the fullscreen
// SessionOverlay, and the `session` IPC handler (bound to SUPER+Escape). Commands mirror the
// previous wlogout layout so behavior is unchanged.
Singleton {
    id: root

    property bool shown: false
    function open() {
        shown = true;
    }
    function close() {
        shown = false;
    }
    function toggle() {
        shown = !shown;
    }

    // label, single-key accelerator, nerd-font glyph, shell command
    readonly property var actions: [
        {
            "label": "Lock",
            "key": "l",
            "icon": "\uf023",
            "cmd": "loginctl lock-session"
        },
        {
            "label": "Logout",
            "key": "e",
            "icon": "\uf08b",
            "cmd": "hyprctl dispatch 'hl.dsp.exit()'"
        },
        {
            "label": "Suspend",
            "key": "u",
            "icon": "\uf186",
            "cmd": "systemctl suspend"
        },
        {
            "label": "Hibernate",
            "key": "h",
            "icon": "\uf2dc",
            "cmd": "systemctl hibernate"
        },
        {
            "label": "Reboot",
            "key": "r",
            "icon": "\uf021",
            "cmd": "systemctl reboot"
        },
        {
            "label": "Shutdown",
            "key": "s",
            "icon": "\uf011",
            "cmd": "systemctl poweroff"
        }
    ]

    function run(cmd) {
        Quickshell.execDetached(["sh", "-lc", cmd]);
        shown = false;
    }
    function runKey(k) {
        for (const a of actions)
            if (a.key === k) {
                run(a.cmd);
                return true;
            }
        return false;
    }
}
