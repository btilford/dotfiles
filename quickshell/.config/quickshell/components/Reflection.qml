import QtQuick

/*!
    Reflection.qml — "floating above water" reflection of a source item.

    Captures the source live, draws it vertically flipped below with a rippling water
    distortion and a depth fade, as if the surface stood on a dark mirror of water.
    Place as a SIBLING anchored under the source (it sizes itself from the source):

        Reflection {
            sourceItem: box
            anchors.top: box.bottom
            anchors.horizontalCenter: box.horizontalCenter
        }

    The capture includes the source's children (energy border, shimmer), so the
    reflection ripples with them. The source's own scale/opacity transforms are not
    part of the capture — bind `opacity` to the source's if it animates.

    Qt6: rebuild after editing the .frag:
        qsb --qt6 -o components/reflection.frag.qsb components/reflection.frag

    Note: this is an Item wrapping the ShaderEffect, NOT a bare ShaderEffect — every
    property on a ShaderEffect becomes a shader uniform, and an Item-typed property
    gets implicitly wrapped as a texture source, which breaks the source's own render.
*/
Item {
    id: root

    //! The item to reflect
    property Item sourceItem
    //! Fraction of the source height shown in the reflection
    property real ratio: 0.35
    //! Reflection opacity right at the water line (fades to 0 with depth)
    property real strength: 0.5
    //! Ripple amplitude in uv units (water choppiness)
    property real amp: 0.006

    width: sourceItem ? sourceItem.width : 0
    height: sourceItem ? sourceItem.height * ratio : 0

    ShaderEffect {
        id: fx
        anchors.fill: parent
        blending: true

        property variant u_src: ShaderEffectSource {
            sourceItem: root.sourceItem
            live: true
            hideSource: false
        }
        property real u_time: 0
        property real u_ratio: root.ratio
        property real u_strength: root.strength
        property real u_amp: root.amp

        // exactly one 2π period — ripple phases are periodic, so the loop is seamless
        NumberAnimation on u_time {
            running: root.visible
            loops: Animation.Infinite
            from: 0
            to: 6.2831853
            duration: 9000
        }

        fragmentShader: Qt.resolvedUrl("reflection.frag.qsb")
    }
}
