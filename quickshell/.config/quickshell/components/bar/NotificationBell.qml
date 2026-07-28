import QtQuick
import Quickshell
import ".."
import "../../config"

// Notification bell. The dwell target: a timed-out card flies up into this widget instead of
// fading out, so the motion ends somewhere meaningful and the count it lands on is visible.
//
// Deliberately minimal. It shows how many notifications have dwelled here since they were last
// acknowledged, and clicking clears that. Opening a history drawer, per-category badges and
// do-not-disturb state are their own stories — do not grow this into them.
Item {
    id: root

    // monitor this bar (and therefore this bell) is on, and the window it lives in — both needed
    // to publish the bell's position in SCREEN coordinates for the dwell flight to aim at
    property string screenName: ""
    property var barWindow: null

    readonly property int unread: Notifications.unread
    readonly property bool live: Notifications.count > 0

    // Only shown when this shell actually owns the notification server: with swaync handling
    // notifications a bell here would be a bell that never rings.
    visible: Shell.notificationsEnabled
    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: Theme.barIcon + 6

    // A dev-mode bar sits at the BOTTOM of the screen, so its window origin is not the screen
    // origin; everything else is anchored at the top where the two coincide.
    readonly property real screenOffsetY: {
        if (!Shell.barDevMode || !root.barWindow || !root.barWindow.screen)
            return 0;
        return root.barWindow.screen.height - root.barWindow.height;
    }

    function publish() {
        if (!root.screenName)
            return;
        if (!root.visible) {
            Notifications.clearBellAnchor(root.screenName);
            return;
        }
        // mapToItem(null, …) is window coordinates; the popup windows cover the whole output
        // (ExclusionMode.Ignore), so once the bar offset is added both live in screen space.
        const p = root.mapToItem(null, root.width / 2, root.height / 2);
        Notifications.setBellAnchor(root.screenName, p.x, p.y + root.screenOffsetY);
    }

    onXChanged: publish()
    onYChanged: publish()
    onWidthChanged: publish()
    onVisibleChanged: publish()
    Component.onCompleted: publish()
    Component.onDestruction: if (root.screenName)
        Notifications.clearBellAnchor(root.screenName)

    // The bar sections animate their width, which slides this widget without changing any of its
    // own geometry properties. Re-publishing whenever the popup model moves costs one mapToItem
    // and guarantees the anchor is fresh at the moment a flight is about to start.
    Connections {
        target: Notifications
        function onPopupsChanged() {
            root.publish();
        }
        function onDwellLanded(screenName) {
            if (screenName === "" || screenName === root.screenName)
                land.restart();
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Text {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            // fa-bell while something is unread or live, fa-bell-o when quiet
            text: root.unread > 0 || root.live ? "" : ""
            color: root.unread > 0 ? Theme.accent : Theme.fg
            font.family: Theme.fontUi
            font.pixelSize: Theme.barIcon
            scale: ma.containsMouse ? 1.15 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Theme.animFast
                    easing.type: Theme.easing
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.unread > 0
            text: root.unread
            color: Theme.accent
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize - 1
            font.bold: true
        }
    }

    // The card lands: the bell takes the impact. Same spike-and-settle as the workspace pill,
    // so arrivals read as one vocabulary across the bar.
    SequentialAnimation {
        id: land
        NumberAnimation {
            target: glyph
            property: "scale"
            from: 1.0
            to: 1.45
            duration: 90
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: glyph
            property: "scale"
            to: 1.0
            duration: 220
            easing.type: Easing.OutBack
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            tip.text = root.unread > 0 ? root.unread + " notification(s) since last checked" : (root.live ? Notifications.count + " on screen" : "No new notifications");
            tip.open();
        }
        onExited: tip.close()
        onClicked: mouse => {
            tip.close();
            if (mouse.button === Qt.MiddleButton)
                Notifications.dismissAll();
            Notifications.markRead();
        }
    }

    Tooltip {
        id: tip
        anchorItem: root
    }
}
