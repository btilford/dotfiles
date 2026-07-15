import QtQuick
import "../config"

// Renders a list of energy connector lines in the parent's coordinate space. Shared by
// ConnectorOverlay (screen-space overlay windows, fed from the Connectors registry) and
// ConnectorFan (in-window dialog fan-out — drawn inside the dialog so it sits ABOVE any
// dim scrim, which a separate lower-layer window can't).
//
// Link records: {x1, y1, x2, y2, energy} — straight line, or additionally {cx, cy} —
// quadratic bezier through that control point (edge-routed lines that arrive at a
// dialog border perpendicular).
Item {
    id: root

    //! [{x1,y1,x2,y2,energy, cx?,cy?}] in this item's coordinate space
    property var links: []
    //! stroke weight — dialogs draw heavier lines than the bar→popout stub
    property real thickness: Theme.connectorThickness

    Repeater {
        model: root.links

        delegate: Loader {
            id: link
            required property var modelData
            readonly property bool curved: modelData.cx !== undefined

            sourceComponent: curved ? curveQuad : lineQuad

            // straight: rotated quad, x-axis along the line
            Component {
                id: lineQuad
                Item {
                    readonly property real ldx: link.modelData.x2 - link.modelData.x1
                    readonly property real ldy: link.modelData.y2 - link.modelData.y1

                    x: link.modelData.x1
                    y: link.modelData.y1 - height / 2
                    width: Math.max(Math.hypot(ldx, ldy), 1)
                    height: root.thickness * 2 + 24
                    rotation: Math.atan2(ldy, ldx) * 180 / Math.PI
                    transformOrigin: Item.Left

                    ShaderEffect {
                        anchors.fill: parent
                        blending: true

                        property real u_energy: link.modelData.energy
                        property real u_thickness: root.thickness
                        property real u_lineLength: width
                        property real u_lineHeight: height
                        property real u_time: 0
                        property color u_color: Theme.energy

                        NumberAnimation on u_time {
                            running: root.visible
                            loops: Animation.Infinite
                            from: 0
                            to: 62.831853
                            duration: 40000
                        }

                        fragmentShader: Qt.resolvedUrl("energyline.frag.qsb")
                    }
                }
            }

            // curved: axis-aligned quad over the bezier's hull, curve points in local px
            Component {
                id: curveQuad
                Item {
                    readonly property real pad: root.thickness * 3 + 12
                    readonly property real bx: Math.min(link.modelData.x1, link.modelData.cx, link.modelData.x2) - pad
                    readonly property real by: Math.min(link.modelData.y1, link.modelData.cy, link.modelData.y2) - pad

                    x: bx
                    y: by
                    width: Math.max(link.modelData.x1, link.modelData.cx, link.modelData.x2) + pad - bx
                    height: Math.max(link.modelData.y1, link.modelData.cy, link.modelData.y2) + pad - by

                    ShaderEffect {
                        anchors.fill: parent
                        blending: true

                        property real u_energy: link.modelData.energy
                        property real u_thickness: root.thickness
                        property real u_width: width
                        property real u_height: height
                        property real u_time: 0
                        property vector2d u_p0: Qt.vector2d(link.modelData.x1 - parent.bx, link.modelData.y1 - parent.by)
                        property vector2d u_p1: Qt.vector2d(link.modelData.cx - parent.bx, link.modelData.cy - parent.by)
                        property vector2d u_p2: Qt.vector2d(link.modelData.x2 - parent.bx, link.modelData.y2 - parent.by)
                        property color u_color: Theme.energy

                        NumberAnimation on u_time {
                            running: root.visible
                            loops: Animation.Infinite
                            from: 0
                            to: 62.831853
                            duration: 40000
                        }

                        fragmentShader: Qt.resolvedUrl("energycurve.frag.qsb")
                    }
                }
            }
        }
    }
}
