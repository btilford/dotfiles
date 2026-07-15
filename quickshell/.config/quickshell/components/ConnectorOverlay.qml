import QtQuick
import Quickshell
import Quickshell.Wayland
import "../config"

// Energy connector lines between shell components: one fullscreen transparent window
// per screen, mapped only while that screen has live links in the Connectors registry
// (and effects are on — the lines are pure flourish, no static fallback). The window is
// input-invisible: empty mask = full click/hover passthrough, no keyboard focus, no
// exclusion zone. Top layer, not Overlay — it must never stack above the Launcher or
// other Overlay-layer dialogs.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property var myLinks: Connectors.links.filter(l => l.screenName === modelData.name)

            visible: Shell.effectsOn && myLinks.length > 0
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-connectors"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // empty input region → everything passes through to the surfaces below
            mask: Region {}

            Repeater {
                model: win.myLinks

                // rotated quad: x-axis along the line, glow pad across it
                delegate: Item {
                    id: quad
                    required property var modelData
                    readonly property real ldx: modelData.x2 - modelData.x1
                    readonly property real ldy: modelData.y2 - modelData.y1

                    x: modelData.x1
                    y: modelData.y1 - height / 2
                    width: Math.max(Math.hypot(ldx, ldy), 1)
                    height: Theme.borderThickness + 24
                    rotation: Math.atan2(ldy, ldx) * 180 / Math.PI
                    transformOrigin: Item.Left

                    ShaderEffect {
                        anchors.fill: parent
                        blending: true

                        property real u_energy: quad.modelData.energy
                        property real u_thickness: Theme.borderThickness
                        property real u_lineLength: width
                        property real u_lineHeight: height
                        property real u_time: 0
                        property color u_color: Theme.energy

                        NumberAnimation on u_time {
                            running: win.visible
                            loops: Animation.Infinite
                            from: 0
                            to: 62.831853
                            duration: 40000
                        }

                        fragmentShader: Qt.resolvedUrl("energyline.frag.qsb")
                    }
                }
            }
        }
    }
}
