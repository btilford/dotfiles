import QtQuick
import ".."
import "../../config"

// One card's slot in a stack. The card itself (NotificationCard) is a pure view of the entry;
// this wrapper owns nothing but MOTION — entrance, exit, and the signature dwell where a timed-out
// card flies up into the bar's bell widget instead of blinking out.
//
// The slot stays in the Column and collapses its height while the card leaves, so the cards below
// close the gap with the positioner's move transition while the leaving card is still visible
// outside the slot's (now zero) bounds.
//
// The card's x/y/scale/opacity are driven by two explicit animations rather than by state bindings
// with Behaviors on them. That is deliberate: a Behavior reads its duration and easing when the
// animation starts, and if those come from bindings on the same flag that triggered it, QML gives
// no guarantee about which is re-evaluated first. That bug shipped here once — position animated
// over the dwell duration while opacity and scale used the (much shorter) entrance one, so the card
// was invisible a quarter of the way into a flight that was otherwise working perfectly. An
// explicit animation reads `to` and `duration` at start(), after beginFlight() has set them.
Item {
    id: slot

    required property var entry
    // stack geometry, so the entrance can slide in from the edge the stack is anchored to
    property string anchorH: "right"
    property string anchorV: "center"
    // bell position in WINDOW coordinates (== screen coordinates: the stack window covers the
    // whole output, see NotificationOverlay), or null when this monitor has no bar bell.
    property var bell: null
    // full-window item the card is reparented into for its exit (see beginFlight)
    property var flightLayer: null

    readonly property var motion: Notifications.motion
    readonly property bool toBell: slot.entry.dwellsToBell && slot.bell !== null

    // exit parameters, all assigned by beginFlight() before the animation is started
    property bool flying: false
    property int travelMs: slot.motion.exitMs
    property real flyX: 0
    property real flyY: 0

    readonly property real slideDistance: 48

    // A collapsed (shrunk-to-icon) card is a narrow pill rather than a full-width card, so it
    // keeps its place in the stack without covering the screen. It hugs whichever edge the stack
    // is anchored to — the resting x below, which the entrance animates to and `settle` moves to
    // when the card folds or unfolds.
    readonly property real collapsedWidth: 200
    readonly property real cardWidth: slot.entry.collapsed ? Math.min(slot.width, slot.collapsedWidth) : slot.width
    readonly property real restX: {
        if (slot.anchorH === "right")
            return slot.width - slot.cardWidth;
        if (slot.anchorH === "center")
            return (slot.width - slot.cardWidth) / 2;
        return 0;
    }

    implicitHeight: slot.flying ? 0 : card.implicitHeight

    Behavior on implicitHeight {
        NumberAnimation {
            duration: slot.motion.reflowMs
            easing.type: Theme.easing
        }
    }

    // Entrance offset: slide in from whichever screen edge this stack hugs. A centered stack has
    // no edge to come from, so it scales up instead of sliding.
    function entranceX() {
        if (slot.motion.entrance !== "slide")
            return 0;
        if (slot.anchorH === "right")
            return slot.slideDistance;
        if (slot.anchorH === "left")
            return -slot.slideDistance;
        return 0;
    }
    function entranceY() {
        if (slot.motion.entrance !== "slide" || slot.anchorH !== "center")
            return 0;
        return slot.anchorV === "top" ? -slot.slideDistance : slot.slideDistance;
    }

    // The flight is measured when it starts, from where the card actually is. The flight layer
    // fills the stack window, which covers the whole output, so its coordinates are screen
    // coordinates — the same space the bar publishes its bell anchor in, with no geometry
    // bookkeeping here.
    function beginFlight() {
        if (slot.flying)
            return;

        // Hand the card to the window-wide flight layer, at the same place on screen. The slot
        // collapses to nothing so the cards below can close the gap, and a card animating out of
        // a zero-height parent inside a positioner does not get presented — it keeps animating,
        // reports the right geometry, and never appears on screen. Flying in a full-window layer
        // also means the card can cross the bar, which is the whole point of the dwell.
        const here = card.mapToItem(slot.flightLayer, 0, 0);
        card.parent = slot.flightLayer;
        card.x = here.x;
        card.y = here.y;

        if (slot.toBell) {
            slot.travelMs = slot.motion.dwellMs;
            // land centered on the bell
            slot.flyX = slot.bell.x - card.width / 2;
            slot.flyY = slot.bell.y - card.height / 2;
        } else {
            // no bell to fly into: back out the way it came in (or just fade, for exit "fade")
            slot.travelMs = slot.motion.exitMs;
            slot.flyX = here.x + (slot.motion.exit === "slide" ? slot.entranceX() : 0);
            slot.flyY = here.y + (slot.motion.exit === "slide" ? slot.entranceY() : 0);
        }
        slot.flying = true;
        entrance.stop();
        flight.start();
    }

    Connections {
        target: slot.entry
        function onLeavingChanged() {
            if (slot.entry.leaving)
                slot.beginFlight();
        }
    }

    onRestXChanged: {
        if (!slot.flying && !entrance.running)
            settle.restart();
    }

    Component.onCompleted: {
        if (slot.motion.entrance === "none") {
            card.x = slot.restX;
            card.y = 0;
            card.scale = 1;
            card.opacity = 1;
        } else {
            card.x = slot.restX + slot.entranceX();
            card.y = slot.entranceY();
            card.scale = slot.motion.entrance === "fade" ? 1 : 0.94;
            card.opacity = 0;
            entrance.start();
        }
        // an entry that is already leaving when its card is built (a config reload mid-flight
        // rebuilds the view) goes straight to the exit
        if (slot.entry.leaving)
            beginFlight();
    }

    ParallelAnimation {
        id: entrance

        NumberAnimation {
            target: card
            property: "x"
            to: slot.restX
            duration: slot.motion.entranceMs
            easing.type: Easing.OutBack
        }
        NumberAnimation {
            target: card
            property: "y"
            to: 0
            duration: slot.motion.entranceMs
            easing.type: Easing.OutBack
        }
        NumberAnimation {
            target: card
            property: "scale"
            to: 1
            duration: slot.motion.entranceMs
            easing.type: Easing.OutBack
        }
        NumberAnimation {
            target: card
            property: "opacity"
            to: 1
            duration: Math.min(slot.motion.entranceMs, Theme.animMed)
            easing.type: Theme.easing
        }
    }

    ParallelAnimation {
        id: flight

        NumberAnimation {
            target: card
            property: "x"
            to: slot.flyX
            duration: slot.travelMs
            // accelerating away, so the card reads as being pulled into the bell
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: card
            property: "y"
            to: slot.flyY
            duration: slot.travelMs
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: card
            property: "scale"
            // shrinking to a bar-icon-sized speck is what sells "it went INTO the bell"
            to: slot.toBell ? 0.12 : 0.92
            duration: slot.travelMs
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: card
            property: "opacity"
            to: 0
            duration: slot.travelMs
            // back-loaded fade: a card that fades linearly is invisible a third of the way into
            // its flight, so the motion never reads as going anywhere
            easing.type: Easing.InQuart
        }
    }

    // fold/unfold: the pill slides to the anchored edge as it narrows, so the collapse reads as
    // the card retreating rather than as a card of a different size appearing in its place
    NumberAnimation {
        id: settle

        target: card
        property: "x"
        to: slot.restX
        duration: Theme.animMed
        easing.type: Theme.easing
    }

    // Depth instead of a stroke. The shadow follows the card through every animation because it
    // is anchored to it, including the dwell flight — and it tints to the accent while the card
    // is the keyboard's selection, which is what replaced the thicker border.
    Elevation {
        target: card
        tint: card.selected ? Theme.accent : "#000000"
        level: card.selected ? 1.3 : 1.0
        opacity: card.opacity
    }

    NotificationCard {
        id: card

        entry: slot.entry
        width: slot.cardWidth

        Behavior on width {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Theme.easing
            }
        }

        transformOrigin: Item.Center
        opacity: 0 // set by Component.onCompleted, then owned by the animations above
    }
}
