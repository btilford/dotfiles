import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import ".."
import "../../config"

// Collapsed sticky notifications, docked in the bar.
//
// A sticky card that has been on screen for a while folds to a pill (story: notif-timing) so it
// stops covering the desktop — but a pill still sitting in the popup stack is a pill occupying a
// stack slot. These land in the bar instead: same vertical band as the bar sections, in the gap
// between the workspace centre and the status cluster, but with NO bar background or border of
// their own. They float there as themselves.
//
// This is a view. The entries, their collapse state and their lifetimes all belong to the
// Notifications singleton; clicking a pill hands the notification back to the popup stack.
Item {
    id: root

    //! Monitor this bar is on. A notification pinned to another screen is not shown here.
    property string screenName: ""

    readonly property int maxPills: NotifyConfig.collapse.maxPills

    // Collapsed, still alive, and belonging to this monitor. "" means the notification follows
    // the focused monitor, which for a docked pill is read as "wherever it was raised".
    readonly property var pills: {
        const out = [];
        for (const e of Notifications.popups) {
            if (!e.collapsed || e.drawerOnly || !e.resolved || e.leaving)
                continue;
            if (e.screenName && e.screenName !== root.screenName)
                continue;
            out.push(e);
        }
        return out;
    }

    readonly property int overflow: Math.max(0, root.pills.length - root.maxPills)
    readonly property var shown: root.pills.slice(0, root.maxPills)

    visible: Shell.notificationsEnabled && root.pills.length > 0
    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: Theme.barHeightMinimal - 8

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        spacing: 6

        Repeater {
            model: root.shown

            delegate: Rectangle {
                id: pill

                required property var modelData
                readonly property var entry: pill.modelData
                readonly property bool critical: pill.entry.urgency === NotificationUrgency.Critical
                readonly property color tone: pill.critical ? Theme.urgent : (pill.entry.urgency === NotificationUrgency.Low ? Theme.subtext : Theme.accent)

                readonly property string iconSource: {
                    if (pill.entry.image)
                        return pill.entry.image;
                    if (!pill.entry.appIcon)
                        return "";
                    if (pill.entry.appIcon.startsWith("/") || pill.entry.appIcon.startsWith("file://"))
                        return pill.entry.appIcon;
                    return Quickshell.iconPath(pill.entry.appIcon, true);
                }

                height: root.implicitHeight
                width: content.implicitWidth + Theme.barPad * 2
                radius: height / 2
                // no border: the same paper-not-power rule the cards follow, so a pill reads as
                // the card it came from rather than as another bar module
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, NotifyConfig.surface.pillOpacity)

                // arrival: the pill grows in place rather than appearing, so a fold that happens
                // while you are looking elsewhere still registers in peripheral vision
                scale: 0
                opacity: 0
                Component.onCompleted: {
                    pill.scale = 1;
                    pill.opacity = 1;
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animMed
                        easing.type: Easing.OutBack
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animFast
                    }
                }

                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: pill.height - 10
                        radius: 1.5
                        color: pill.tone
                    }

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pill.iconSource !== ""
                        source: pill.iconSource
                        sourceSize.width: Theme.barIcon - 4
                        sourceSize.height: Theme.barIcon - 4
                        width: visible ? Theme.barIcon - 4 : 0
                        height: Theme.barIcon - 4
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // the summary, not the app: which alert it is matters more in a pill than
                        // which program raised it, and there is only room for one of them
                        text: pill.entry.summary || pill.entry.appName
                        elide: Text.ElideRight
                        // long enough to identify, short enough that three of them fit the gap
                        width: Math.min(implicitWidth, 150)
                        color: pill.critical ? Theme.urgent : Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: pill.critical
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        tip.text = (pill.entry.summary || "") + (pill.entry.body ? " — " + pill.entry.body : "");
                        tip.open();
                    }
                    onExited: tip.close()
                    onClicked: mouse => {
                        tip.close();
                        if (mouse.button === Qt.MiddleButton) {
                            Notifications.dismiss(pill.entry);
                            return;
                        }
                        // hand it back to the popup stack, expanded, with a fresh collapse clock
                        Notifications.expand(pill.entry);
                    }
                }

                Shimmer {
                    anchors.fill: parent
                    radius: parent.radius
                }
            }
        }

        // Overflow: the bar is not a queue. Past maxPills the rest are one chip that opens the
        // drawer, where they are all listed anyway.
        Rectangle {
            visible: root.overflow > 0
            anchors.verticalCenter: parent.verticalCenter
            height: root.implicitHeight
            width: moreText.implicitWidth + Theme.barPad * 2
            radius: height / 2
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, NotifyConfig.surface.pillOpacity)

            Text {
                id: moreText
                anchors.centerIn: parent
                text: "+" + root.overflow
                color: Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 2
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    tip.text = root.overflow + " more collapsed — open the drawer";
                    tip.open();
                }
                onExited: tip.close()
                onClicked: {
                    tip.close();
                    NotifyDrawer.open();
                }
            }
        }
    }

    // One shadow for the whole tray rather than one per pill: they sit on the same plane, and
    // per-pill effects would each rasterize their own layer for a chip a few pixels tall.
    Elevation {
        target: row
        level: 0.8
    }

    Tooltip {
        id: tip
        anchorItem: root
    }
}
