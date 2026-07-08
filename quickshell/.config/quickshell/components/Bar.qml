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

                // left: windows on this monitor's active workspace —  ____/
                Section {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    barHeight: bar.implicitHeight
                    slantLeft: false
                    slantRight: true
                    Power {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    LayoutMode {
                        anchors.verticalCenter: parent.verticalCenter
                        screenName: bar.modelData.name
                        portrait: bar.portrait
                    }
                    Submap {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    WindowList {
                        anchors.verticalCenter: parent.verticalCenter
                        screenName: bar.modelData.name
                    }
                }

                // center: this monitor's workspaces — pinned to TRUE screen center —  \____/
                Section {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    barHeight: bar.implicitHeight
                    Workspaces {
                        screenName: bar.modelData.name
                    }
                }

                // right: status cluster + clock —  \____
                // Audio/Network/Bluetooth are ALWAYS visible (even on minimal landscape bars);
                // Tray + Battery only on hub bars (Battery also self-hides on desktops).
                Section {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    barHeight: bar.implicitHeight
                    slantLeft: true
                    slantRight: false
                    Tray {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: bar.isHub
                        barWindow: bar
                    }
                    Network {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Bluetooth {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Audio {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Battery {
                        anchors.verticalCenter: parent.verticalCenter
                        hub: bar.isHub
                    }
                    Clock {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
