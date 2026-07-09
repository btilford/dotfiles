import QtQuick
import "../config"

/*!
    EnergyBorder.qml — Procedural plasma/electricity shader border for QuickShell surfaces.

    Renders an animated energy glow on all four edges of the parent item. Trigger a surge with
    pulse() (or drive `energy` directly); the glow rises then decays back to idle.

    Qt6 note: ShaderEffect.fragmentShader is a URL to a precompiled .qsb, NOT inline GLSL. The
    GLSL source lives in `energyborder.frag` and is baked to `energyborder.frag.qsb` via
    `qsb --qt6`. Rebuild after editing the .frag:
        qsb --qt6 -o components/energyborder.frag.qsb components/energyborder.frag

    Colors come from Theme.qml (warm palette: energy #ff6600, energyActive #ffaa00).

    Usage (event-driven pulse):
        EnergyBorder { id: glow; anchors.fill: parent; thickness: 2 }
        Connections {
            target: Hyprland
            function onRawEvent(e) { if (e.name === "activewindow") glow.pulse(); }
        }
    Usage (steady state, e.g. while a popout is open):
        EnergyBorder { anchors.fill: parent; energy: pop.shown ? 0.6 : 0.0 }
*/
Item {
    id: root

    //! Steady-state target energy (0..1). Decay pulls toward this; pulse() spikes above it.
    property real energy: 0.0
    //! Border thickness in pixels
    property real thickness: 2.0
    //! Left slant in px — matches Section.qml's slanted tab (0 = vertical edge)
    property real slantLeft: 0
    //! Right slant in px (0 = vertical edge)
    property real slantRight: 0
    //! Skip the top edge (for a trapezoid tab sitting at the screen edge)
    property bool skipTop: false
    //! Corner radius (px) for the rounded-rect path — used when slantLeft==slantRight==0
    property real radius: 0
    //! Base color — defaults to Theme.energy (#ff6600)
    property color energyColor: Theme.energy
    //! High-energy color when the smoothed level exceeds 0.8 — defaults to Theme.energyActive
    property color energyActiveColor: Theme.energyActive
    //! Per-frame exponential decay toward `energy` (lower = longer afterglow)
    property real decayRate: 0.02
    //! Per-frame rise speed toward a higher target
    property real activationRate: 0.15
    //! True while the border is drawing (shader hidden when idle to save GPU)
    readonly property bool isActive: root._activeEnergy > 0.005

    //! Spike the border to full then let it decay — call on discrete events.
    function pulse() {
        root._activeEnergy = 1.0;
    }

    // Smoothed energy the shader actually samples
    property real _activeEnergy: 0.0
    readonly property color _shaderColor: root._activeEnergy > 0.8 ? root.energyActiveColor : root.energyColor

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: root.isActive
        blending: true

        property real u_energy: root._activeEnergy
        property real u_thickness: root.thickness
        property real u_borderWidth: width
        property real u_borderHeight: height
        property real u_time: 0
        property real u_sl: root.slantLeft
        property real u_sr: root.slantRight
        property real u_skipTop: root.skipTop ? 1.0 : 0.0
        property real u_radius: root.radius
        property color u_color: root._shaderColor

        NumberAnimation on u_time {
            running: fx.visible
            loops: Animation.Infinite
            from: 0
            to: 62.831853
            duration: 40000
        }

        fragmentShader: Qt.resolvedUrl("energyborder.frag.qsb")
    }

    // 60fps driver: rise toward target, exponential decay back to idle
    Timer {
        running: true
        repeat: true
        interval: 16
        onTriggered: {
            var diff = root.energy - root._activeEnergy;
            if (Math.abs(diff) < 0.001) {
                root._activeEnergy = root.energy;
            } else if (diff > 0) {
                root._activeEnergy += diff * root.activationRate;
            } else {
                root._activeEnergy -= root.decayRate;
                if (root._activeEnergy < 0)
                    root._activeEnergy = 0;
            }
            root._activeEnergy = Math.max(0, Math.min(1, root._activeEnergy));
        }
    }
}
