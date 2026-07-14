import QtQuick
import "../config"

/*!
    EnergyFill.qml — Slow bubbly lava fill for active-item highlights (workspace pill, active-window
    indicator, submap badge). Drop-in replacement for a solid `color: Theme.accent` Rectangle: the
    highlight becomes rotating molten blobs in the accent color, translucent between blobs.

    Qt6: fragment is precompiled. Rebuild after editing the .frag:
        qsb --qt6 -o components/energyfill.frag.qsb components/energyfill.frag

    Usage:
        EnergyFill { anchors.fill: parent; radius: 6 }   // instead of Rectangle{ color: Theme.accent }
*/
Item {
    id: root

    //! Visual variant: "neon" (edge tube + glow + buzz) or "lava" (molten blobs, kept for later)
    property string effect: "neon"
    //! Base color — defaults to Theme.accent (#ff6600)
    property color color: Theme.accent
    //! Corner radius in px
    property real radius: 6
    //! Overall fill opacity (keep high for text contrast)
    property real alpha: 1.0

    // QS_EFFECTS=off → the shader pipeline is never instantiated; a flat themed
    // rectangle stands in so call sites stay drop-in.
    Loader {
        anchors.fill: parent
        active: Shell.effectsOn
        sourceComponent: ShaderEffect {
            blending: true

            property real u_time: 0
            property real u_width: width
            property real u_height: height
            property real u_radius: root.radius
            property real u_alpha: root.alpha
            property color u_color: root.color

            // exactly one 2π period so the loop is seamless. 9s/loop → the sin(2t) breath term
            // cycles every 4.5s, slow enough to read as breathing but clearly alive.
            NumberAnimation on u_time {
                running: root.visible
                loops: Animation.Infinite
                from: 0
                to: 6.2831853
                duration: 9000
            }

            fragmentShader: Qt.resolvedUrl(root.effect === "lava" ? "energyfill.frag.qsb" : "neonfill.frag.qsb")
        }
    }

    Loader {
        anchors.fill: parent
        active: !Shell.effectsOn
        sourceComponent: Rectangle {
            color: root.color
            radius: root.radius
            opacity: root.alpha
        }
    }
}
