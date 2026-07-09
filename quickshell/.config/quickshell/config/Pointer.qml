pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Global cursor position (Hyprland layout coordinates), polled via `hyprctl cursorpos`.
// Wayland clients can't read the pointer outside their own surfaces, so shell-wide
// "light position" effects (Shimmer) poll the compositor instead. 8Hz keeps the fork
// cost negligible; consumers smooth the motion themselves (the shader lerps via
// Behaviors on the light uniforms).
Singleton {
    id: root

    property real x: 0
    property real y: 0

    Process {
        id: proc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(",");
                if (parts.length === 2) {
                    const nx = parseFloat(parts[0]);
                    const ny = parseFloat(parts[1]);
                    if (!isNaN(nx) && !isNaN(ny)) {
                        root.x = nx;
                        root.y = ny;
                    }
                }
            }
        }
    }

    Timer {
        interval: 125
        running: true
        repeat: true
        onTriggered: {
            proc.running = false;
            proc.running = true;
        }
    }
}
