import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import ".."
import "../../config"

// StatusNotifier tray. Left click = activate, middle = secondaryActivate, right click = the app's
// native DBus menu via item.display(window, x, y). Hover shows a title tooltip. When more than
// `maxVisible` items are present, the overflow collapses into an ellipsis button that opens a
// popout grid. barWindow is the host PanelWindow (parent for display()).
Item {
    id: root
    property var barWindow
    property int cellW: Theme.barIcon + 16
    property int maxVisible: 6

    // shared hover tooltip state
    property Item hoverCell: null
    property string hoverTitle: ""

    readonly property var allItems: SystemTray.items ? SystemTray.items.values : []
    readonly property var visibleItems: allItems.slice(0, maxVisible)
    readonly property var overflowItems: allItems.length > maxVisible ? allItems.slice(maxVisible) : []

    implicitHeight: Theme.barIcon + 6
    implicitWidth: mainRow.implicitWidth
    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.animFast
            easing.type: Theme.easing
        }
    }

    // one tray icon (reused in the bar row and the overflow popout)
    component TrayIcon: Item {
        id: cell
        property var item
        readonly property string label: item ? (item.tooltipTitle || item.title || item.id || "") : ""
        width: root.cellW
        height: root.cellW

        IconImage {
            id: img
            anchors.centerIn: parent
            implicitSize: Theme.barIcon
            source: cell.item ? cell.item.icon : ""
            scale: cma.containsMouse ? 1.18 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Theme.animFast
                    easing.type: Theme.easing
                }
            }
        }

        MouseArea {
            id: cma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onEntered: {
                root.hoverCell = cell;
                root.hoverTitle = cell.label;
                tip.open();
            }
            onExited: if (root.hoverCell === cell)
                tip.close()
            onClicked: mouse => {
                tip.close();
                if (mouse.button === Qt.LeftButton) {
                    if (cell.item.onlyMenu)
                        cell.item.display(root.barWindow, cell.x, root.height);
                    else
                        cell.item.activate();
                } else if (mouse.button === Qt.MiddleButton) {
                    cell.item.secondaryActivate();
                } else if (mouse.button === Qt.RightButton && cell.item.hasMenu) {
                    cell.item.display(root.barWindow, cell.x, root.height);
                }
            }
        }
    }

    Row {
        id: mainRow
        anchors.centerIn: parent
        spacing: 4
        Repeater {
            model: root.visibleItems
            delegate: TrayIcon {
                required property var modelData
                item: modelData
            }
        }

        // overflow toggle
        Item {
            visible: root.overflowItems.length > 0
            width: visible ? root.cellW : 0
            height: root.cellW
            Text {
                anchors.centerIn: parent
                text: "\uf141" // fa-ellipsis-h
                color: overflowMa.containsMouse ? Theme.accent : Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.barIcon
                scale: overflowMa.containsMouse ? 1.18 : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animFast
                        easing.type: Theme.easing
                    }
                }
            }
            MouseArea {
                id: overflowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: overflowPop.toggle()
            }
        }
    }

    // shared hover-title tooltip
    Tooltip {
        id: tip
        anchorItem: root.hoverCell
        text: root.hoverTitle
    }

    // overflow grid
    Popout {
        id: overflowPop
        anchorItem: root
        readonly property int cols: Math.min(root.overflowItems.length, 5)
        // width = grid + body padding, so the last column isn't clipped
        popWidth: cols * root.cellW + (cols - 1) * 2 + Theme.pad * 2

        Grid {
            width: parent.width
            columns: overflowPop.cols
            spacing: 2
            Repeater {
                model: root.overflowItems
                delegate: TrayIcon {
                    required property var modelData
                    item: modelData
                }
            }
        }
    }
}
