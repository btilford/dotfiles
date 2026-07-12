pragma Singleton

import QtQuick
import Quickshell

// Dumb shown/open/close/toggle state for the ClipboardDialog, shared between the
// `clipboard` IPC handler and the dialog itself. Mirrors Session.qml.
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
}
