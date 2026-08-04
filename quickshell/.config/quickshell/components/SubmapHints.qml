import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// which-key style submap hints: entering a Hyprland submap pops a translucent slab at the
// bottom of the focused monitor listing that map's binds, so the pulsing bar badge is no
// longer the only feedback ("you are in a submap", but not what is in it).
//
// This surface is PASSIVE, and that is the whole design:
//   - `WlrKeyboardFocus.None` — Hyprland owns the keys while a submap is active. A layer
//     surface that grabs the keyboard makes the submap's own binds stop firing, and taking
//     an exclusive grab resets the live submap outright (see Keymap.filterSubmap, which
//     exists only because KeymapOverlay does take one).
//   - `mask: Region {}` — empty input region, the ConnectorOverlay pattern. Keyboard focus
//     is only half of "passive": a layer surface with a default input region swallows every
//     pointer event over its area, and this one lies across the bottom of the screen.
// Nothing in here is clickable, so there is nothing to carve out of the mask.
//
// Surface language: borderless paper (Elevation, no EnergyBorder) at the drawer's glass
// opacity. That reads as frosted only because Hyprland blurs this namespace — the layer rule
// for `quickshell-submap-hints` lives in hypr/lua/windowrules.lua and is not optional.
PanelWindow {
    id: win

    // the map being described; "" = default map, nothing to show
    readonly property string submap: Keymap.currentSubmap
    // delay elapsed — a submap you pass straight through never gets to flash
    property bool armed: false
    // what should be on screen right now
    readonly property bool wantShown: Shell.submapHintsEnabled && win.armed && win.entries.length > 0
    // window stays mapped through the fade-out, then unmaps
    property bool mapped: false

    color: "transparent"
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null
    visible: win.mapped

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-submap-hints"
    exclusionMode: ExclusionMode.Ignore
    // empty input region → everything passes through to the surfaces below
    mask: Region {}

    anchors {
        bottom: true
        left: true
        right: true
    }
    // the dev-mode bar sits at the BOTTOM; ExclusionMode.Ignore means nothing moves us off it
    margins.bottom: Theme.pad + (Shell.barVisible && Shell.barDevMode ? Theme.barHeightHub : 0)

    implicitHeight: slab.height + Theme.pad * 2

    // [{chord, label, group}] for the active submap. A bind that enters a NESTED submap is
    // rendered as a which-key "+prefix" group rather than by its dispatcher.
    readonly property var entries: {
        const out = [];
        if (!win.submap.length)
            return out;
        for (const bind of Keymap.binds) {
            if ((bind.submap || "") !== win.submap)
                continue;
            const nested = Keymap.submapEntry(bind);
            out.push({
                "chord": Keymap.chord(bind),
                "label": nested.length ? "+" + nested : Keymap.action(bind),
                "group": nested.length > 0
            });
        }
        out.sort((a, b) => a.chord.localeCompare(b.chord));
        return out;
    }

    readonly property int rowHeight: Theme.fontSize + 10
    // a tall map wraps into columns instead of climbing the screen
    readonly property int maxRows: Math.max(1, Math.floor((win.screen ? win.screen.height * 0.4 : 400) / win.rowHeight))
    readonly property int columnCount: Math.max(1, Math.ceil(win.entries.length / win.maxRows))
    readonly property int rowCount: Math.max(1, Math.ceil(win.entries.length / win.columnCount))

    onSubmapChanged: {
        if (win.submap.length) {
            // first submap after startup, if nothing has populated the cache yet — otherwise
            // the binds are already loaded and entering a submap costs no subprocess at all
            if (Keymap.binds.length === 0)
                Keymap.load();
            showDelay.restart();
        } else {
            showDelay.stop();
            win.armed = false;
        }
    }

    Timer {
        id: showDelay
        interval: Shell.submapHintsDelay
        onTriggered: win.armed = true
    }

    onWantShownChanged: {
        if (win.wantShown)
            win.mapped = true;
        else
            fadeOut.restart();
    }

    // unmapping on the same frame the fade starts would cut it off
    Timer {
        id: fadeOut
        interval: Theme.animFast
        onTriggered: if (!win.wantShown)
            win.mapped = false
    }

    Elevation {
        target: slab
        level: 1.2
        opacity: slab.opacity
    }

    Rectangle {
        id: slab
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.pad
        width: Math.min(body.implicitWidth + Theme.pad * 2, win.width - Theme.pad * 4)
        height: body.implicitHeight + Theme.pad * 2
        radius: Theme.radius
        // Glass, at the notification drawer's opacity (NotifyConfig.drawer.opacity). Borderless
        // on purpose: this is paper that landed on the desktop, not a dialog.
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, NotifyConfig.drawer.opacity)

        opacity: win.wantShown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
                easing.type: Theme.easing
            }
        }

        Column {
            id: body
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: win.submap
                color: Theme.accent
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }

            Grid {
                flow: Grid.TopToBottom
                rows: win.rowCount
                columns: win.columnCount
                rowSpacing: 2
                columnSpacing: Theme.pad

                Repeater {
                    model: win.entries

                    Row {
                        id: hint
                        required property var modelData
                        height: win.rowHeight
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 74
                            horizontalAlignment: Text.AlignRight
                            text: hint.modelData.chord
                            color: Theme.accent
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSize - 1
                            elide: Text.ElideLeft
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "→"
                            color: Theme.subtext
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: hint.modelData.label
                            // a group reads like which-key's "+prefix": accent, not body text
                            color: hint.modelData.group ? Theme.accent : Theme.fg
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSize - 1
                        }
                    }
                }
            }
        }
    }
}
