import QtQuick
import QtQuick.Shapes
import ".."
import "../../config"

// Slanted "inverted tab": \____/ . The top edge is always square (it sits at the screen edge on
// a top bar) and an unslanted side is a square vertical edge flush to the screen edge; only the
// foot of a slanted side is rounded. The border is a separate energy stroke tracing the slanted
// sides + bottom (no top edge, no flush edges). slantLeft/slantRight toggle each side
// (left = ____/ , right = \____ ).
Item {
    id: root
    property alias spacing: inner.spacing
    property int barHeight: Theme.barHeightMinimal
    property bool slantLeft: true
    property bool slantRight: true
    property int slant: 12
    property int corner: 7
    default property alias content: inner.data

    //! Steady border energy (0..1). Ambient shimmer level; pulse() spikes above it.
    property real energy: 0.6
    //! Spike the border glow, then decay back to `energy`.
    function pulse() {
        glow.pulse();
    }

    readonly property int contentW: inner.implicitWidth + Theme.barPad * 2
    implicitHeight: barHeight
    implicitWidth: contentW + (slantLeft ? slant : 0) + (slantRight ? slant : 0)

    // geometry shared by the fill + stroke paths
    readonly property real sl: slantLeft ? slant : 0
    readonly property real sr: slantRight ? slant : 0
    readonly property real llen: Math.hypot(sl, height)
    readonly property real rlen: Math.hypot(sr, height)
    // effective corner radius per side: only the foot of a slanted side is rounded —
    // flush (unslanted) sides stay square so they sit tight against the screen edge
    readonly property real cl: slantLeft ? corner : 0
    readonly property real cr: slantRight ? corner : 0

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.animFast
            easing.type: Theme.easing
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // fill (closed trapezoid, no stroke). Square top corners; rounded feet only where
        // slanted (cl/cr are 0 on flush sides, degenerating those quads to the corner point).
        ShapePath {
            fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.55)
            strokeWidth: 0
            startX: 0
            startY: 0
            PathLine {
                x: root.width
                y: 0
            }
            PathLine {
                x: (root.width - root.sr) + root.cr * root.sr / root.rlen
                y: root.height - root.cr * root.height / root.rlen
            }
            PathQuad {
                controlX: root.width - root.sr
                controlY: root.height
                x: (root.width - root.sr) - root.cr
                y: root.height
            }
            PathLine {
                x: root.sl + root.cl
                y: root.height
            }
            PathQuad {
                controlX: root.sl
                controlY: root.height
                x: root.sl - root.cl * root.sl / root.llen
                y: root.height - root.cl * root.height / root.llen
            }
            PathLine {
                x: 0
                y: 0
            }
        }

    }

    // border: animated energy shader tracing the tab outline (sides + bottom, no top),
    // replacing the old solid accent stroke. Ambient shimmer at `energy`, spikes on pulse().
    EnergyBorder {
        id: glow
        anchors.fill: parent
        thickness: Theme.borderThickness
        slantLeft: root.sl
        slantRight: root.sr
        skipTop: true
        energy: root.energy
    }

    // QS_EFFECTS=off → static accent stroke tracing the same outline the shader draws
    // (sides + bottom, no top edge). EnergyBorder's internal fallback only covers rounded
    // rects; the trapezoid geometry lives here, mirroring the fill path above.
    Loader {
        anchors.fill: parent
        active: !Shell.effectsOn
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
                strokeWidth: Math.max(1, Theme.borderThickness * 0.5)
                startX: root.width
                startY: 0
                PathLine {
                    x: (root.width - root.sr) + root.cr * root.sr / root.rlen
                    y: root.height - root.cr * root.height / root.rlen
                }
                PathQuad {
                    controlX: root.width - root.sr
                    controlY: root.height
                    x: (root.width - root.sr) - root.cr
                    y: root.height
                }
                PathLine {
                    x: root.sl + root.cl
                    y: root.height
                }
                PathQuad {
                    controlX: root.sl
                    controlY: root.height
                    x: root.sl - root.cl * root.sl / root.llen
                    y: root.height - root.cl * root.height / root.llen
                }
                PathLine {
                    x: 0
                    y: 0
                }
            }
        }
    }

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: Theme.barPad
    }

    // cursor-lit glimmer over the tab surface
    Shimmer {
        anchors.fill: parent
        slantLeft: root.sl
        slantRight: root.sr
    }
}
