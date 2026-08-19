import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import "../../config"

// Now playing — MPRIS title + transport, floating in the gap between the window list and the
// workspace centre.
//
// Deliberately NOT inside a Section: Section.qml is what draws the slanted bar surface, and this
// is not a bar module. It is the mirror of NotificationPills on the other side of the centre —
// text and icons only, no Rectangle, no border, no Theme.surface fill.
//
// LEFT-aligned so it grows rightward into empty space. The centre section is anchored to the
// screen's horizontalCenter, so every pixel this takes has to be absorbed by ELIDING the title,
// never by pushing anything: the workspaces must sit on true screen centre at any title length.
Item {
    id: root

    //! Monitor this bar is on — compared against the pinned monitor (Shell.nowPlayingMonitor).
    property string screenName: ""

    // ---------------------------------------------------------------------------------------
    // Which monitor.
    //
    // Media is ONE stream, not per-screen state, so unlike Audio/Network/Clock this does not
    // belong on all four bars. It is pinned by monitor DESCRIPTION rather than connector name,
    // because connector names shuffle across reconnects (the same reason hypr/lua/monitors.lua
    // addresses displays by desc:). A bare connector name still works, so either form can go in
    // the config key.
    //
    // Two fallbacks, both toward showing rather than vanishing: unset config shows on every bar,
    // and a configured monitor that is not currently connected (undocked laptop) does too.
    // ---------------------------------------------------------------------------------------
    readonly property string wantMonitor: Shell.nowPlayingMonitor.trim()

    readonly property bool onThisMonitor: {
        if (root.wantMonitor === "")
            return true;
        const want = root.wantMonitor.toLowerCase();
        const ms = Hyprland.monitors ? Hyprland.monitors.values : [];
        let present = false;
        for (const m of ms) {
            const desc = (m.lastIpcObject && m.lastIpcObject.description) ? String(m.lastIpcObject.description) : "";
            if (m.name === root.wantMonitor || desc.toLowerCase().indexOf(want) !== -1) {
                present = true;
                if (m.name === root.screenName)
                    return true;
            }
        }
        return !present;
    }

    // ---------------------------------------------------------------------------------------
    // Which player.
    //
    // A browser tab and a music app are both registered most of the time, so this picks ONE and
    // never stacks. Preference is whatever is actually Playing; with nothing playing it holds on
    // to the player it was already showing, which is what makes the pause grace period below
    // show the track you just paused rather than some other app's stale metadata.
    // ---------------------------------------------------------------------------------------
    readonly property var players: Mpris.players ? Mpris.players.values : []
    property var player: null

    function pickPlayer() {
        const ps = root.players;
        if (ps.length === 0) {
            root.player = null;
            return;
        }
        const held = root.player && ps.indexOf(root.player) !== -1 ? root.player : null;
        if (held && held.playbackState === MprisPlaybackState.Playing)
            return;
        for (const p of ps) {
            if (p.playbackState === MprisPlaybackState.Playing) {
                root.player = p;
                return;
            }
        }
        root.player = held ? held : ps[0];
    }

    onPlayersChanged: root.pickPlayer()
    Component.onCompleted: root.pickPlayer()

    // Reconsider when any player starts or stops. Mpris.players only changes when a player
    // appears or disappears, so without this the pick is frozen at whatever was playing when the
    // set last changed — switching from the browser to the music app would never register.
    Instantiator {
        model: root.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPlaybackStateChanged() {
                root.pickPlayer();
            }
        }
    }

    readonly property bool playing: !!root.player && root.player.playbackState === MprisPlaybackState.Playing
    readonly property string title: root.player ? (root.player.trackTitle || "") : ""
    // One read, not a `trackArtist || trackArtists` pair: on stable 0.3.0 both are QString off the
    // same bindable, so the fallback was dead code dressed up as a compatibility shim.
    readonly property string artist: root.player ? (root.player.trackArtist || "") : ""

    // ---------------------------------------------------------------------------------------
    // Visibility: playing, plus a grace period.
    //
    // Hiding the instant a track is paused makes the bar jump every time you pause to say
    // something and resume ten seconds later, so a pause starts a timer instead and a resume
    // cancels it. The player disappearing entirely hides immediately — there is nothing left to
    // describe.
    //
    // The grace belongs to ONE player — the one that was actually playing — and `graceOwner`
    // is what enforces that. Without it, quitting a playing Spotify while a paused browser
    // player is still registered promoted the browser (`pickPlayer` falls through to ps[0]),
    // saw `playing` go true -> false, and started a full 45s grace over the browser's stale
    // paused metadata: the spec's "hide when the player disappears" turned into "advertise
    // someone else's old track for 45 seconds".
    //
    // The owner is the player's `dbusName`, which is the only stable identity available here.
    // NOT `uniqueId`: that is per-TRACK, not per-player — the rig caught it changing 1 -> 4 on
    // one player when the title changed, so a perfectly ordinary pause looked like a stranger
    // asking for a grace it had not earned, and the paused track vanished instantly. Not the
    // object either: the player that armed the grace may already be destroyed when this is
    // compared, and a string outlives it.
    // ---------------------------------------------------------------------------------------
    property bool inGrace: false
    property string graceOwner: ""

    Timer {
        id: graceTimer
        interval: Shell.nowPlayingTimeoutMs
        onTriggered: root.inGrace = false
    }

    // Arm the grace for the current player, or drop it if this is not the player that earned one.
    function refreshGrace() {
        const p = root.player;
        if (!p) {
            graceTimer.stop();
            root.inGrace = false;
            root.graceOwner = "";
            return;
        }
        // Read the state off the PLAYER, never off root.playing. When the selection changes,
        // onPlayerChanged can run before the `playing` binding has re-evaluated, and that stale
        // `true` is precisely how the browser inherited the grace: it took the "is playing"
        // branch, stamped ITSELF as graceOwner, and the pause that followed then looked like the
        // owner pausing. Verified — the first version of this fix still showed the stale tab.
        const isPlaying = p.playbackState === MprisPlaybackState.Playing;
        if (isPlaying) {
            graceTimer.stop();
            root.inGrace = true;
            root.graceOwner = p.dbusName;
            return;
        }
        if (p.dbusName === root.graceOwner) {
            // the track you just paused — hold it on the bar for the timeout
            if (!graceTimer.running)
                graceTimer.restart();
            return;
        }
        // a player that never played under us: no grace, hide now
        graceTimer.stop();
        root.inGrace = false;
    }

    onPlayingChanged: root.refreshGrace()
    onPlayerChanged: root.refreshGrace()

    // ---------------------------------------------------------------------------------------
    // Fitting the gap.
    //
    // Widths are derived from root.width — the gap between the two sections, which this item is
    // anchored across — and NEVER from the laid-out row, because feeding a measured row back
    // into the properties that size that row is a binding loop (the same rule NotificationPills
    // documents). showPrev therefore tests the space available WITHOUT it.
    //
    // Previous is the first thing dropped when the gap is tight, per the spec: better to lose a
    // control than to elide the title to nothing. Below minTitle the whole cluster goes — that
    // is also the answer for a PORTRAIT bar, where the gap is a few hundred pixels: it falls out
    // of the width test rather than needing a portrait flag.
    // ---------------------------------------------------------------------------------------
    readonly property int gutter: 6
    readonly property int ctlWidth: Theme.barIcon + 10
    readonly property int iconWidth: Theme.barIcon + 2
    readonly property int minTitle: 56

    readonly property bool canToggle: !!root.player && root.player.canTogglePlaying
    readonly property bool canNext: !!root.player && root.player.canGoNext

    readonly property int fixedWidth: root.iconWidth + root.gutter + (root.canToggle ? root.ctlWidth + root.gutter : 0) + (root.canNext ? root.ctlWidth + root.gutter : 0)

    readonly property int spaceNoPrev: Math.max(0, root.width - root.fixedWidth)
    readonly property bool showPrev: !!root.player && root.player.canGoPrevious && (root.spaceNoPrev - root.ctlWidth - root.gutter >= root.minTitle)
    readonly property int titleSpace: Math.max(0, root.spaceNoPrev - (root.showPrev ? root.ctlWidth + root.gutter : 0))

    // DELIBERATE DEVIATION from the spec's "visible when a player exists and is playing": a
    // playing player with no title renders NOTHING, not a bare note and two buttons. A title-less
    // cluster cannot say what it is offering to control, and a transport with no subject reads as
    // a bar glitch. The cost, stated plainly: a stream whose metadata never arrives is invisible
    // here even though it is audible.
    readonly property bool wanted: Shell.nowPlayingEnabled && root.onThisMonitor && !!root.player && (root.playing || root.inGrace) && root.title !== "" && root.titleSpace >= root.minTitle

    implicitHeight: Theme.barHeightMinimal - 8

    opacity: root.wanted ? 1 : 0
    // Never let a faded-out cluster keep eating clicks over empty bar
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.animFast
            easing.type: Theme.easing
        }
    }

    // one transport control — hidden, not greyed, when the player does not advertise it. Many
    // players advertise a subset, and an unsupported control is a silent no-op that still
    // renders as an enabled-looking button.
    component Ctl: Item {
        id: ctl
        property string glyph: ""
        property bool available: true
        signal activated

        visible: ctl.available
        // Fixed, for the same reason the artist's width is: a Row lays out no invisible child,
        // so a width that switches on visibility buys nothing and can latch at zero.
        width: root.ctlWidth
        height: root.implicitHeight

        Text {
            id: ctlGlyph
            anchors.centerIn: parent
            text: ctl.glyph
            color: ctlArea.containsMouse ? Theme.accent : Theme.fg
            font.family: Theme.fontUi
            font.pixelSize: Theme.barIcon - 3
            scale: ctlArea.containsMouse ? 1.15 : 1
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
            id: ctlArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ctl.activated()
        }
    }

    Row {
        id: row
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gutter

        Text {
            id: stateIcon
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconWidth
            horizontalAlignment: Text.AlignHCenter
            // The note is constant and the COLOUR carries the state: during the grace period
            // the cluster still describes the same track, it has just stopped moving. Swapping
            // the glyph here would compete with the play/pause button a few pixels to the right.
            text: ""
            color: root.playing ? Theme.accent : Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: Theme.barIcon
            Behavior on color {
                ColorAnimation {
                    duration: Theme.animFast
                }
            }
        }

        // Title + artist share one wrapper so the hover/click area has something to anchor to:
        // a MouseArea parented to root cannot anchor to items inside this Row, which are its
        // nieces rather than its siblings ("Cannot anchor to an item that isn't a parent or
        // sibling" — silently no-ops the anchors and leaves the area at zero size).
        Item {
            id: textGroup
            anchors.verticalCenter: parent.verticalCenter
            width: textRow.implicitWidth
            height: root.implicitHeight

            Row {
                id: textRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.gutter

                Text {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, root.titleSpace)
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 1
                }

                Text {
                    id: artistText
                    anchors.verticalCenter: parent.verticalCenter
                    // Secondary and strictly optional — the title alone is the requirement, so
                    // the artist appears only out of what the title did not use.
                    readonly property int room: root.titleSpace - titleText.width - root.gutter
                    visible: root.artist !== "" && room >= 60
                    // NOT `visible ? Math.min(implicitWidth, room) : 0`. That binding is first
                    // evaluated while visible is still false, short-circuits before it ever
                    // reads implicitWidth, and then stays latched at 0 — the artist was
                    // permanently invisible with visible == true and width == 0, no warning
                    // anywhere. A Row skips invisible children outright, so the width does not
                    // need to know about visibility in the first place.
                    width: Math.min(implicitWidth, Math.max(0, room))
                    text: root.artist
                    elide: Text.ElideRight
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            // Hover for the full metadata the elision dropped; click raises the player's window
            // when it has one (canRaise is false for mpd/playerctld, which have none). Scroll is
            // deliberately unbound: it means volume on Audio.qml, and one gesture meaning two
            // different volumes a few hundred pixels apart is worse than no gesture at all.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: (root.player && root.player.canRaise) ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: {
                    if (!root.player)
                        return;
                    const bits = [root.title];
                    if (root.artist)
                        bits.push(root.artist);
                    if (root.player.trackAlbum)
                        bits.push(root.player.trackAlbum);
                    tip.text = bits.join(" — ") + (root.player.identity ? "  (" + root.player.identity + ")" : "");
                    tip.open();
                }
                onExited: tip.close()
                onClicked: {
                    tip.close();
                    if (root.player && root.player.canRaise)
                        root.player.raise();
                }
            }
        }

        Ctl {
            anchors.verticalCenter: parent.verticalCenter
            glyph: ""
            available: root.showPrev
            onActivated: if (root.player)
                root.player.previous()
        }

        Ctl {
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.playing ? "" : ""
            available: root.canToggle
            onActivated: if (root.player)
                root.player.togglePlaying()
        }

        Ctl {
            anchors.verticalCenter: parent.verticalCenter
            glyph: ""
            available: root.canNext
            onActivated: if (root.player)
                root.player.next()
        }
    }

    Tooltip {
        id: tip
        anchorItem: titleText
    }
}
