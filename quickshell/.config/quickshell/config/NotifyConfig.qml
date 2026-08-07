pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// User-facing notification configuration: placement, motion and timing.
//
// WHY A JSON FILE. The story requires that anchor, stack direction, entrance/exit animation and
// dwell target are changeable "with no QML edit". The rest of this dotfiles repo keeps desktop
// config in Lua, but that is Hyprland's config language — QML cannot read it without shelling out
// to a Lua interpreter or generating a second file, which puts a build step between the user and a
// preference. FileView + JSON is the mechanism this shell already uses for live-reloading config
// (Theme reads the wallust palette exactly this way), so it costs no new machinery and hot-reloads
// on save. See Projects/hyprland-dotfiles/decisions.md in the notes vault.
//
//   file:  ~/.config/quickshell/notifications.json   (see notifications.example.json)
//   env:   QS_NOTIFY_CONFIG=<path>    read this file instead — the path seam that lets a nested
//                                     session (visual-capture harness, `qs -p`, CI) configure the
//                                     shell without touching the live desktop's file
//          QS_NOTIFY_PRESET=<name>    override the preset, wins over the file
//
// EVERY value falls back to the constants below, key by key: a missing file, a truncated file,
// invalid JSON or one bad key never breaks the shell — it logs and keeps the default.
Singleton {
    id: root

    // ---------------------------------------------------------------------------------------
    // Fallback defaults. These are the shipped behaviour; the file only ever overrides them.
    // ---------------------------------------------------------------------------------------

    readonly property string defaultPreset: "right-center"

    readonly property var defaultPlacement: ({
            anchorH: "right",       // "left" | "center" | "right"
            anchorV: "center",      // "top"  | "center" | "bottom"
            stack: "down",          // "down" = newest nearest the top, "up" = newest at the bottom
            margin: 24,             // gap to the screen edge
            spacing: 12,            // gap between cards
            cardWidth: 420,
            maxVisible: 5,          // extras queue in the model behind a "+N more" indicator
            screenName: ""          // "" = whichever monitor has focus; else a monitor name
        })

    readonly property var defaultMotion: ({
            entrance: "slide",      // "slide" | "scale" | "fade" | "none"
            exit: "dwell",          // "dwell" (fly into the bar bell) | "slide" | "fade" | "none"
            entranceMs: 260,
            exitMs: 200,
            dwellMs: 460,           // flight time of the dwell into the bell
            reflowMs: 200           // cards closing the gap after one leaves
        })

    // Duration vocabulary, used by these three values, by a rule's `presentation.durationMs`, and
    // by the entry's own durationMs — one meaning everywhere:
    //     > 0   show for that many milliseconds
    //       0   sticky: stays until dismissed (matches expire_timeout = 0 on the wire)
    //     < 0   drawer-only: recorded and counted unread, never popped
    readonly property var defaultTiming: ({
            low: 3000,
            normal: 6000,
            critical: 0,            // sticky, then collapses to a pill (criticalCollapseMs)
            respectAppTimeout: true,
            hoverPause: true,       // pointer over a card freezes its countdown
            showRemaining: true,    // ...and the card shows how much of it is left
            // Burst relief: once a stack is this full, further non-critical cards are capped at
            // burstMs so the stack drains instead of growing. 0 = use placement.maxVisible.
            burstAt: 0,
            burstMs: 2500,          // 0 disables burst shortening entirely
            // A sticky card shrinks to an icon pill this long after it appears, staying on screen
            // without occupying it. One click expands it again. 0 = never collapse.
            criticalCollapseMs: 15000
        })

    // SQLite history (config/NotifyStore.qml). Retention is age AND count: whichever bites first.
    readonly property var defaultStore: ({
            enabled: true,
            retentionDays: 30,
            retentionCount: 2000
        })

    // Lua rules engine (config/NotifyRules.qml + rules/engine.lua). `path` empty = the
    // conventional ~/.config/quickshell/notifications.lua; QS_NOTIFY_RULES wins over both.
    // timeoutMs is the fail-open budget: past it the notification is shown with its defaults
    // and the interpreter is restarted.
    readonly property var defaultRules: ({
            enabled: true,
            path: "",
            timeoutMs: 50
        })

    // Drawer (components/NotificationDrawer.qml). `mode` is a display choice over the same
    // data: "panel" slides out from the right edge full height, "modal" is centred and
    // launcher-shaped. `limit` is how many stored rows one page of the drawer pulls.
    readonly property var defaultDrawer: ({
            mode: "panel",
            width: 460,
            limit: 200,
            // The slab is glass: very translucent, and blurred by the compositor
            // (hypr/lua/windowrules.lua layer rule on the quickshell-notification-drawer
            // namespace). The ROWS are much more opaque — the background is atmosphere, the
            // notifications are the content, and content has to stay readable over a terminal.
            //
            // 0.05, down from 0.35, matching the submap hints. Slab alpha is not a legibility
            // control: it is a Rectangle fill and the rows above it carry their own itemOpacity,
            // so raising it never made content more readable — it only stacked more tint between
            // you and the desktop until the panel stopped reading as glass. See
            // Shell.submapHintsOpacity, where the same mistake is written up at length.
            opacity: 0.05,
            itemOpacity: 0.82
        })

    // Custom actions — a flat list read like the hyprland keybind table:
    // matcher -> label -> key -> what it does. Settled in AD-012; see
    // Projects/hyprland-dotfiles/features/notification-actions-design.
    //
    // Matcher keys: app, category, urgency, summary, body, hint.<name>. All present keys
    // must match (AND). A `~` prefix makes the value a regex; anything else is an exact,
    // case-insensitive compare — the same vocabulary the Lua rules engine matches on, so
    // there is one thing to learn.
    //
    // `run` substitutions ({id} {app} {summary} {body} {input} {hint:NAME}) are passed as
    // ARGV ELEMENTS and never spliced into a shell string. A summary containing `; rm -rf`
    // is an argument, not a command. That is a security boundary, not a style choice.
    readonly property var defaultActions: []

    // A prompt is an inline field on the card. It appears on a client inline-reply hint, on
    // an allowlisted category, or when a matching custom action declares one.
    //
    // The allowlist is written down rather than left to per-rule taste: a prompt is offered
    // only where a text reply is the notification's natural response AND the reply has
    // somewhere to go. "Build failed" gets actions, not a prompt — there is no recipient.
    readonly property var defaultPrompt: ({
            categories: ["im.received", "email.arrived", "x-vault.reminder"],
            placeholder: "Reply\u2026"
        })

    // Snooze. `s` uses defaultMs; `r` opens the prompt in time mode ("20m", "17:30",
    // "tomorrow 9am"). maxMs bounds a parsed value rather than trusting it.
    readonly property var defaultSnooze: ({
            defaultMs: 900000,
            maxMs: 604800000
        })

    // Surface opacity for the popup cards and the docked pills. Separate from the drawer's
    // (which is deliberately glass — see defaultDrawer): a card sits over whatever you are
    // working in for a few seconds and has to be readable immediately, so it stays mostly
    // solid. Theme.surfaceOpacity remains the shell-wide default for everything else.
    readonly property var defaultSurface: ({
            cardOpacity: 0.8,
            pillOpacity: 0.85
        })

    // Where a collapsed sticky card goes (story: notif-timing folds it; this decides where the
    // pill lives). "bar" docks it in the bar between the workspaces and the status cluster,
    // floating, with no bar background of its own; "stack" leaves it in the popup stack where it
    // still costs a slot. maxPills caps the tray — past it, one "+N" chip opens the drawer.
    readonly property var defaultCollapse: ({
            home: "bar",
            maxPills: 3
        })

    // Named presets exist so the two candidate layouts can be swapped with one word and compared
    // from real captures rather than taste (that comparison IS this story).
    readonly property var presets: ({
            "right-center": {
                anchorH: "right",
                anchorV: "center",
                stack: "down"
            },
            "bottom-center": {
                anchorH: "center",
                anchorV: "bottom",
                stack: "up"
            },
            "top-right": {
                anchorH: "right",
                anchorV: "top",
                stack: "down"
            }
        })

    // ---------------------------------------------------------------------------------------
    // Resolved config. Plain JS objects, replaced wholesale on reload so bindings re-evaluate.
    // ---------------------------------------------------------------------------------------

    property string preset: root.defaultPreset
    property var placement: root.clone(root.defaultPlacement)
    property var motion: root.clone(root.defaultMotion)
    property var timing: root.clone(root.defaultTiming)
    property var store: root.clone(root.defaultStore)
    property var rules: root.clone(root.defaultRules)
    property var drawer: root.clone(root.defaultDrawer)
    property var collapse: root.clone(root.defaultCollapse)
    property var surface: root.clone(root.defaultSurface)
    // a LIST, not an object — cloned per reload so bindings re-evaluate
    property var actions: root.defaultActions.slice()
    property var prompt: root.clone(root.defaultPrompt)
    property var snooze: root.clone(root.defaultSnooze)

    readonly property string configPath: root.envOr("QS_NOTIFY_CONFIG", Quickshell.env("HOME") + "/.config/quickshell/notifications.json")

    // TOML is preferred and JSON is the fallback, in that order.
    //
    // JSON was chosen originally because QML parses it natively and reading anything else meant
    // a build step between the user and a preference. That reasoning holds for a *build* step;
    // it does not hold for a converter run at LOAD, which is what this is. The file is still
    // edited directly and still hot-reloads on save.
    //
    // The cost of JSON was being paid in `_comment` keys — a config format that needs a
    // convention to fake comments is telling you something. TOML also matches every other
    // config in this repo (clipborg, mise, metapac, worktrunk), and AD-012 wrote its action
    // examples in TOML before any of this existed:
    //
    //     [[actions]]
    //     match = { app = "Slack" }
    //
    // `tomlq` (from the `yq` package) does the conversion. If it is missing the TOML file is
    // ignored with one log line and JSON/defaults still apply — a missing converter must not
    // take the shell's notifications with it.
    readonly property string tomlPath: root.envOr("QS_NOTIFY_CONFIG_TOML", Quickshell.env("HOME") + "/.config/quickshell/notifications.toml")
    // Layered on top of the base file, lowest precedence first:
    //   notifications.toml            the stowed/base config
    //   notifications.d/*.toml        drop-ins, lexical order
    //   notifications.local.toml      machine-local, always wins
    //
    // Same shape as clipborg's config.toml + config.local.toml and the repo's documented `.d/`
    // pattern — `*.local.toml` and `NN-local*` are already reserved in .gitignore and
    // .stow-local-ignore, so a local file cannot be committed by accident.
    readonly property string tomlDir: Quickshell.env("HOME") + "/.config/quickshell/notifications.d"
    readonly property string tomlLocalPath: Quickshell.env("HOME") + "/.config/quickshell/notifications.local.toml"
    // parsed TOML, or null when there is no usable TOML file
    property var tomlCfg: null

    // ---------------------------------------------------------------------------------------

    function clone(o) {
        return Object.assign({}, o);
    }

    function envOr(key: string, fallback: string): string {
        const v = Quickshell.env(key);
        return (v === undefined || v === null || v === "") ? fallback : v;
    }

    // Per-key validation. An unknown value is reported once and then ignored, because silently
    // accepting "botom" would move the popups nowhere with no explanation.
    function pickEnum(src, key, allowed, fallback) {
        const v = src ? src[key] : undefined;
        if (v === undefined)
            return fallback;
        if (allowed.indexOf(v) >= 0)
            return v;
        console.warn("notifications: config", key, "=", v, "is not one of", allowed.join("/"), "— keeping", fallback);
        return fallback;
    }

    function pickInt(src, key, fallback, min) {
        const v = src ? src[key] : undefined;
        if (v === undefined)
            return fallback;
        if (typeof v !== "number" || !isFinite(v) || v < min) {
            console.warn("notifications: config", key, "=", v, "is not a number >=", min, "— keeping", fallback);
            return fallback;
        }
        return Math.round(v);
    }

    function pickReal(src, key, fallback, min, max) {
        const v = src ? src[key] : undefined;
        if (v === undefined)
            return fallback;
        if (typeof v !== "number" || !isFinite(v) || v < min || v > max) {
            console.warn("notifications: config", key, "=", v, "is not a number in", min + "…" + max, "— keeping", fallback);
            return fallback;
        }
        return v;
    }

    function pickBool(src, key, fallback) {
        const v = src ? src[key] : undefined;
        return typeof v === "boolean" ? v : fallback;
    }

    function pickString(src, key, fallback) {
        const v = src ? src[key] : undefined;
        return typeof v === "string" ? v : fallback;
    }

    function rebuild() {
        let cfg = {};
        if (root.tomlCfg) {
            cfg = root.tomlCfg;
        } else {
            try {
                const t = configFile.text();
                if (t && t.trim().length)
                    cfg = JSON.parse(t);
            } catch (e) {
                console.warn("notifications: config file unreadable, using defaults —", e);
                cfg = {};
            }
        }
        if (!cfg || typeof cfg !== "object")
            cfg = {};

        // preset first, then explicit keys on top of it: a file can pick "bottom-center" and
        // still nudge one value without restating the whole block.
        const name = root.envOr("QS_NOTIFY_PRESET", root.pickString(cfg, "preset", root.defaultPreset));
        const presetVals = root.presets[name];
        if (!presetVals)
            console.warn("notifications: unknown preset", name, "— using", root.defaultPreset);
        root.preset = presetVals ? name : root.defaultPreset;

        const base = Object.assign(root.clone(root.defaultPlacement), presetVals || root.presets[root.defaultPreset]);
        const p = cfg.placement;
        root.placement = {
            anchorH: root.pickEnum(p, "anchorH", ["left", "center", "right"], base.anchorH),
            anchorV: root.pickEnum(p, "anchorV", ["top", "center", "bottom"], base.anchorV),
            stack: root.pickEnum(p, "stack", ["up", "down"], base.stack),
            margin: root.pickInt(p, "margin", base.margin, 0),
            spacing: root.pickInt(p, "spacing", base.spacing, 0),
            cardWidth: root.pickInt(p, "cardWidth", base.cardWidth, 120),
            maxVisible: root.pickInt(p, "maxVisible", base.maxVisible, 1),
            screenName: root.pickString(p, "screenName", base.screenName)
        };

        const m = cfg.motion;
        root.motion = {
            entrance: root.pickEnum(m, "entrance", ["slide", "scale", "fade", "none"], root.defaultMotion.entrance),
            exit: root.pickEnum(m, "exit", ["dwell", "slide", "fade", "none"], root.defaultMotion.exit),
            entranceMs: root.pickInt(m, "entranceMs", root.defaultMotion.entranceMs, 0),
            exitMs: root.pickInt(m, "exitMs", root.defaultMotion.exitMs, 0),
            dwellMs: root.pickInt(m, "dwellMs", root.defaultMotion.dwellMs, 0),
            reflowMs: root.pickInt(m, "reflowMs", root.defaultMotion.reflowMs, 0)
        };

        const t2 = cfg.timing;
        // min -1 on the per-urgency values: negative is meaningful here (drawer-only), unlike
        // every other duration in this file where it is just a typo.
        root.timing = {
            low: root.pickInt(t2, "low", root.defaultTiming.low, -1),
            normal: root.pickInt(t2, "normal", root.defaultTiming.normal, -1),
            critical: root.pickInt(t2, "critical", root.defaultTiming.critical, -1),
            respectAppTimeout: root.pickBool(t2, "respectAppTimeout", root.defaultTiming.respectAppTimeout),
            hoverPause: root.pickBool(t2, "hoverPause", root.defaultTiming.hoverPause),
            showRemaining: root.pickBool(t2, "showRemaining", root.defaultTiming.showRemaining),
            burstAt: root.pickInt(t2, "burstAt", root.defaultTiming.burstAt, 0),
            burstMs: root.pickInt(t2, "burstMs", root.defaultTiming.burstMs, 0),
            criticalCollapseMs: root.pickInt(t2, "criticalCollapseMs", root.defaultTiming.criticalCollapseMs, 0)
        };

        const s = cfg.store;
        root.store = {
            enabled: root.pickBool(s, "enabled", root.defaultStore.enabled),
            // 0 on either = that limit is off; both off means the history grows forever
            retentionDays: root.pickInt(s, "retentionDays", root.defaultStore.retentionDays, 0),
            retentionCount: root.pickInt(s, "retentionCount", root.defaultStore.retentionCount, 0)
        };

        const r = cfg.rules;
        root.rules = {
            enabled: root.pickBool(r, "enabled", root.defaultRules.enabled),
            path: root.pickString(r, "path", root.defaultRules.path),
            // a 0 budget would mean "fail open before asking", which is just disabled with
            // extra steps — clamp to something a lua round trip can actually make
            timeoutMs: root.pickInt(r, "timeoutMs", root.defaultRules.timeoutMs, 5)
        };

        const d = cfg.drawer;
        root.drawer = {
            mode: root.pickEnum(d, "mode", ["panel", "modal"], root.defaultDrawer.mode),
            width: root.pickInt(d, "width", root.defaultDrawer.width, 240),
            limit: root.pickInt(d, "limit", root.defaultDrawer.limit, 10),
            opacity: root.pickReal(d, "opacity", root.defaultDrawer.opacity, 0.05, 1),
            itemOpacity: root.pickReal(d, "itemOpacity", root.defaultDrawer.itemOpacity, 0.05, 1)
        };

        const su = cfg.surface;
        root.surface = {
            cardOpacity: root.pickReal(su, "cardOpacity", root.defaultSurface.cardOpacity, 0.05, 1),
            pillOpacity: root.pickReal(su, "pillOpacity", root.defaultSurface.pillOpacity, 0.05, 1)
        };

        // Actions. A malformed entry is DROPPED with a log line rather than taken
        // partially: an action with a matcher but no `run` would silently do nothing when
        // pressed, which is worse than not offering the key at all. `run` is normalised to
        // an argv array here so nothing downstream has to decide how to split it.
        const acts = [];
        const rawActs = Array.isArray(cfg.actions) ? cfg.actions : [];
        for (let i = 0; i < rawActs.length; i++) {
            const a = rawActs[i];
            if (!a || typeof a !== "object") {
                console.warn("notifications: config actions[" + i + "] is not an object — ignored");
                continue;
            }
            const label = (typeof a.label === "string") ? a.label : "";
            if (!label.length) {
                console.warn("notifications: config actions[" + i + "] has no label — ignored");
                continue;
            }
            let run = a.run;
            if (typeof run === "string")
                run = run.length ? run.split(/\s+/) : [];
            if (!Array.isArray(run) || run.length === 0) {
                console.warn("notifications: config actions[" + i + "] (" + label + ") has no run — ignored");
                continue;
            }
            acts.push({
                match: (a.match && typeof a.match === "object") ? a.match : ({}),
                label: label,
                key: (typeof a.key === "string" && a.key.length === 1) ? a.key : "",
                run: run,
                // What to do with the command's STDOUT:
                //   ""       fire and forget (the default)
                //   "draft"  put it in the reply field for review, then you press Enter
                //   "reply"  send it as the inline reply immediately
                // "draft" is the one to reach for when a language model writes the text. A
                // model that replies to your colleagues with no one reading it first is a
                // different product than one that drafts, and the difference is one word here.
                capture: (a.capture === "draft" || a.capture === "reply") ? a.capture : "",
                prompt: (a.prompt && typeof a.prompt === "object") ? a.prompt : null
            });
        }
        root.actions = acts;

        const pr = cfg.prompt;
        root.prompt = {
            categories: Array.isArray(pr && pr.categories) ? pr.categories.filter(c => typeof c === "string") : root.defaultPrompt.categories.slice(),
            placeholder: (pr && typeof pr.placeholder === "string") ? pr.placeholder : root.defaultPrompt.placeholder
        };

        const sn = cfg.snooze;
        root.snooze = {
            defaultMs: root.pickInt(sn, "defaultMs", root.defaultSnooze.defaultMs, 1000),
            maxMs: root.pickInt(sn, "maxMs", root.defaultSnooze.maxMs, 1000)
        };

        const co = cfg.collapse;
        root.collapse = {
            home: root.pickEnum(co, "home", ["bar", "stack"], root.defaultCollapse.home),
            maxPills: root.pickInt(co, "maxPills", root.defaultCollapse.maxPills, 1)
        };
    }

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        // The file is optional. Without this, every shell on a machine that never wrote one
        // logs a read error at startup, which trains people to ignore the log.
        printErrors: false
        onLoaded: root.rebuild()
        onLoadFailed: root.rebuild()
        onFileChanged: {
            reload();
            root.rebuild();
        }
    }

    // Watches the TOML for changes only — its text is never parsed here, tomlq does that.
    FileView {
        id: tomlFile
        path: root.tomlPath
        watchChanges: true
        printErrors: false
        onLoaded: root.convertToml()
        onFileChanged: root.convertToml()
        onLoadFailed: {
            // no TOML on this machine: JSON (or defaults) is the answer, silently
            root.tomlCfg = null;
            root.rebuild();
        }
    }

    // MERGE RULES, and they are deliberate:
    //   - tables merge key by key, recursively, so a drop-in can set one value without
    //     restating the block it lives in
    //   - arrays CONCATENATE, so `[[actions]]` in a drop-in adds a verb rather than replacing
    //     every verb the base file defined. That is the whole point of a drop-in here; making
    //     arrays replace would mean copying the entire actions list to add one entry
    //   - scalars: last file wins
    //
    // The trade, stated: concatenation means a drop-in cannot REMOVE a base action. Editing the
    // base file is how you do that, which is fine when the base file is yours.
    function mergeInto(base, over) {
        for (const k in over) {
            const v = over[k];
            if (Array.isArray(v)) {
                base[k] = (Array.isArray(base[k]) ? base[k] : []).concat(v);
            } else if (v && typeof v === "object") {
                if (!base[k] || typeof base[k] !== "object" || Array.isArray(base[k]))
                    base[k] = {};
                root.mergeInto(base[k], v);
            } else {
                base[k] = v;
            }
        }
        return base;
    }

    function convertToml() {
        // sh only to expand the drop-in glob and drop files that do not exist — tomlq fails on
        // a missing path, and an unmatched glob would otherwise be passed through literally.
        // Every path here comes from this file, never from notification content, so this is not
        // the injection surface the action `run` rules are about.
        // The three paths are read into variables BEFORE `set --` clears the positional
        // parameters — clearing them first leaves the loop globbing empty strings, which
        // silently produces zero layers and looks exactly like "no config file".
        tomlProc.command = ["sh", "-c", "b=$1; d=$2; l=$3; set --; for f in \"$b\" \"$d\"/*.toml \"$l\"; do [ -f \"$f\" ] && set -- \"$@\" \"$f\"; done; [ \"$#\" -gt 0 ] && exec tomlq -c -s . \"$@\"; echo '[]'", "sh", root.tomlPath, root.tomlDir, root.tomlLocalPath];
        tomlProc.running = true;
    }

    Process {
        id: tomlProc
        stderr: StdioCollector {}
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (!t.length)
                    return;
                try {
                    const docs = JSON.parse(t);
                    if (!Array.isArray(docs) || docs.length === 0) {
                        root.tomlCfg = null;
                    } else {
                        let merged = {};
                        for (let i = 0; i < docs.length; i++)
                            root.mergeInto(merged, docs[i]);
                        root.tomlCfg = merged;
                    }
                } catch (e) {
                    console.warn("notifications: tomlq produced unparseable output —", e);
                    root.tomlCfg = null;
                }
                root.rebuild();
            }
        }
        onExited: exitCode => {
            if (exitCode === 0)
                return;
            // 127 = no tomlq on this machine. Anything else is a broken TOML file, and the
            // user wants to know which line — tomlq already said so on stderr.
            const why = exitCode === 127 ? "tomlq not found (install the yq package)" : tomlProc.stderr.text.trim();
            console.warn("notifications: could not read", root.tomlPath, "—", why, "— falling back to JSON/defaults");
            root.tomlCfg = null;
            root.rebuild();
        }
    }

    Component.onCompleted: rebuild()
}
