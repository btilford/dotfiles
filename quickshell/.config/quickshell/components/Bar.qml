import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"
import "bar"

// One top bar per monitor. Portrait monitors (height > width) are "hubs" (taller, full modules);
// landscape monitors are minimal. If no portrait monitor exists, the focused monitor is the hub.
// Gated by Shell.barVisible; dev mode renders at the bottom with no exclusive zone so it can run
// alongside waybar during development.
Scope {
    id: barScope

    readonly property bool anyPortrait: {
        for (const s of Quickshell.screens)
            if (s.height > s.width)
                return true;
        return false;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            visible: Shell.barVisible
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top

            readonly property bool portrait: modelData.height > modelData.width
            readonly property bool isHub: barScope.anyPortrait
                ? portrait
                : (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === modelData.name)
            readonly property bool devMode: Shell.barDevMode

            anchors {
                left: true
                right: true
                top: !bar.devMode
                bottom: bar.devMode
            }
            implicitHeight: bar.isHub ? Theme.barHeightHub : Theme.barHeightMinimal
            exclusiveZone: bar.devMode ? 0 : bar.implicitHeight

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Theme.animMed
                    easing.type: Theme.easing
                }
            }

            Item {
                anchors.fill: parent

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.barPad

                    // left: windows on this monitor's active workspace —  ____/
                    Section {
                        barHeight: bar.implicitHeight
                        slantLeft: false
                        slantRight: true
                        Layout.alignment: Qt.AlignVCenter
                        WindowList {
                            screenName: bar.modelData.name
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // center: this monitor's workspaces —  \____/
                    Section {
                        barHeight: bar.implicitHeight
                        Layout.alignment: Qt.AlignVCenter
                        Workspaces {
                            screenName: bar.modelData.name
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // right: clock (status modules join it in phase B) —  \____
                    Section {
                        barHeight: bar.implicitHeight
                        slantLeft: true
                        slantRight: false
                        Layout.alignment: Qt.AlignVCenter
                        Clock {}
                    }
                }
            }
        }
    }
}
