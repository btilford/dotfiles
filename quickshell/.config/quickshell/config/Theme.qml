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

    // --- contrast ---
    //
    // `subtext` is wallust's color8 as-is, so its contrast against our (pinned, warm) surfaces
    // changes with every wallpaper: #766C57 on #2a1010 is about 3:1, under the 4.5:1 small
    // text needs, and secondary text in the notification drawer was hard to read for exactly
    // that reason. Do not fix it by picking a brighter constant — the next wallpaper moves it
    // again. Ask for a ratio against the background the text actually sits on instead.
    //
    // WCAG 2 relative luminance and contrast ratio.
    function luminance(c: color): real {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }
    function contrast(a: color, b: color): real {
        const la = luminance(a);
        const lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    // `c`, moved toward white (on a dark background) or black (on a light one) in 5% steps
    // until it reaches `min` against `bg`. Mixing rather than replacing keeps the hue, so muted
    // text still carries the wallpaper's tint; a colour that already passes comes back as is.
    function readable(c: color, bg: color, min: real): color {
        const toWhite = luminance(bg) < 0.18;
        const t = toWhite ? 1 : 0;
        for (let k = 0; k <= 20; k++) {
            const w = k / 20;
            const m = Qt.rgba(c.r + (t - c.r) * w, c.g + (t - c.g) * w, c.b + (t - c.b) * w, 1);
            if (contrast(m, bg) >= min)
                return m;
        }
        return Qt.rgba(t, t, t, 1);
    }
    // Secondary text that is legible on `surface` — the default for muted text on cards and rows.
    readonly property real textContrast: 4.5
    readonly property color muted: readable(subtext, surface, textContrast)

    // --- glass ---
    //
    // The tint for translucent slabs (submap hints, notification drawer). NOT `surface` used
    // directly, which is what these read before and is the reason they looked like a brown
    // wash rather than glass.
    //
    // Two corrections on top of `surface`, both measured on the submap hints (2026-08-04):
    //
    // 1. Desaturate toward the BRIGHTEST channel, not toward luminance. `surface` is #2a1010
    //    under warmBase and carries nearly all its brightness in red, so a luminance-grey mix
    //    drops R 42 -> 22 and the slab collapses to near-black. Mixing toward the max channel
    //    lifts green and blue up to meet red: the hue goes, the weight stays.
    // 2. Lift toward white. Blur only reads as frost where there is contrast to see it
    //    against, and these surfaces usually sit over a dark terminal, which supplies none.
    //    Same layer acrylic/vibrancy implementations put above the tint, for the same reason.
    //
    // Slab alpha is per-surface and much lower than it looks like it should be — see
    // Shell.submapHintsOpacity for why raising it does NOT improve legibility (it is a
    // Rectangle fill; child Text is opaque at any value).
    readonly property real glassDesaturate: 0.7
    readonly property real glassLift: 0.3
    readonly property color glassBase: {
        const s = surface;
        const m = Math.max(s.r, s.g, s.b);
        const k = glassDesaturate;
        const n = glassLift;
        const r = s.r + (m - s.r) * k;
        const g = s.g + (m - s.g) * k;
        const b = s.b + (m - s.b) * k;
        return Qt.rgba(r + (1 - r) * n, g + (1 - g) * n, b + (1 - b) * n, 1);
    }
    // glass fill at a given alpha — the one call site for every translucent slab
    function glass(alpha: real): color {
        return Qt.rgba(glassBase.r, glassBase.g, glassBase.b, alpha);
    }

    // --- shader / energy-border tokens (warm palette) ---
    readonly property color energy: accent      // normal energy glow (#ff6600)
    // active/high-energy glow — pinned warm with the accent; wallust's color9 can be
    // near-white on pale wallpapers, which reads as a white border, not a surge
    readonly property color energyActive: pinAccent ? "#ffaa00" : urgent

    // border weights — every border in the shell routes through these
    readonly property real borderThickness: 6.0 // energy/shader borders (Section, Popout, overlays)
    readonly property real borderThin: 1.25     // static hairline outlines (cards, keycaps, inputs)

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
    // popout stand-off from the bar — long enough for the energy connector arc to read
    // as a line (pairs with the hyprland top gutter, windows.lua gaps_out.top)
    readonly property int popoutGap: 22
    // connector arcs are conduits FEEDING the popout border — much heavier than the
    // border stroke they pour into, but lighter than the dialog fan lines
    readonly property real connectorThickness: borderThickness * 4.75
    // dialog fan lines are the heaviest strokes on screen — full-window conduits
    readonly property real connectorFanThickness: borderThickness * 5

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
