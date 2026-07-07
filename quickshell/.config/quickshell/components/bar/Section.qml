import QtQuick
import QtQuick.Shapes
import "../../config"

// Slanted "inverted tab": \____/  with rounded corners. Fill is a closed trapezoid; the border
// is a SEPARATE open stroke tracing only the sides + bottom (no top edge — it sits at the screen
// edge on a top bar). slantLeft/slantRight toggle each side (left = ____/ , right = \____ ).
Item {
    id: root
    property alias spacing: inner.spacing
    property int barHeight: Theme.barHeightMinimal
    property bool slantLeft: true
    property bool slantRight: true
    property int slant: 12
    property int corner: 7
    default property alias content: inner.data

    readonly property int contentW: inner.implicitWidth + Theme.barPad * 2
    implicitHeight: barHeight
    implicitWidth: contentW + (slantLeft ? slant : 0) + (slantRight ? slant : 0)

    // geometry shared by the fill + stroke paths
    readonly property real sl: slantLeft ? slant : 0
    readonly property real sr: slantRight ? slant : 0
    readonly property real llen: Math.hypot(sl, height)
    readonly property real rlen: Math.hypot(sr, height)
    // top corner points (where the top edge meets the rounded corners)
    readonly property real trx: width - corner * sr / rlen
    readonly property real try_: corner * height / rlen
    readonly property real tlx: corner * sl / llen
    readonly property real tly: corner * height / llen

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.animFast
            easing.type: Theme.easing
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // fill (closed trapezoid, no stroke)
        ShapePath {
            fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.55)
            strokeWidth: 0
            startX: root.corner
            startY: 0
            PathLine {
                x: root.width - root.corner
                y: 0
            }
            PathQuad {
                controlX: root.width
                controlY: 0
                x: root.trx
                y: root.try_
            }
            PathLine {
                x: (root.width - root.sr) + root.corner * root.sr / root.rlen
                y: root.height - root.corner * root.height / root.rlen
            }
            PathQuad {
                controlX: root.width - root.sr
                controlY: root.height
                x: (root.width - root.sr) - root.corner
                y: root.height
            }
            PathLine {
                x: root.sl + root.corner
                y: root.height
            }
            PathQuad {
                controlX: root.sl
                controlY: root.height
                x: root.sl - root.corner * root.sl / root.llen
                y: root.height - root.corner * root.height / root.llen
            }
            PathLine {
                x: root.tlx
                y: root.tly
            }
            PathQuad {
                controlX: 0
                controlY: 0
                x: root.corner
                y: 0
            }
        }

        // border: OPEN stroke, sides + bottom only (starts at top-right corner point, ends at
        // top-left corner point) — no top edge.
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
            strokeWidth: 1
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            startX: root.trx
            startY: root.try_
            PathLine {
                x: (root.width - root.sr) + root.corner * root.sr / root.rlen
                y: root.height - root.corner * root.height / root.rlen
            }
            PathQuad {
                controlX: root.width - root.sr
                controlY: root.height
                x: (root.width - root.sr) - root.corner
                y: root.height
            }
            PathLine {
                x: root.sl + root.corner
                y: root.height
            }
            PathQuad {
                controlX: root.sl
                controlY: root.height
                x: root.sl - root.corner * root.sl / root.llen
                y: root.height - root.corner * root.height / root.llen
            }
            PathLine {
                x: root.tlx
                y: root.tly
            }
        }
    }

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: Theme.barPad
    }
}
