pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Terminal-flavored theme tokens.
// Fallback constants come from the ghostty + tmux configs; the live palette is read from
// the wallust-generated ~/.config/quickshell/wallust/colors.json (regenerated on wallpaper
// switch by WallustSwww.sh) and hot-reloads via FileView.watchChanges.
Singleton {
    id: root

    // --- terminal fallback / brand (ghostty config + .tmux.conf) ---
    readonly property color fbBg: "#1a0808"
    readonly property color fbSurface: "#2a1010"
    readonly property color fbFg: "#cdd6f4"
    readonly property color fbSubtext: "#585555"
    readonly property color fbAccent: "#ff6600" // system-wide orange (hyprland border, tmux, ghostty)
    readonly property color fbUrgent: "#ffaa00"

    // parsed wallust palette (empty until colors.json exists)
    property var palette: ({})

    // Keep a warm terminal base (ghostty) regardless of wallpaper, so the shell never
    // goes cold/blue when a wallpaper is blue-dominant. Set false to fully follow wallust.
    property bool warmBase: true
    // Pin the brand orange as accent even when the palette follows the wallpaper.
    property bool pinAccent: true

    readonly property color bg: warmBase ? fbBg : (palette.background ? palette.background : fbBg)
    readonly property color surface: warmBase ? fbSurface : (palette.color0 ? palette.color0 : fbSurface)
    readonly property color fg: palette.foreground ? palette.foreground : fbFg
    readonly property color subtext: palette.color8 ? palette.color8 : fbSubtext
    readonly property color accent: pinAccent
        ? fbAccent
        : (palette.color12 ? palette.color12 : fbAccent)
    readonly property color urgent: palette.color9 ? palette.color9 : fbUrgent
    readonly property color border: accent

    // --- shader / energy-border tokens (warm palette) ---
    readonly property color energy: accent      // normal energy glow (#ff6600)
    readonly property color energyActive: urgent // active/high-energy glow (#ffaa00)

    // terminal look
    readonly property real surfaceOpacity: 0.85
    readonly property string fontUi: "JetBrainsMono Nerd Font"
    readonly property string fontMono: "JetBrains Mono"
    readonly property int radius: 8
    readonly property int pad: 12
    readonly property int fontSize: 13

    // bar
    readonly property int barHeightMinimal: 28
    readonly property int barHeightHub: 40
    readonly property int barIcon: 18
    readonly property int barPad: 8
    readonly property real barOpacity: 0.6

    // animation tokens — reuse everywhere for a consistent feel
    readonly property int animFast: 120
    readonly property int animMed: 200
    readonly property int animSlow: 340
    readonly property int easing: Easing.OutCubic

    function reloadPalette() {
        try {
            const t = colorsFile.text();
            root.palette = (t && t.length) ? JSON.parse(t) : ({});
        } catch (e) {
            root.palette = ({});
        }
    }

    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/wallust/colors.json"
        watchChanges: true
        onLoaded: root.reloadPalette()
        onFileChanged: {
            reload();
            root.reloadPalette();
        }
    }

    Component.onCompleted: reloadPalette()
}
