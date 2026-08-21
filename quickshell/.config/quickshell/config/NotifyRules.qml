pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Lua rules engine host (story: notif-lua-rules).
//
// The rules themselves run in `rules/engine.lua` as a long-lived SUBPROCESS. Quickshell
// 0.3.0 has no Lua binding, and an in-process VM would put user code on the shell's own
// thread: a rule with a runaway loop would freeze the bar, the launcher and every popup,
// not just the notification it was evaluating. Out of process, the worst case is one
// missed deadline.
//
// The contract this file exists to keep: **a notification is never lost to the rules
// engine.** No rules file, a syntax error, a throwing predicate, a hung interpreter, no
// `lua` on the machine at all — every one of those paths ends with the notification shown
// using the defaults it already had.
Singleton {
    id: root

    readonly property var config: NotifyConfig.rules

    // Env first (so a harness or a nested session can point at its own rules), then the
    // config value, then the conventional path. Same seam as QS_NOTIFY_CONFIG / QS_NOTIFY_DB.
    readonly property string rulesPath: {
        const explicit = Quickshell.env("QS_NOTIFY_RULES");
        if (explicit)
            return explicit;
        if (root.config.path)
            return root.config.path;
        const conf = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return conf + "/quickshell/notifications.lua";
    }

    // The engine ships with the shell, so it is found relative to this file rather than
    // through any user-configurable path — a rules engine you can point somewhere else is
    // just a second way to run arbitrary code.
    readonly property string enginePath: Qt.resolvedUrl("../rules/engine.lua").toString().replace(/^file:\/\//, "")

    readonly property bool enabled: root.config.enabled && root.interpreter !== ""
    readonly property int timeoutMs: root.config.timeoutMs > 0 ? root.config.timeoutMs : 50

    // luajit first: same language for our purposes, noticeably faster to start, and the
    // engine is written to the 5.1 subset both accept.
    property string interpreter: ""
    property bool healthy: true

    // ---------------------------------------------------------------------------------------
    // Evaluation
    //
    // Requests are answered in order (one interpreter, one loop), so the queue is a plain
    // FIFO and only the head can be timing out. `seq` is echoed by the engine and checked
    // here: applying one notification's answer to another would be worse than no rules.
    // ---------------------------------------------------------------------------------------

    property int seq: 0
    property var waiting: []

    // evaluate(notification, presentation, callback). The callback ALWAYS runs exactly once:
    // with the engine's presentation, or with null when the rules could not answer.
    function evaluate(n, presentation, callback) {
        if (!root.enabled || !proc.running) {
            callback(null);
            return;
        }
        root.seq++;
        const req = {
            seq: root.seq,
            callback: callback,
            deadline: Date.now() + root.timeoutMs
        };
        root.waiting.push(req);
        proc.write(JSON.stringify({
            seq: req.seq,
            n: n,
            p: presentation,
            s: root.state()
        }) + "\n");
        root.arm();
    }

    // What a predicate can ask about the shell, beyond the notification itself. `dnd` is the
    // real Do Not Disturb state (story: notif-dnd-core) — manual toggle OR scheduled quiet
    // hours. The shell already applies DND's own suppression default before this runs (see
    // NotifyDnd.applySuppression); a rule reading `s.dnd == true` is deciding an EXCEPTION,
    // not implementing DND itself.
    function state() {
        const mon = Hyprland.focusedMonitor;
        return {
            dnd: NotifyDnd.active,
            monitor: mon ? mon.name : "",
            workspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.name : "",
            fullscreen: Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.hasFullscreen || false) : false,
            visible: Notifications.visibleCount,
            hour: new Date().getHours()
        };
    }

    function arm() {
        if (root.waiting.length === 0) {
            deadline.stop();
            return;
        }
        deadline.interval = Math.max(1, root.waiting[0].deadline - Date.now());
        deadline.restart();
    }

    function deliver(seq, presentation, err) {
        if (err)
            console.warn("notifications: rule error —", err);
        for (var i = 0; i < root.waiting.length; i++) {
            if (root.waiting[i].seq !== seq)
                continue;
            const req = root.waiting[i];
            root.waiting.splice(i, 1);
            req.callback(presentation);
            root.arm();
            return;
        }
    }

    Timer {
        id: deadline
        repeat: false
        onTriggered: {
            const now = Date.now();
            const expired = [];
            const rest = [];
            for (const req of root.waiting)
                (req.deadline <= now ? expired : rest).push(req);
            root.waiting = rest;
            for (const req of expired)
                req.callback(null); // fail open: the notification shows with its defaults
            if (expired.length > 0) {
                // A missed deadline means the interpreter is wedged (an accidental `while
                // true` is the common case), and every later notification would queue
                // behind it. Restart rather than degrade quietly.
                console.warn("notifications: rules timed out after", root.timeoutMs, "ms — restarting the engine");
                root.restart();
            } else {
                root.arm();
            }
        }
    }

    // ---------------------------------------------------------------------------------------
    // The interpreter process
    // ---------------------------------------------------------------------------------------

    Process {
        id: which
        running: true
        command: ["sh", "-c", "command -v luajit || command -v lua || command -v lua5.4 || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.interpreter = this.text.trim().split("\n")[0] || "";
                if (root.interpreter === "" && root.config.enabled)
                    console.warn("notifications: no lua interpreter found — rules disabled, notifications unaffected");
            }
        }
    }

    Process {
        id: proc
        // A binding, not an imperative flag: `command` reads `interpreter`, which arrives
        // asynchronously from the `which` probe, and any path that set running = true before it
        // landed started an argv whose binary was the empty string ("Process failed to start").
        // Tying both to the same condition makes that ordering unrepresentable.
        running: root.enabled && root.interpreter !== "" && !root.restarting
        command: [root.interpreter, root.enginePath, root.rulesPath]
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (!line)
                    return;
                try {
                    const msg = JSON.parse(line);
                    root.deliver(msg.seq, msg.p || null, msg.err);
                } catch (e) {
                    console.warn("notifications: unreadable reply from the rules engine —", e);
                }
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line)
                    console.warn("notifications:", line);
            }
        }

        onExited: (code, status) => {
            // Everything still in flight loses its answer, so hand each one the fallback
            // rather than leaving a notification waiting on a process that is gone.
            const stranded = root.waiting;
            root.waiting = [];
            for (const req of stranded)
                req.callback(null);
            deadline.stop();
            if (root.enabled && code !== 0 && !root.restarting)
                console.warn("notifications: rules engine exited", code, "— notifications continue with defaults");
        }
    }

    // Set across a deliberate stop so onExited knows the difference between "we replaced it"
    // and "it died on us" — only the second is worth a line in the log.
    property bool restarting: false

    // Toggling `restarting` cycles the binding above: false stops the process, true lets it
    // start again with whatever rulesPath/interpreter now say.
    function restart() {
        root.restarting = true;
        root.restarting = false;
    }

    // Hot reload: the engine reads the rules file once at startup and has no reload path of
    // its own, deliberately — restarting a subprocess is atomic and cannot leave half of an
    // edited file loaded.
    FileView {
        path: root.rulesPath
        watchChanges: true
        // No rules file is the normal state on a machine that has not written one. Without this
        // every such shell logs a read error at startup, which trains people to ignore the log.
        printErrors: false
        onFileChanged: {
            console.info("notifications: rules changed, reloading");
            root.restart();
        }
        // A missing rules file is the normal state on a machine with no rules; it is not an
        // error and must not log like one.
        onLoadFailed: error => {}
    }

    onRulesPathChanged: if (root.enabled)
        root.restart()
}
