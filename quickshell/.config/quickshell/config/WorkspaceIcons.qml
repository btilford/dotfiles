pragma Singleton

import QtQuick
import Quickshell

// Workspace name -> nerd-font glyph, shared by everything that shows a workspace: the bar's
// workspace pills, the window picker and the launcher's windows mode. It lived inside
// bar/Workspaces.qml until a second and third consumer needed it.
Singleton {
    readonly property var glyphs: ({
            "Main": "",       // home
            "CLI1": "",       // terminal
            "CLI2": "",       // terminal
            "Draw": "",       // paint-brush
            "RefLeft": "",    // book
            "RefRight": "",   // book
            "Music": "",      // music
            "Messaging": "",  // comments
            "Other": ""       // ellipsis
        })
    // windows the app submap hid on special:hide-<class> (hypr/lua/keybindings.lua)
    readonly property string hiddenGlyph: "" // eye-slash

    // glyph for a workspace name, or "" when unmapped
    function iconFor(name) {
        return name && glyphs[name] ? glyphs[name] : "";
    }

    // "<glyph> <name>" for a hyprctl workspace name, as a list row shows it:
    // hide-* workspaces read "hidden", other specials drop their "special:" prefix.
    function label(name) {
        const n = name || "";
        if (n.startsWith("special:hide-"))
            return hiddenGlyph + " hidden";
        if (n.startsWith("special:"))
            return n.substring(8) + " (special)";
        const ic = iconFor(n);
        return ic ? ic + " " + n : n;
    }
}
