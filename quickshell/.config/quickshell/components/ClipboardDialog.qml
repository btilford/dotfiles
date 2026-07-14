import QtQuick
import Quickshell.Hyprland
import Clipborg
import "../config"

// Thin wrapper over the ClipboardDialog shipped by the clipborg repo
// (examples/quickshell/Clipborg — on QML_IMPORT_PATH via environments.lua).
// The repo is canonical: the dialog's behaviour, IPC and keys live there and
// arrive with `git pull`. Everything below is host glue — where it shows, what
// drives it, and how it's painted.
//
// Fix dialog *behaviour* in the clipborg repo, not here. If a change can't be
// expressed through these seams (shown/closeRequested/targetScreen/theme/effects),
// widen the seams upstream rather than forking the dialog back into dotfiles.
//
// Loaded through a LazyLoader in shell.qml: on a machine with no clipborg clone
// the `import Clipborg` fails, and the LazyLoader keeps that failure from taking
// the rest of the shell down with it.
ClipboardDialog {
    id: dialog

    // State lives in the Clipboard singleton, driven by `qs ipc call clipboard toggle`.
    shown: Clipboard.shown
    onCloseRequested: Clipboard.close()

    targetScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    // Wallust palette + terminal tokens, shared with the rest of the shell.
    theme: Theme

    // Shader decorations, matching the other overlays. The repo dialog renders
    // undecorated without these.
    boxEffect: Component {
        Item {
            EnergyBorder {
                anchors.fill: parent
                radius: Theme.radius
                thickness: Theme.borderThickness
                energy: 0.7
            }
            Shimmer {
                anchors.fill: parent
                radius: Theme.radius
            }
        }
    }

    boxUnderlay: Component {
        Reflection {
            sourceItem: dialog.boxItem
        }
    }

    highlightEffect: Component {
        EnergyFill {
            radius: 4
            alpha: 0.3
        }
    }
}
