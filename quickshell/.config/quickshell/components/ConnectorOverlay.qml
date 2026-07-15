import QtQuick
import Quickshell
import Quickshell.Wayland
import "../config"

// Energy connector lines between separate windows (bar → Popout): one fullscreen
// transparent window per screen, mapped only while that screen has live links in the
// Connectors registry (and effects are on — the lines are pure flourish, no static
// fallback). The window is input-invisible: empty mask = full click/hover passthrough,
// no keyboard focus, no exclusion zone. Top layer, not Overlay — it must never stack
// above the Launcher or other Overlay-layer dialogs. (Fullscreen dialogs draw their own
// fan lines in-window via ConnectorFan instead, so they sit above the dialog scrim.)
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property var myLinks: Connectors.links.filter(l => l.screenName === modelData.name)

            visible: Shell.effectsOn && myLinks.length > 0
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-connectors"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // empty input region → everything passes through to the surfaces below
            mask: Region {}

            ConnectorLines {
                anchors.fill: parent
                links: win.myLinks
            }
        }
    }
}
