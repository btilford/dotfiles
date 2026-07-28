import QtQuick
import QtQuick.Effects
import "../config"

/*!
    Elevation.qml — drop shadow for a rounded shell surface.

    The energy border says "this thing is powered". A notification is not: it is a piece of
    paper that landed on the desktop, and it should read as lifted off the wallpaper rather
    than wired into it. Shadow instead of stroke, so the card carries no colour of its own and
    the urgency stripe stays the only chromatic cue.

    Renders `target` a second time, blurred and offset, BEHIND the real item — the duplicate is
    hidden under the original, which is why the target must be opaque enough to cover it. Place
    as a sibling immediately before the surface:

        Rectangle { id: card; radius: Theme.radius; color: … }
        Elevation { target: card }

    `tint` colours the shadow: the default black reads as depth, while an accent tint reads as
    a glow and is how the keyboard's selection is marked now that there is no border to thicken.
*/
MultiEffect {
    id: root

    //! The surface to cast a shadow for. Anchored to it automatically.
    required property Item target
    //! Shadow colour. Black = depth; an accent colour = glow (used for selection).
    property color tint: "#000000"
    //! 0 = flat on the surface, 1 = fully lifted. Scales blur, offset and opacity together so
    //! callers pick one number rather than four that can disagree.
    property real level: 1.0

    source: root.target
    anchors.fill: root.target
    z: root.target.z - 1

    shadowEnabled: true
    shadowColor: root.tint
    shadowBlur: 1.0
    blurMax: Math.round(24 * root.level)
    shadowOpacity: 0.55 * root.level
    shadowVerticalOffset: 5 * root.level
    shadowHorizontalOffset: 0

    Behavior on shadowOpacity {
        NumberAnimation {
            duration: Theme.animFast
        }
    }
    Behavior on shadowColor {
        ColorAnimation {
            duration: Theme.animFast
        }
    }
}
