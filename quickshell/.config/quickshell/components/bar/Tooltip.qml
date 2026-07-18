import QtQuick
import ".."
import "../../config"

// Reusable hover-title tooltip: a non-dismissable Popout that sizes to the true full-text width
// (TextMetrics, so an elided Text can't wedge it small). Drive it from a module's hover handlers:
//   Tooltip { id: tip; anchorItem: someItem; text: "..." }  + onEntered: tip.open()  onExited: tip.close()
Popout {
    id: tip
    property alias text: lbl.text
    dismissable: false
    reflection: false
    travelMs: 70 // hover labels: quicker line travel so scrubbing across icons stays snappy
    popWidth: Math.min(340, tm.advanceWidth + Theme.pad * 2 + 2)

    TextMetrics {
        id: tm
        font: lbl.font
        text: tip.text
    }
    Text {
        id: lbl
        width: parent.width
        color: Theme.fg
        font.family: Theme.fontUi
        font.pixelSize: Theme.fontSize - 1
        elide: Text.ElideRight
    }
}
