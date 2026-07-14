import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import ".."

// Default-sink volume. Icon reflects level/mute; scroll = volume, click = slide-out mixer with
// sliders for system output, mic, and each playing app stream. PwObjectTracker keeps every
// displayed node subscribed so volume/muted stay reactive.
Item {
    id: root
    implicitWidth: icon.implicitWidth + 14
    implicitHeight: Theme.barIcon + 6

    // right-click launches the audio management app (disowned)
    property string manageCmd: "pavucontrol"

    readonly property var sink: Pipewire.defaultAudioSink
    // default source, else first available source (some setups never set a default)
    readonly property var mic: Pipewire.defaultAudioSource
        ?? [...Pipewire.nodes.values].find(n => n.type === PwNodeType.AudioSource)
        ?? null
    readonly property var au: sink && sink.audio ? sink.audio : null
    readonly property real vol: au ? au.volume : 0
    readonly property bool muted: au ? au.muted : false

    // app playback streams (media players, browsers, games…)
    readonly property var streams: [...Pipewire.nodes.values].filter(n => n.type === PwNodeType.AudioOutStream)

    // subscribe every displayed node so audio props update live
    PwObjectTracker {
        objects: [root.sink, root.mic, ...root.streams].filter(Boolean)
    }

    function setVol(v) {
        if (root.au)
            root.au.volume = Math.max(0, Math.min(1, v));
    }
    function toggleMute() {
        if (root.au)
            root.au.muted = !root.au.muted;
    }

    Text {
        id: icon
        anchors.centerIn: parent
        text: root.muted ? "" : (root.vol < 0.01 ? "" : (root.vol < 0.5 ? "" : ""))
        color: root.muted ? Theme.subtext : Theme.fg
        font.family: Theme.fontUi
        font.pixelSize: Theme.barIcon
        scale: ma.containsMouse ? 1.15 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Theme.animFast
                easing.type: Theme.easing
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: Theme.animFast
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onEntered: if (!pop.shown) {
            tip.text = root.muted ? "Muted" : "Volume " + Math.round(root.vol * 100) + "%";
            tip.open();
        }
        onExited: tip.close()
        onClicked: mouse => {
            tip.close();
            if (mouse.button === Qt.MiddleButton)
                root.toggleMute();
            else if (mouse.button === Qt.RightButton)
                Quickshell.execDetached(["sh", "-lc", root.manageCmd]);
            else
                pop.toggle();
        }
        onWheel: wheel => root.setVol(root.vol + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
    }

    Tooltip {
        id: tip
        anchorItem: root
    }

    // one mixer row: mute-toggle icon + label + percent, horizontal slider underneath
    component VolRow: Column {
        id: row
        required property var node
        property string label: ""
        property string glyph: ""
        property string glyphMuted: ""
        readonly property var rau: node && node.audio ? node.audio : null
        readonly property real rvol: rau ? rau.volume : 0
        readonly property bool rmuted: rau ? rau.muted : false
        spacing: 4

        function set(v) {
            if (row.rau)
                row.rau.volume = Math.max(0, Math.min(1, v));
        }

        Item {
            width: parent.width
            height: rowLabel.implicitHeight
            Text {
                id: rowIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: row.rmuted ? row.glyphMuted : row.glyph
                color: row.rmuted ? Theme.subtext : Theme.accent
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (row.rau)
                        row.rau.muted = !row.rau.muted
                }
            }
            Text {
                id: rowLabel
                anchors.left: rowIcon.right
                anchors.leftMargin: 8
                anchors.right: rowPct.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.label
                color: Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.fontSize - 1
                elide: Text.ElideRight
            }
            Text {
                id: rowPct
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: row.rmuted ? "muted" : Math.round(row.rvol * 100) + "%"
                color: row.rmuted ? Theme.subtext : Theme.subtext
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 2
            }
        }

        // horizontal slider (drag anywhere on the track)
        Item {
            width: parent.width
            height: 16
            Rectangle {
                id: rowTrack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.15)

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * row.rvol
                    height: parent.height
                    radius: parent.radius
                    color: row.rmuted ? Theme.subtext : Theme.accent
                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }
                }
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    color: row.rmuted ? Theme.subtext : Theme.accent
                    border.color: Theme.bg
                    border.width: 2.5
                    anchors.verticalCenter: parent.verticalCenter
                    x: (parent.width - width) * row.rvol
                    Behavior on x {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                onPressed: mouse => row.set((mouse.x + 4) / rowTrack.width)
                onPositionChanged: mouse => row.set((mouse.x + 4) / rowTrack.width)
                onWheel: wheel => row.set(row.rvol + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
            }
        }
    }

    component SectionLabel: Text {
        color: Theme.subtext
        font.family: Theme.fontMono
        font.pixelSize: Theme.fontSize - 3
        font.bold: true
    }

    Popout {
        id: pop
        anchorItem: root
        popWidth: 300

        // ---- system output ----
        SectionLabel {
            text: "OUTPUT"
        }
        VolRow {
            width: parent.width
            node: root.sink
            label: root.sink ? (root.sink.description || root.sink.nickname || root.sink.name) : "No sink"
            glyph: ""
            glyphMuted: ""
        }

        // ---- mic ----
        SectionLabel {
            text: "MIC"
        }
        VolRow {
            visible: !!root.mic
            width: parent.width
            node: root.mic
            label: root.mic ? (root.mic.description || root.mic.nickname || root.mic.name) : "No mic"
            glyph: ""
            glyphMuted: ""
        }
        Text {
            visible: !root.mic
            text: "No mic"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 1
        }

        // ---- per-app media streams ----
        SectionLabel {
            text: "APPS"
        }
        Repeater {
            model: root.streams
            delegate: VolRow {
                required property var modelData
                width: parent.width
                node: modelData
                label: {
                    const p = modelData.properties || {};
                    return p["application.name"] || p["media.name"] || modelData.nickname || modelData.name || "stream";
                }
                glyph: ""
                glyphMuted: ""
            }
        }
        Text {
            visible: root.streams.length === 0
            text: "Nothing playing"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSize - 1
        }
    }
}
