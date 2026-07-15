pragma Singleton

import QtQuick
import Quickshell

// Registry for energy connector lines drawn between shell components by
// ConnectorOverlay.qml (one transparent input-passthrough window per screen).
// Dumb by design: publishers (Popout, later Launcher/overlays) compute their own
// endpoints in screen-local logical coordinates and push {id, screenName,
// x1,y1, x2,y2, energy} records here; the overlay just renders whatever is live.
Singleton {
    id: root

    //! live links: [{id, screenName, x1, y1, x2, y2, energy}]
    property var links: []

    //! per-screen bar section feet for the dialog fan-out: { screenName: [{x,y} ×3] }
    //! (left section right-foot, center bottom-center, right section left-foot;
    //! published by Bar.qml whenever section geometry changes)
    property var sectionAnchors: ({})

    readonly property bool anyActive: links.length > 0

    function setSectionAnchors(screenName, pts) {
        const out = Object.assign({}, root.sectionAnchors);
        out[screenName] = pts;
        root.sectionAnchors = out;
    }

    function register(link) {
        const out = root.links.filter(l => l.id !== link.id);
        out.push(link);
        root.links = out;
    }

    function update(id, patch) {
        root.links = root.links.map(l => l.id === id ? Object.assign({}, l, patch) : l);
    }

    function unregister(id) {
        root.links = root.links.filter(l => l.id !== id);
    }
}
