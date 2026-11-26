import QtQuick
import Quickshell
import "../config"

/*!
    Shimmer.qml — Subtle animated glimmer overlay for shell surfaces, lit by the cursor.

    The highlight leans toward the global pointer position (a light/reflection direction
    effect, not cursor tracking) via the Pointer singleton, plus a slow sweeping glimmer
    band. Place as the LAST child of a surface so the light sits over its content:

        Shimmer { anchors.fill: parent; radius: parent.radius }             // rounded rect
        Shimmer { anchors.fill: parent; slantLeft: sl; slantRight: sr }     // Section tab

    Strength default is intentionally faint; Hyprland windows get an even fainter static
    sheen from the screen shader (hypr/shaders/shimmer.frag).

    Qt6: rebuild after editing the .frag:
        qsb --qt6 -o components/shimmer.frag.qsb components/shimmer.frag
*/
Item {
    id: root

    //! Effect strength (~0.05 subtle … 0.15 obvious)
    property real strength: 0.08
    //! Corner radius for the rounded-rect mask
    property real radius: 0
    //! Section trapezoid slants (mask matches the tab shape when nonzero)
    property real slantLeft: 0
    property real slantRight: 0

    // Light position in item UV space, from the global cursor. QsWindow.itemPosition
    // gives this item's origin in window coords; bar windows and fullscreen overlays sit
    // at their monitor's origin, so window coords ≈ monitor coords. (Popout windows are
    // slightly off — acceptable, the light is directional ambience, not a tracker.)
    readonly property real _lx: {
        const w = QsWindow.window;
        if (!w)
            return 0.5; // not yet in a window — center the light
        const s = w.screen;
        const o = QsWindow.itemPosition(root);
        return ((Pointer.x - (s ? s.x : 0)) - o.x) / Math.max(root.width, 1);
    }
    readonly property real _ly: {
        const w = QsWindow.window;
        if (!w)
            return 0.5;
        const s = w.screen;
        const o = QsWindow.itemPosition(root);
        return ((Pointer.y - (s ? s.y : 0)) - o.y) / Math.max(root.height, 1);
    }

    // The light only follows the cursor while the effect is animating. Otherwise every 8Hz
    // pointer poll would change the uniform and redraw this surface on every monitor, which is
    // exactly the cost config/Motion.qml exists to remove. A still shimmer holds its light.
    property real _heldX: 0.5
    property real _heldY: 0.5
    property bool _animating: false
    Binding {
        target: root
        property: "_heldX"
        value: root._lx
        when: root._animating
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "_heldY"
        value: root._ly
        when: root._animating
        restoreMode: Binding.RestoreNone
    }

    // QS_EFFECTS=off → no glimmer at all; the effect is pure ambience with no static stand-in
    Loader {
        anchors.fill: parent
        active: Shell.effectsOn
        sourceComponent: ShaderEffect {
            blending: true

            property real u_time: clock.time
            property real u_width: width
            property real u_height: height
            property real u_radius: root.radius
            property real u_sl: root.slantLeft
            property real u_sr: root.slantRight
            // proximity (hybrid mode) brightens the glimmer as the pointer reaches the surface
            property real u_strength: root.strength * (1 + Motion.boostStrength * clock.boost)
            property real u_lightX: root._heldX
            property real u_lightY: root._heldY

            // smooth the 8Hz cursor poll into continuous light motion
            Behavior on u_lightX {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on u_lightY {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }

            // exactly one 2π period — the band phase is periodic, so the loop is seamless
            MotionClock {
                id: clock
                target: root
                enabled: root.visible
                duration: 24000
                onAnimatingChanged: root._animating = animating
                Component.onCompleted: root._animating = animating
            }

            fragmentShader: Qt.resolvedUrl("shimmer.frag.qsb")
        }
    }
}
