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

            // Publish the section feet for the dialog connector fan-out (screen coords —
            // the bar window is pinned to the screen's top edge). Re-publishes whenever
            // section geometry animates. Dev-mode bottom bars publish nothing: the fan
            // math assumes lines drop DOWN from the bar.
            readonly property var connAnchors: bar.devMode ? [] : [
                { x: leftSection.x + leftSection.width - leftSection.slant, y: bar.implicitHeight },
                { x: centerSection.x + centerSection.width / 2, y: bar.implicitHeight },
                { x: rightSection.x + rightSection.slant, y: bar.implicitHeight }
            ]
            onConnAnchorsChanged: Connectors.setSectionAnchors(bar.modelData.name, connAnchors)
            Component.onCompleted: Connectors.setSectionAnchors(bar.modelData.name, connAnchors)

            // Pulse every section's energy border on window focus / move / open.
            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    switch (event.name) {
                    case "activewindow":
                    case "movewindow":
                    case "openwindow":
                        leftSection.pulse();
                        centerSection.pulse();
                        rightSection.pulse();
                        break;
                    }
                }
            }

            Item {
                anchors.fill: parent

                // left: windows on this monitor's active workspace —  ____/
                Section {
                    id: leftSection
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
                    id: centerSection
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    barHeight: bar.implicitHeight
                    Workspaces {
                        screenName: bar.modelData.name
                    }
                }

                // Now playing, floating in the gap between the window list and the workspaces —
                // the mirror of NotificationPills on the other side of the centre. Same rule:
                // deliberately NOT inside a Section, because Section.qml is what draws the
                // slanted bar surface and this is text and icons only. Left-aligned so it grows
                // rightward into empty space; the centre section is pinned to true screen
                // centre, so any width this wants is absorbed by eliding the title.
                NowPlaying {
                    id: nowPlaying
                    screenName: bar.modelData.name
                    anchors.left: leftSection.right
                    anchors.leftMargin: Theme.barPad
                    anchors.right: centerSection.left
                    anchors.rightMargin: Theme.barPad
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Collapsed sticky notifications, floating in the gap between the workspaces and
                // the status cluster. Deliberately NOT inside a Section: these are notifications
                // that folded down, not bar modules, so they carry their own pill surface and no
                // bar background. Right-aligned so the tray grows leftward into empty space
                // instead of pushing the status cluster around.
                NotificationPills {
                    id: notifPills
                    screenName: bar.modelData.name
                    anchors.right: rightSection.left
                    anchors.rightMargin: Theme.barPad
                    anchors.left: centerSection.right
                    anchors.leftMargin: Theme.barPad
                    anchors.verticalCenter: parent.verticalCenter
                }

                // right: status cluster + clock —  \____
                // Audio/Network/Bluetooth are ALWAYS visible (even on minimal landscape bars);
                // Tray + Battery only on hub bars (Battery also self-hides on desktops).
                Section {
                    id: rightSection
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
                    // live stopwatch readout — hidden unless one is running (story: notif-timers).
                    // A countdown lives on a card; a stopwatch has no end to render there, so it
                    // reads out here.
                    Stopwatch {
                        anchors.verticalCenter: parent.verticalCenter
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
                    // dwell target for expiring notification cards — it publishes its position to
                    // the Notifications singleton, so it must exist on every bar, hub or not
                    NotificationBell {
                        anchors.verticalCenter: parent.verticalCenter
                        screenName: bar.modelData.name
                        barWindow: bar
                    }
                    Clock {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
