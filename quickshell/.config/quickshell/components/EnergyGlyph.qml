import QtQuick
import "../config"

/*!
    EnergyGlyph.qml — Lava-fill effect for icon glyphs, used as a `layer.effect`.

    Recolors the item's rendered texture (alpha-masked) with the slow bubbly lava pattern,
    so an "active" icon glows with moving lava instead of a flat accent color.

    Usage on any Text/icon:
        Text {
            ...
            layer.enabled: isActive           // plain color when inactive
            layer.effect: EnergyGlyph {}
        }

    Qt6: rebuild after editing the .frag:
        qsb --qt6 -o components/energyglyph.frag.qsb components/energyglyph.frag
*/
ShaderEffect {
    id: fx

    //! Lava color — defaults to Theme.accent
    property color color: Theme.accent
    //! Overall opacity of the effect
    property real alpha: 1.0

    // `source` is bound automatically by layer.effect
    property variant source

    property real u_time: 0
    property real u_width: width
    property real u_height: height
    property real u_alpha: fx.alpha
    property color u_color: fx.color

    NumberAnimation on u_time {
        running: fx.visible
        loops: Animation.Infinite
        from: 0
        to: 6.2831853
        duration: 45000
    }

    fragmentShader: Qt.resolvedUrl("energyglyph.frag.qsb")
}
