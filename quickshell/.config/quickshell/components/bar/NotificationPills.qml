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

    // ---------------------------------------------------------------------------------------
    // Fitting the gap.
    //
    // This tray lives between the workspace centre and the status cluster, and on a PORTRAIT
    // monitor that gap is a few hundred pixels, not a thousand. The mode is therefore derived
    // from the width actually available rather than assumed:
    //
    //   full     icon + summary, the normal landscape case
    //   compact  icon only — you can see how many and how urgent, hover for the text
    //   chip     one "N" bubble; the bar has no room to say anything more, so it says how many
    //
    // The thresholds are ESTIMATES, deliberately: measuring the laid-out row and feeding that
    // back into the mode that determines the row's width is a binding loop. Conservative
    // constants cannot oscillate.
    // ---------------------------------------------------------------------------------------

    readonly property int fullPillWidth: 190   // icon + elided summary + padding
    readonly property int compactPillWidth: 46 // stripe + icon + padding
    readonly property int chipWidth: 54
    readonly property int gutter: 6

    // room for the "+N" chip when not everything fits
    readonly property real usable: Math.max(0, root.width - (root.pills.length > root.maxPills ? root.chipWidth + root.gutter : 0))

    readonly property int fitsFull: Math.floor((root.usable + root.gutter) / (root.fullPillWidth + root.gutter))
    readonly property int fitsCompact: Math.floor((root.usable + root.gutter) / (root.compactPillWidth + root.gutter))

    readonly property string mode: {
        if (root.fitsFull >= 1)
            return "full";
        if (root.fitsCompact >= 1)
            return "compact";
        return "chip";
    }

    readonly property int visibleCount: {
        if (root.mode === "chip")
            return 0;
        const fits = root.mode === "full" ? root.fitsFull : root.fitsCompact;
        return Math.max(0, Math.min(root.pills.length, Math.min(root.maxPills, fits)));
    }

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

    readonly property int overflow: Math.max(0, root.pills.length - root.visibleCount)
    readonly property var shown: root.pills.slice(0, root.visibleCount)

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
                        // which program raised it, and there is only room for one of them.
                        // Dropped entirely in compact mode — the hover tooltip still has it.
                        visible: root.mode === "full"
                        // A timer's card folds to a pill like any other sticky, and a pill that
                        // says only "Deep work" has thrown away the one thing a running timer is
                        // for. It keeps counting here (story: notif-timers).
                        text: {
                            Timers.revision;
                            Timers.now;
                            const t = Timers.stateFor(pill.entry);
                            const name = pill.entry.summary || pill.entry.appName;
                            return t ? Timers.fmt(Timers.remainingOf(t)) + "  " + name : name;
                        }
                        elide: Text.ElideRight
                        // long enough to identify, short enough that three of them fit the gap
                        width: visible ? Math.min(implicitWidth, 150) : 0
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
                        // Anchor to THIS pill, not the tray. The tray is anchored left AND right
                        // in Bar.qml so it spans the whole gap between the workspaces and the
                        // status cluster — anchoring the tip to it puts the tooltip in the middle
                        // of that empty space, nowhere near the pill under the cursor.
                        tip.anchorItem = pill;
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

        // Overflow — and, on a bar too narrow for even one compact pill, the whole tray. Either
        // way it says how many and opens the drawer, because the bar is not a queue.
        Rectangle {
            id: overflowChip
            visible: root.overflow > 0
            anchors.verticalCenter: parent.verticalCenter
            height: root.implicitHeight
            width: moreText.implicitWidth + Theme.barPad * 2
            radius: height / 2
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, NotifyConfig.surface.pillOpacity)

            Text {
                id: moreText
                anchors.centerIn: parent
                // "+2" next to visible pills, plain "3" when it IS the tray
                text: (root.mode === "chip" ? "" : "+") + root.overflow
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
                    tip.text = root.mode === "chip" ? root.overflow + " collapsed — open the drawer" : root.overflow + " more collapsed — open the drawer";
                    tip.anchorItem = overflowChip;
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
        // Reassigned per hover to the pill or chip under the cursor; root is only the
        // fallback for the frame before the first hover.
        anchorItem: root
    }
}
