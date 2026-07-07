import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../config"

// Per-monitor focused window icon: the most-recently-focused window on THIS monitor
// (lowest focusHistoryID among this monitor's toplevels). Title-on-hover comes later.
Item {
    id: root
    property string screenName: ""
    implicitWidth: Theme.barIcon + 4
    implicitHeight: Theme.barIcon + 4

    readonly property int monId: {
        const ms = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (const m of ms)
            if (m.name === root.screenName)
                return m.id;
        return -1;
    }

    // last-focused toplevel on this monitor
    readonly property var win: {
        let best = null;
        let bestH = 1e9;
        const tls = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (const w of tls) {
            const o = w.lastIpcObject;
            if (!o || o.monitor !== root.monId)
                continue;
            const h = (o.focusHistoryID !== undefined) ? o.focusHistoryID : 999;
            if (h < bestH) {
                bestH = h;
                best = w;
            }
        }
        return best;
    }

    readonly property string appClass: (win && win.lastIpcObject) ? (win.lastIpcObject.class || "") : ""
    readonly property var entry: {
        DesktopEntries.applications; // reactive tap: re-run heuristicLookup once the entry index loads
        return root.appClass ? DesktopEntries.heuristicLookup(root.appClass) : null;
    }
    readonly property string iconName: entry && entry.icon ? entry.icon : ""

    Image {
        id: icon
        anchors.centerIn: parent
        visible: source != "" && root.appClass !== ""
        source: root.iconName ? Quickshell.iconPath(root.iconName, true) : ""
        sourceSize.width: Theme.barIcon
        sourceSize.height: Theme.barIcon
        width: Theme.barIcon
        height: Theme.barIcon
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Theme.easing
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !icon.visible && root.appClass !== ""
        text: "" // generic window glyph
        color: Theme.subtext
        font.family: Theme.fontUi
        font.pixelSize: Theme.barIcon
    }
}
