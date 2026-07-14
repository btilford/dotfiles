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

    // QS_EFFECTS=off → no glimmer at all; the effect is pure ambience with no static stand-in
    Loader {
        anchors.fill: parent
        active: Shell.effectsOn
        sourceComponent: ShaderEffect {
            blending: true

            property real u_time: 0
            property real u_width: width
            property real u_height: height
            property real u_radius: root.radius
            property real u_sl: root.slantLeft
            property real u_sr: root.slantRight
            property real u_strength: root.strength
            property real u_lightX: root._lx
            property real u_lightY: root._ly

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
            NumberAnimation on u_time {
                running: root.visible
                loops: Animation.Infinite
                from: 0
                to: 6.2831853
                duration: 24000
            }

            fragmentShader: Qt.resolvedUrl("shimmer.frag.qsb")
        }
    }
}
