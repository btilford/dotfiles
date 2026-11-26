import QtQuick
import Quickshell
import "../config"

/*!
    MotionClock.qml — Drives a shader's `u_time` under the Motion policy (config/Motion.qml).

    Replaces a free-running `NumberAnimation on u_time { loops: Animation.Infinite }`, which
    redrew the effect every frame for as long as it was visible. The clock advances only while
    Motion says this effect should animate, steps at Motion.capFps on capped (DisplayLink)
    screens, and in proximity/hybrid mode runs faster while the pointer is near (`boost`).

    Time is accumulated rather than restarted, so pausing and resuming never jumps the phase.

    Usage, inside the ShaderEffect:
        MotionClock { id: clock; target: root; enabled: root.visible; duration: 9000 }
        property real u_time: clock.time
*/
Item {
    id: clock

    //! The item whose on-screen rect counts for proximity (usually the effect's root).
    property Item target: parent
    //! Master switch, typically the effect's visibility.
    property bool enabled: true
    //! One loop of u_time; the shaders are periodic over this, so wrapping is seamless.
    property real period: 6.2831853
    //! Milliseconds per period at normal speed.
    property int duration: 9000

    property real time: 0

    width: 0
    height: 0
    visible: false

    readonly property string screenName: {
        const w = QsWindow.window;
        return w && w.screen ? w.screen.name : "";
    }

    readonly property bool near: {
        if (!Motion.usesProximity || !clock.target)
            return false;
        const w = QsWindow.window;
        if (!w || !w.screen)
            return false;
        const s = w.screen;
        const o = QsWindow.itemPosition(clock.target);
        const px = Pointer.x - s.x - o.x;
        const py = Pointer.y - s.y - o.y;
        const m = Motion.proximityPx;
        return px >= -m && py >= -m && px <= clock.target.width + m && py <= clock.target.height + m;
    }

    //! 0..1, eased toward 1 while the pointer is near (hybrid/proximity), else toward 0.
    property real boost: Motion.usesBoost && clock.near ? 1 : 0
    Behavior on boost {
        NumberAnimation {
            duration: 450
            easing.type: Easing.OutQuad
        }
    }

    // Keep ticking while a boost is still fading out, so leaving does not freeze mid-surge.
    readonly property bool animating: clock.enabled && (Motion.wants(clock.screenName, clock.near) || clock.boost > 0.01)
    readonly property bool capped: Motion.capped(clock.screenName)

    readonly property real _ratePerMs: clock.period / Math.max(clock.duration, 1) * (1 + Motion.boostSpeed * clock.boost)

    function _advance(ms: real): void {
        clock.time = (clock.time + clock._ratePerMs * ms) % clock.period;
    }

    // Uncapped: once per rendered frame, in step with the render loop.
    FrameAnimation {
        running: clock.animating && !clock.capped
        onTriggered: clock._advance(frameTime * 1000)
    }

    // Capped: a fixed low rate. Each tick changes the uniform once, so the window redraws at
    // capFps and DisplayLink compresses that many frames instead of the refresh rate.
    Timer {
        running: clock.animating && clock.capped
        repeat: true
        interval: Math.round(1000 / Math.max(Motion.capFps, 1))
        onTriggered: clock._advance(interval)
    }
}
