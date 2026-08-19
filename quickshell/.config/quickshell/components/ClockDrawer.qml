import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"

// Clock drawer: the time/ambient surface, hung off the bar clock the way the notification
// drawer hangs off the bell. Weather, world clocks and a month calendar, in that order.
//
// A view over the Clocks and Weather singletons and nothing else — no state lives in this file,
// the same split NotificationDrawer keeps.
//
// SHAPE. A full-height slab against the right edge, matching the notification drawer rather
// than dropping out from under the clock. Two reasons: the clock is the last module in the bar,
// so the right edge IS under it; and a widget column wants height, which a popout hanging off a
// 40px bar does not have. It has its OWN layer namespace (quickshell-clock-drawer) and its own
// blur rule in hypr/lua/windowrules.lua — a near-transparent surface with no rule behind it is
// not glass, it is an unreadable tint.
PanelWindow {
    id: win

    visible: Clocks.shown
    color: "transparent"
    screen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.screen ? Hyprland.focusedMonitor.screen : null

    // ExclusionMode.Ignore means the bar does not push this window off its strip, so a
    // full-height panel steps around it by hand — the notification drawer's barInset, for the
    // same reason and with the same hub-height overshoot.
    readonly property int barInset: Shell.barVisible ? Theme.barHeightHub : 0
    readonly property int topInset: Shell.barDevMode ? 0 : win.barInset
    readonly property int bottomInset: Shell.barDevMode ? win.barInset : 0

    readonly property int panelWidth: 420

    // Glass, at the same values as the notification drawer and the submap hints — but as its
    // OWN constants, deliberately not read from NotifyConfig.drawer. Sharing that value once
    // meant tuning one surface silently restyled an unrelated one (see Shell.submapHintsOpacity).
    //
    // Slab alpha is not a legibility control: it is a Rectangle fill and the cards above carry
    // their own opacity, so raising it only stacks tint between you and the desktop. The layer
    // rule's ignore_alpha (0.15) sits deliberately ABOVE this, so the slab itself is unblurred
    // and only the cards, shimmer and text sit over a sharp background.
    readonly property real slabOpacity: 0.05
    readonly property real cardOpacity: 0.82

    WlrLayershell.layer: WlrLayer.Overlay
    // The drawer is something the user deliberately opened — focus follows intent (AD-011), the
    // same rule that lets the notification drawer take the keyboard.
    WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-clock-drawer"
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    onVisibleChanged: if (visible)
        keys.forceActiveFocus()

    // click-away
    MouseArea {
        anchors.fill: parent
        onClicked: Clocks.close()
    }

    // h/l (and the arrows) browse months, t returns to today, r refetches the weather, Esc
    // closes. No j/k: nothing here is a list, and binding them to something else would break
    // the habit the other two keyboard surfaces build.
    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                Clocks.close();
            else if (event.key === Qt.Key_H || event.key === Qt.Key_Left)
                Clocks.shiftMonth(-1);
            else if (event.key === Qt.Key_L || event.key === Qt.Key_Right)
                Clocks.shiftMonth(1);
            else if (event.key === Qt.Key_T)
                Clocks.resetMonth();
            else if (event.key === Qt.Key_R)
                Weather.refresh();
            else
                return;
            event.accepted = true;
        }
    }

    Elevation {
        target: panel
        level: 1.4
        opacity: panel.opacity
    }

    Rectangle {
        id: panel

        width: win.panelWidth
        height: win.height - win.topInset - win.bottomInset
        x: win.width - width * panel.reveal
        y: win.topInset
        color: Theme.glass(win.slabOpacity)

        // 0 = off screen right, 1 = fully out — the panel slides, as the notification panel does
        property real reveal: win.visible ? 1 : 0
        Behavior on reveal {
            NumberAnimation {
                duration: Theme.animMed
                easing.type: Theme.easing
            }
        }

        // cursor-lit glass, same as the bar sections and the launcher
        Shimmer {
            anchors.fill: parent
            z: 10
        }

        Flickable {
            id: scroll
            anchors.fill: parent
            anchors.margins: Theme.pad
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // Widgets are a plain column of cards, so a fourth one is an insertion rather than a
            // rewrite — the story asks for that explicitly. The Flickable is what makes it true:
            // a fourth card on a short monitor scrolls instead of being clipped away.
            Column {
                id: column
                width: scroll.width
                spacing: Theme.pad

                // ---- header ----------------------------------------------------------------
                Item {
                    width: parent.width
                    height: 26

                    Text {
                        id: header
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(Clocks.now, "HH:mm:ss")
                        color: Theme.fg
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSize + 4
                        font.bold: true
                    }

                    Text {
                        anchors.left: header.right
                        anchors.leftMargin: 8
                        anchors.baseline: header.baseline
                        text: Qt.formatDate(Clocks.now, "dddd d MMMM yyyy")
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                // ---- weather ---------------------------------------------------------------
                Rectangle {
                    id: weatherCard
                    width: parent.width
                    height: weatherBody.implicitHeight + Theme.pad * 2
                    radius: Theme.radius
                    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, win.cardOpacity)

                    Column {
                        id: weatherBody
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: 8

                        // title row: where, and how old the reading is
                        Item {
                            width: parent.width
                            height: 18

                            Text {
                                id: weatherTitle
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: Weather.label.length ? Weather.label : "Weather"
                                color: Theme.fg
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: true
                            }

                            // Provenance, not decoration: which backend answered and when. A
                            // number with no age on it is the thing that makes a stale reading
                            // dangerous rather than merely old.
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    // Touch the ticking clock so the age re-evaluates while the
                                    // drawer is open — a binding on updatedAt alone would print
                                    // "0s ago" until the next fetch.
                                    Clocks.now;
                                    if (Weather.status === "loading" && !Weather.current)
                                        return "fetching…";
                                    if (!Weather.updatedAt)
                                        return Weather.provider;
                                    return Weather.provider + " · " + win.ago(Weather.updatedAt) + (Weather.stale ? " · stale" : "");
                                }
                                color: Weather.stale ? Theme.urgent : Theme.subtext
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }

                        // Current conditions. Rendered whenever there IS a reading, even while
                        // the last fetch is failing — the failure is reported on the line below
                        // rather than by blanking the panel.
                        Item {
                            width: parent.width
                            height: visible ? 48 : 0
                            visible: Weather.current !== null

                            Text {
                                id: wIcon
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: Weather.current ? Weather.current.icon : ""
                                color: Weather.stale ? Theme.subtext : Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: 34
                            }

                            Text {
                                id: wTemp
                                anchors.left: wIcon.right
                                anchors.leftMargin: 10
                                anchors.top: parent.top
                                anchors.topMargin: 2
                                text: Weather.current && !isNaN(Weather.current.temp) ? Math.round(Weather.current.temp) + Weather.readingTempUnit : "—"
                                color: Theme.fg
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize + 8
                            }

                            Text {
                                anchors.left: wIcon.right
                                anchors.leftMargin: 10
                                anchors.top: wTemp.bottom
                                text: Weather.current ? Weather.current.desc : ""
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fontSize - 2
                            }

                            Column {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    anchors.right: parent.right
                                    visible: Weather.current !== null && !isNaN(Weather.current.feelsLike)
                                    text: Weather.current ? "feels " + Math.round(Weather.current.feelsLike) + Weather.readingTempUnit : ""
                                    color: Theme.subtext
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSize - 3
                                }
                                Text {
                                    anchors.right: parent.right
                                    visible: Weather.current !== null && !isNaN(Weather.current.humidity)
                                    text: Weather.current ? Math.round(Weather.current.humidity) + "% humidity" : ""
                                    color: Theme.subtext
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSize - 3
                                }
                                Text {
                                    anchors.right: parent.right
                                    visible: Weather.current !== null && !isNaN(Weather.current.wind)
                                    text: Weather.current ? Math.round(Weather.current.wind) + " " + Weather.readingWindUnit : ""
                                    color: Theme.subtext
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                        }

                        // Forecast strip. One row of days, sized to the card so a 5- or 7-day
                        // forecast fits either way.
                        Row {
                            width: parent.width
                            visible: Weather.forecast.length > 0

                            Repeater {
                                model: Weather.forecast
                                delegate: Column {
                                    required property var modelData
                                    width: Weather.forecast.length > 0 ? weatherBody.width / Weather.forecast.length : 0
                                    spacing: 1

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.day
                                        color: Theme.subtext
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.fontSize - 4
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        color: Theme.accent
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.fontSize + 4
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: isNaN(modelData.hi) ? "—" : Math.round(modelData.hi) + "°"
                                        color: Theme.fg
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: isNaN(modelData.lo) ? "" : Math.round(modelData.lo) + "°"
                                        color: Theme.subtext
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSize - 4
                                    }
                                }
                            }
                        }

                        // The degraded state, and the whole reason it is a LINE rather than an
                        // empty panel: an unreachable network, a missing curl, an unconfigured
                        // machine and a bad entity id all land here saying which one it was.
                        // With a cached reading above, this annotates it; with none, it is the
                        // entire widget.
                        Column {
                            width: parent.width
                            visible: Weather.status === "error"
                            spacing: 1

                            // Two Texts, not one: the reason wraps to whatever length it needs
                            // (a curl message can be a sentence) and would otherwise orphan the
                            // hint onto a line of its own reading just "retry".
                            Text {
                                width: parent.width
                                text: "weather unavailable — " + Weather.error
                                wrapMode: Text.Wrap
                                color: Theme.urgent
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Text {
                                text: "[r] retry · click the card"
                                color: Theme.subtext
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Weather.refresh()
                    }
                }

                // ---- world clocks ----------------------------------------------------------
                Rectangle {
                    width: parent.width
                    height: zoneBody.implicitHeight + Theme.pad * 2
                    radius: Theme.radius
                    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, win.cardOpacity)

                    Column {
                        id: zoneBody
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: 4

                        Text {
                            text: "World clocks"
                            color: Theme.fg
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }

                        Repeater {
                            model: Clocks.zoneTimes
                            delegate: Item {
                                required property var modelData
                                width: zoneBody.width
                                height: 20

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 90
                                    text: modelData.label
                                    elide: Text.ElideRight
                                    color: Theme.fg
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.fontSize - 1
                                }
                                Text {
                                    id: zoneDay
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34
                                    horizontalAlignment: Text.AlignRight
                                    // The weekday is here because a zone list without one lies
                                    // by omission: "07:12" in Tokyo is tomorrow morning.
                                    text: modelData.day
                                    color: Theme.subtext
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSize - 3
                                }
                                Text {
                                    anchors.right: zoneDay.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.time
                                    color: Theme.accent
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSize - 1
                                }
                            }
                        }

                        Text {
                            visible: Clocks.zoneTimes.length === 0
                            text: "no zones configured"
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }

                // ---- calendar --------------------------------------------------------------
                Rectangle {
                    width: parent.width
                    height: calBody.implicitHeight + Theme.pad * 2
                    radius: Theme.radius
                    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, win.cardOpacity)

                    Column {
                        id: calBody
                        anchors.fill: parent
                        anchors.margins: Theme.pad
                        spacing: 4

                        // ‹ Month Year ›  — clicking the title returns to today, as [t] does
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
                                    onClicked: Clocks.shiftMonth(-1)
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: Qt.formatDate(new Date(Clocks.calYear, Clocks.calMonth, 1), "MMMM yyyy")
                                color: Theme.fg
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Clocks.resetMonth()
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
                                    onClicked: Clocks.shiftMonth(1)
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            Repeater {
                                model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                                delegate: Text {
                                    required property var modelData
                                    width: calBody.width / 7
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    color: Theme.subtext
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                        }

                        Grid {
                            width: parent.width
                            columns: 7
                            Repeater {
                                model: Clocks.calCells
                                delegate: Item {
                                    required property var modelData
                                    width: calBody.width / 7
                                    height: width - 6
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width, parent.height) - 4
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

                // key hints, the same shape the notification drawer's placeholder line uses
                Text {
                    width: parent.width
                    text: "[h/l] month · [t] today · [r] refresh weather · [Esc] close"
                    color: Theme.subtext
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize - 4
                    elide: Text.ElideRight
                }
            }
        }
    }

    // "4m" / "2h" / "3d" — how old the reading is, in the units the notification drawer's
    // timestamps already use.
    function ago(ms) {
        const s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (s < 60)
            return s + "s ago";
        if (s < 3600)
            return Math.floor(s / 60) + "m ago";
        if (s < 86400)
            return Math.floor(s / 3600) + "h ago";
        return Math.floor(s / 86400) + "d ago";
    }
}
