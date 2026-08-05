import QtQuick
import Quickshell
import Quickshell.Io
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

    // --- preview override, for the headless capture rig -------------------------
    //
    // This overlay is driven by real Hyprland submap state, and the capture rig runs
    // sway (Hyprland 0.56 cannot start headless), so there is no way to make it appear
    // there. It shipped with no capture scene at all as a result — the repo's own rule
    // that quickshell changes are verified headless, never in the live session, could
    // not actually be met for this component.
    //
    // These two properties are the seam that fixes that. Nothing sets them in normal
    // operation, so the live path is unchanged and costs one null check.
    //
    //   qs ipc call submapHints preview resize 14
    //   qs ipc call submapHints hide
    property var previewEntries: null
    property string previewSubmap: ""

    IpcHandler {
        target: "submapHints"

        // Fake `count` entries for map `name`, with labels long enough to exercise the
        // elide, so a capture shows the worst case rather than a tidy one.
        function preview(name: string, count: int): void {
            const out = [];
            const chords = ["h", "j", "k", "l", "SUPER+h", "SUPER+SHIFT+j", "1", "2", "3", "4", "5", "f", "b", "n", "p", "g", "d", "y"];
            for (let i = 0; i < count; i++) {
                out.push({
                    "chord": chords[i % chords.length],
                    "label": i % 5 === 0 ? "+nested group" : "action with a deliberately long name " + i,
                    "group": i % 5 === 0
                });
            }
            win.previewEntries = out;
            win.previewSubmap = name;
        }

        function hide(): void {
            win.previewEntries = null;
            win.previewSubmap = "";
        }
    }

    // the map being described; "" = default map, nothing to show
    readonly property string submap: win.previewSubmap.length ? win.previewSubmap : Keymap.currentSubmap
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
    // Lifted off the bottom edge rather than hugging it. ExclusionMode.Ignore means nothing
    // reflows out of the way, so at Theme.pad the slab landed straight on top of whatever
    // occupies the last rows of a full-height terminal — a tmux status line and the prompt
    // below it — and the hints competed with that text instead of sitting clear of it.
    //
    // Expressed in text rows so it tracks the font rather than a pixel count that stops
    // being right the moment either changes.
    //
    // The dev-mode bar sits at the BOTTOM, so its height still stacks on top of this.
    margins.bottom: Theme.pad + win.textSize * 6 + (Shell.barVisible && Shell.barDevMode ? Theme.barHeightHub : 0)

    implicitHeight: slab.height + Theme.pad * 2

    // [{chord, label, group}] for the active submap. A bind that enters a NESTED submap is
    // rendered as a which-key "+prefix" group rather than by its dispatcher.
    readonly property var entries: {
        if (win.previewEntries)
            return win.previewEntries;
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

    // Two points up on the shell's base size. This overlay is read in a glance while a chord
    // is half-entered, at whatever distance the monitor happens to be — it is not body text,
    // and the -1 it used to run at made it the smallest thing on screen.
    readonly property int textSize: Theme.fontSize + 1
    readonly property int rowHeight: win.textSize + 10

    // Which-key's shape: a WIDE, short slab across the bottom.
    //
    // The layout is driven by width and the row count falls out of it. The first
    // version did the opposite — it capped rows at 40% of screen height and let
    // columns accumulate — which on a small map produced one tall narrow column
    // hugging the bottom edge, the shape nvim's which-key deliberately avoids.
    //
    // Fixed-width cells rather than implicit ones, because columns that each size
    // to their own longest label do not line up vertically, and a which-key panel
    // is read by scanning DOWN a column of chords. The cost is a hard elide on a
    // long action name, which is the right trade for a hint overlay.
    readonly property real slabWidth: Math.round((win.screen ? win.screen.width : 1920) * 0.94)
    // scales with the text, so a font bump cannot start clipping "SUPER+SHIFT+j"
    readonly property int chordWidth: Math.round(win.textSize * 5.3)
    readonly property int hintWidth: win.chordWidth + Math.round(win.textSize * 13)
    readonly property int columnCount: Math.max(1, Math.min(win.entries.length, Math.floor((win.slabWidth - Theme.pad * 2 + Theme.pad) / (win.hintWidth + Theme.pad))))
    readonly property int rowCount: Math.max(1, Math.ceil(win.entries.length / win.columnCount))

    onSubmapChanged: {
        if (win.submap.length) {
            // first submap after startup, if nothing has populated the cache yet — otherwise
            // the binds are already loaded and entering a submap costs no subprocess at all.
            // Skipped under preview: the entries are supplied, and Keymap.load() shells out to
            // hyprctl, which does not exist in the capture rig.
            if (!win.previewEntries && Keymap.binds.length === 0)
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
        // Fixed near-full width, not the content's implicit width: the panel should
        // be the same size every time it appears, so its position is muscle memory
        // rather than something that jumps with the size of the map.
        width: Math.min(win.slabWidth, win.width - Theme.pad * 2)
        height: body.implicitHeight + Theme.pad * 2
        radius: Theme.radius
        // Glass. Borderless on purpose: this is paper that landed on the desktop, not a
        // dialog. The opacity is this component's OWN setting — it used to read
        // NotifyConfig.drawer.opacity, which coupled two unrelated surfaces, so tuning the
        // hints for legibility over a bright window restyled the notification drawer too.
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Shell.submapHintsOpacity)

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
                font.pixelSize: win.textSize
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
                        width: win.hintWidth
                        height: win.rowHeight
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: win.chordWidth
                            horizontalAlignment: Text.AlignRight
                            text: hint.modelData.chord
                            color: Theme.accent
                            font.family: Theme.fontMono
                            font.pixelSize: win.textSize
                            elide: Text.ElideLeft
                        }
                        Text {
                            id: arrow
                            anchors.verticalCenter: parent.verticalCenter
                            text: "→"
                            color: Theme.subtext
                            font.family: Theme.fontMono
                            font.pixelSize: win.textSize - 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            // fills the rest of the fixed cell, so long labels elide instead of
                            // pushing the next column out of alignment
                            width: hint.width - win.chordWidth - arrow.width - hint.spacing * 2
                            text: hint.modelData.label
                            elide: Text.ElideRight
                            // a group reads like which-key's "+prefix": accent, not body text
                            color: hint.modelData.group ? Theme.accent : Theme.fg
                            font.family: Theme.fontUi
                            font.pixelSize: win.textSize
                        }
                    }
                }
            }
        }
    }
}
