import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../../config"

// Local clock. Hover opens a world-clock popout listing configurable timezones. qs's JS engine has
// no Intl/timezone support, so the zone times come from one `TZ=… date` shell call refreshed each
// minute (and on open). Edit `zones` to reconfigure (label + IANA tz).
Text {
    id: root
    property string format: "HH:mm · ddd dd/MM"

    // [label, IANA timezone]
    property var zones: [["UTC", "Etc/UTC"], ["Indianapolis", "America/Indiana/Indianapolis"], ["Florida", "America/New_York"], ["California", "America/Los_Angeles"], ["Minneapolis", "America/Chicago"]]
    property var zoneTimes: [] // [{label, time}]

    text: Qt.formatDateTime(clock.now, format)
    color: Theme.fg
    font.family: Theme.fontMono
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter

    QtObject {
        id: clock
        property var now: new Date()
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clock.now = new Date()
    }

    // ---- world clock ----
    function zoneScript() {
        const parts = root.zones.map(z => '"' + z[0] + '|' + z[1] + '"').join(" ");
        return 'for z in ' + parts + '; do l=${z%%|*}; t=${z##*|}; printf "%s\\t%s\\n" "$l" "$(TZ=$t date +%H:%M)"; done';
    }
    Process {
        id: tzProc
        command: ["sh", "-c", root.zoneScript()]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of this.text.split("\n")) {
                    if (!line.trim())
                        continue;
                    const p = line.split("\t");
                    out.push({ label: p[0], time: p[1] || "" });
                }
                root.zoneTimes = out;
            }
        }
    }
    function refreshZones() {
        tzProc.running = false;
        tzProc.running = true;
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshZones()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (!calPop.shown) {
            root.refreshZones();
            tzPop.open();
        }
        onExited: tzPop.close()
        onClicked: {
            tzPop.close();
            calPop.toggle();
        }
    }

    Popout {
        id: tzPop
        anchorItem: root
        dismissable: false
        popWidth: 190

        Repeater {
            model: root.zoneTimes
            delegate: Item {
                required property var modelData
                width: tzPop.popWidth - Theme.pad * 2
                height: 20
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 60
                    text: modelData.label
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 1
                    elide: Text.ElideRight
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.time
                    color: Theme.accent
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }

    // ---- calendar (click) ----
    property int calYear: (new Date()).getFullYear()
    property int calMonth: (new Date()).getMonth() // 0-11
    function buildCells(y, m, today) {
        const first = new Date(y, m, 1).getDay();      // 0=Sun
        const dim = new Date(y, m + 1, 0).getDate();   // days in month
        const dimPrev = new Date(y, m, 0).getDate();
        const tY = today.getFullYear(), tM = today.getMonth(), tD = today.getDate();
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const n = i - first + 1;
            if (n < 1)
                cells.push({ day: dimPrev + n, other: true, today: false });
            else if (n > dim)
                cells.push({ day: n - dim, other: true, today: false });
            else
                cells.push({ day: n, other: false, today: (y === tY && m === tM && n === tD) });
        }
        return cells;
    }
    readonly property var calCells: buildCells(calYear, calMonth, clock.now)
    function shiftMonth(d) {
        let m = calMonth + d, y = calYear;
        if (m < 0) {
            m = 11;
            y--;
        } else if (m > 11) {
            m = 0;
            y++;
        }
        calMonth = m;
        calYear = y;
    }
    function resetMonth() {
        const n = new Date();
        calYear = n.getFullYear();
        calMonth = n.getMonth();
    }

    Popout {
        id: calPop
        anchorItem: root
        popWidth: 232
        onShownChanged: if (shown)
            root.resetMonth()

        // header: ‹ Month Year ›
        Item {
            width: parent.width
            height: 24
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: prevMa.containsMouse ? Theme.accent : Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize + 4
                MouseArea {
                    id: prevMa
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.shiftMonth(-1)
                }
            }
            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(new Date(root.calYear, root.calMonth, 1), "MMMM yyyy")
                color: Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize
                font.bold: true
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resetMonth()
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: nextMa.containsMouse ? Theme.accent : Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize + 4
                MouseArea {
                    id: nextMa
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.shiftMonth(1)
                }
            }
        }

        // weekday header
        Row {
            width: parent.width
            Repeater {
                model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                delegate: Text {
                    required property var modelData
                    width: (calPop.popWidth - Theme.pad * 2) / 7
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }

        // day grid
        Grid {
            width: parent.width
            columns: 7
            Repeater {
                model: root.calCells
                delegate: Item {
                    required property var modelData
                    width: (calPop.popWidth - Theme.pad * 2) / 7
                    height: width - 4
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.height - 4
                        height: width
                        radius: width / 2
                        color: modelData.today ? Theme.accent : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.today ? Theme.bg : (modelData.other ? Theme.subtext : Theme.fg)
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: modelData.today
                    }
                }
            }
        }
    }
}
