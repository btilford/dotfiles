pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// VPN state for the bar's Network widget (and any future consumer). Mullvad is the
// primary backend: one availability probe (`mullvad status -j`), then a long-running
// `mullvad status -j listen` push stream (2026.3 CLI: the -j flag goes BEFORE the
// subcommand), restarted with backoff when it exits (daemon restarts). Quickshell
// 0.3.0's Networking module can't see tun/wireguard devices (DeviceType is only
// None|Wifi|Wired), so a generic fallback polls `ip -j link` for wg/tun/tailscale
// interfaces; mullvad wins outright whenever it reports non-disconnected, and
// mullvad-owned interfaces are excluded from the generic match so `wg0-mullvad`
// is never double-counted.
//
// Note: the exposed state property is named `status`, not `state` — see the
// property-shadowing lesson in quickshell/CLAUDE.md (ClipboardDialog lockout).
Singleton {
    id: root

    //! connected | connecting | disconnected | disconnecting | error
    readonly property string status: {
        if (mullvadAvailable && _mvStatus !== "disconnected")
            return _mvStatus;
        if (_genIface.length)
            return "connected";
        return mullvadAvailable ? _mvStatus : "disconnected";
    }
    //! which backend the current status came from: mullvad | generic | none
    readonly property string backend: {
        if (mullvadAvailable && _mvStatus !== "disconnected")
            return "mullvad";
        if (_genIface.length)
            return "generic";
        return mullvadAvailable ? "mullvad" : "none";
    }
    //! relay hostname (mullvad) or interface name (generic)
    readonly property string relay: backend === "mullvad" ? _mvRelay : (backend === "generic" ? _genIface : "")
    //! "City, Country" (mullvad only)
    readonly property string location: backend === "mullvad" ? _mvLocation : ""
    //! mullvad lockdown mode: disconnected + lockedDown = network is blocked
    property bool lockedDown: false
    property bool mullvadAvailable: false

    readonly property bool connected: status === "connected"
    readonly property bool busy: status === "connecting" || status === "disconnecting"

    function connectVpn() {
        if (mullvadAvailable)
            Quickshell.execDetached(["mullvad", "connect"]);
    }
    function disconnectVpn() {
        if (mullvadAvailable)
            Quickshell.execDetached(["mullvad", "disconnect"]);
    }

    // --- mullvad backend ---
    property string _mvStatus: "disconnected"
    property string _mvRelay: ""
    property string _mvLocation: ""

    function _applyMullvad(line) {
        let st;
        try {
            st = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!st || !st.state)
            return;
        const loc = st.details && st.details.location ? st.details.location : null;
        root._mvStatus = st.state;
        root._mvRelay = loc && loc.hostname ? loc.hostname : "";
        root._mvLocation = loc ? [loc.city, loc.country].filter(x => x && x.length).join(", ") : "";
        root.lockedDown = st.details ? !!st.details.locked_down : false;
    }

    // availability probe + initial state; re-run after listener exits or while unavailable
    Process {
        id: probeProc
        command: ["mullvad", "status", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root._applyMullvad(this.text.trim())
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.mullvadAvailable = true;
                listenProc.running = true;
            } else {
                // CLI missing or daemon down — degrade to generic, re-probe slowly
                root.mullvadAvailable = false;
                root._mvStatus = "disconnected";
                reprobeTimer.start();
            }
        }
    }

    // push updates; `listen` emits the current state immediately, then one JSON line per change
    Process {
        id: listenProc
        command: ["mullvad", "status", "-j", "listen"]
        stdout: SplitParser {
            onRead: segment => root._applyMullvad(segment.trim())
        }
        onExited: restartTimer.start()
    }

    Timer {
        id: restartTimer
        interval: 5000
        onTriggered: probeProc.running = true
    }
    Timer {
        id: reprobeTimer
        interval: 30000
        onTriggered: probeProc.running = true
    }

    // --- generic fallback (wireguard/tun/tailscale up-interface poll) ---
    property string _genIface: ""

    Process {
        id: ipProc
        command: ["ip", "-j", "link", "show", "up"]
        stdout: StdioCollector {
            onStreamFinished: {
                let iface = "";
                try {
                    for (const l of JSON.parse(this.text)) {
                        const n = l.ifname || "";
                        // mullvad's own tunnel is already reported by the CLI
                        if (n.indexOf("mullvad") >= 0)
                            continue;
                        if (l.link_type === "none" || /^(wg|tun|tailscale)/.test(n)) {
                            iface = n;
                            break;
                        }
                    }
                } catch (e) {}
                root._genIface = iface;
            }
        }
    }
    Timer {
        interval: 12000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!ipProc.running) ipProc.running = true
    }

    Component.onCompleted: probeProc.running = true
}
