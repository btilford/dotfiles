pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Weather for the clock drawer (components/ClockDrawer.qml).
//
// THE PROVIDER IS CONFIG, NOT A HARDCODE. Three backends answer the same question and each is
// right on a different machine: open-meteo needs no key and covers the planet, home-assistant
// keeps the request on the LAN, wttr.in is a one-call fallback when neither is set up.
//
//   file: ~/.config/quickshell/weather.json   (see weather.example.json)
//   env:  QS_WEATHER_CONFIG=<path>            read this file instead — the path seam a nested
//                                             session (visual-capture, `qs -p`, CI) uses so a
//                                             rig never reads the live desktop's coordinates
//
// NOTHING PRIVATE LIVES IN THIS FILE OR IN THE REPO. A home latitude/longitude is private
// infrastructure under the repo's public-mirror rule, exactly like a LAN IP, so the real
// weather.json is untracked and provisioned from private-dotfiles; only the example ships. A
// Home Assistant token is never in the JSON either — the config names a SECRET, and the value
// is fetched at request time through `dotfiles-secrets --get <NAME>`.
//
// FAILURE IS A STATE, NOT A BLANK. Every path ends in one of idle/loading/ok/error with a
// human-readable `error`, and the last good reading is kept so a flaky fetch shows yesterday's
// number marked stale rather than an empty panel or a spinner that never resolves.
Singleton {
    id: root

    // ---------------------------------------------------------------------------------------
    // Config
    // ---------------------------------------------------------------------------------------

    readonly property string configPath: root.envOr("QS_WEATHER_CONFIG", Quickshell.env("HOME") + "/.config/quickshell/weather.json")

    readonly property var defaults: ({
            provider: "open-meteo",
            label: "",
            latitude: 0,
            longitude: 0,
            units: "imperial",
            refreshMinutes: 15,
            timeoutSec: 10,
            forecastDays: 5
        })

    property string provider: root.defaults.provider
    property string label: ""
    property real latitude: 0
    property real longitude: 0
    property string units: root.defaults.units
    property int refreshMinutes: root.defaults.refreshMinutes
    property int timeoutSec: root.defaults.timeoutSec
    property int forecastDays: root.defaults.forecastDays

    // home-assistant
    property string haBaseUrl: ""
    property string haEntity: ""
    property string haTokenSecret: ""
    // wttr.in
    property string wttrLocation: ""

    readonly property bool metric: root.units === "metric"
    readonly property string tempUnit: root.metric ? "°C" : "°F"
    readonly property string windUnit: root.metric ? "km/h" : "mph"

    // What each provider needs before a request is worth making. Reported in the panel rather
    // than logged, because "not configured" is the state a fresh machine is actually in and the
    // user is the one who can fix it.
    readonly property string missing: {
        if (root.provider === "open-meteo")
            return (root.latitude === 0 && root.longitude === 0) ? "set latitude/longitude in weather.json" : "";
        if (root.provider === "home-assistant") {
            if (!root.haBaseUrl.length)
                return "set homeAssistant.baseUrl in weather.json";
            if (!root.haEntity.length)
                return "set homeAssistant.entity in weather.json";
            if (!root.haTokenSecret.length)
                return "set homeAssistant.tokenSecret in weather.json";
            return "";
        }
        if (root.provider === "wttr.in")
            return root.wttrLocation.length ? "" : "set wttr.location in weather.json";
        return "unknown provider " + root.provider;
    }
    readonly property bool configured: root.missing.length === 0

    // ---------------------------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------------------------

    // idle | loading | ok | error
    property string status: "idle"
    property string error: ""
    // { temp, feelsLike, humidity, wind, desc, icon }
    property var current: null
    // [{ day, hi, lo, desc, icon }]
    property var forecast: []
    // When `current` was fetched. The reading survives a failure on purpose — a widget that
    // blanks on one dropped packet is less useful than one that says how old its number is.
    property double updatedAt: 0

    readonly property bool stale: root.status === "error" && root.current !== null

    // The units the CURRENT READING was fetched in, which is not necessarily the units the
    // config asks for now. `units` is live config; `current` is a cached number. Editing
    // weather.json (or switching provider) while a cached reading is on screen re-labelled it
    // without re-fetching it — a 19°C reading relabelled 19°F, which is not a cosmetic bug, it
    // is a wrong number on the screen. A reading carries its own units until it is replaced.
    property string readingTempUnit: root.tempUnit
    property string readingWindUnit: root.windUnit

    function envOr(key: string, fallback: string): string {
        const v = Quickshell.env(key);
        return (v === undefined || v === null || v === "") ? fallback : v;
    }

    function num(v, fallback) {
        const n = typeof v === "string" ? parseFloat(v) : v;
        return (typeof n === "number" && isFinite(n)) ? n : fallback;
    }

    function rebuild() {
        let cfg = {};
        try {
            const t = configFile.text();
            if (t && t.trim().length)
                cfg = JSON.parse(t);
        } catch (e) {
            console.warn("weather: config unreadable, using defaults —", e);
            cfg = {};
        }
        if (!cfg || typeof cfg !== "object")
            cfg = {};

        const p = typeof cfg.provider === "string" ? cfg.provider : root.defaults.provider;
        if (["open-meteo", "home-assistant", "wttr.in"].indexOf(p) < 0) {
            console.warn("weather: unknown provider", p, "— using", root.defaults.provider);
            root.provider = root.defaults.provider;
        } else {
            root.provider = p;
        }

        root.label = typeof cfg.label === "string" ? cfg.label : "";
        root.latitude = root.num(cfg.latitude, 0);
        root.longitude = root.num(cfg.longitude, 0);
        root.units = cfg.units === "metric" ? "metric" : "imperial";
        root.refreshMinutes = Math.max(5, Math.round(root.num(cfg.refreshMinutes, root.defaults.refreshMinutes)));
        root.timeoutSec = Math.max(2, Math.round(root.num(cfg.timeoutSec, root.defaults.timeoutSec)));
        root.forecastDays = Math.max(1, Math.min(7, Math.round(root.num(cfg.forecastDays, root.defaults.forecastDays))));

        const ha = cfg.homeAssistant || {};
        root.haBaseUrl = (typeof ha.baseUrl === "string" ? ha.baseUrl : "").replace(/\/+$/, "");
        root.haEntity = typeof ha.entity === "string" ? ha.entity : "";
        root.haTokenSecret = typeof ha.tokenSecret === "string" ? ha.tokenSecret : "";

        const w = cfg.wttr || {};
        root.wttrLocation = typeof w.location === "string" ? w.location : "";

        root.refresh();
    }

    // ---------------------------------------------------------------------------------------
    // Icons. WMO codes for open-meteo; the other two providers hand back prose, so their
    // descriptions are keyword-matched onto the same small set. One vocabulary in the view.
    // ---------------------------------------------------------------------------------------

    readonly property string iconClear: "󰖙"
    readonly property string iconPartly: "󰖕"
    readonly property string iconCloud: "󰖐"
    readonly property string iconFog: "󰖑"
    readonly property string iconDrizzle: "󰖖"
    readonly property string iconRain: "󰖗"
    readonly property string iconSnow: "󰖘"
    readonly property string iconStorm: "󰖓"

    function wmoIcon(code) {
        const c = Math.round(root.num(code, -1));
        if (c === 0 || c === 1)
            return root.iconClear;
        if (c === 2)
            return root.iconPartly;
        if (c === 3)
            return root.iconCloud;
        if (c === 45 || c === 48)
            return root.iconFog;
        if (c >= 51 && c <= 57)
            return root.iconDrizzle;
        if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82))
            return root.iconRain;
        if ((c >= 71 && c <= 77) || c === 85 || c === 86)
            return root.iconSnow;
        if (c >= 95)
            return root.iconStorm;
        return root.iconCloud;
    }

    function wmoDesc(code) {
        const c = Math.round(root.num(code, -1));
        const map = {
            0: "Clear",
            1: "Mainly clear",
            2: "Partly cloudy",
            3: "Overcast",
            45: "Fog",
            48: "Rime fog",
            51: "Light drizzle",
            53: "Drizzle",
            55: "Heavy drizzle",
            56: "Freezing drizzle",
            57: "Freezing drizzle",
            61: "Light rain",
            63: "Rain",
            65: "Heavy rain",
            66: "Freezing rain",
            67: "Freezing rain",
            71: "Light snow",
            73: "Snow",
            75: "Heavy snow",
            77: "Snow grains",
            80: "Rain showers",
            81: "Rain showers",
            82: "Violent showers",
            85: "Snow showers",
            86: "Snow showers",
            95: "Thunderstorm",
            96: "Thunderstorm, hail",
            99: "Thunderstorm, hail"
        };
        return map[c] || "—";
    }

    // Prose -> the same icon set, for the two providers that do not speak WMO.
    function textIcon(text) {
        const s = (text || "").toLowerCase();
        if (s.indexOf("thunder") >= 0 || s.indexOf("lightning") >= 0)
            return root.iconStorm;
        if (s.indexOf("snow") >= 0 || s.indexOf("sleet") >= 0 || s.indexOf("hail") >= 0)
            return root.iconSnow;
        if (s.indexOf("drizzle") >= 0)
            return root.iconDrizzle;
        if (s.indexOf("rain") >= 0 || s.indexOf("shower") >= 0 || s.indexOf("pouring") >= 0)
            return root.iconRain;
        if (s.indexOf("fog") >= 0 || s.indexOf("mist") >= 0 || s.indexOf("haze") >= 0)
            return root.iconFog;
        if (s.indexOf("partly") >= 0 || s.indexOf("partlycloudy") >= 0)
            return root.iconPartly;
        if (s.indexOf("cloud") >= 0 || s.indexOf("overcast") >= 0)
            return root.iconCloud;
        if (s.indexOf("clear") >= 0 || s.indexOf("sunny") >= 0)
            return root.iconClear;
        return root.iconCloud;
    }

    // "sunny" / "partlycloudy" -> "Sunny" / "Partly cloudy". Home Assistant's states are
    // machine tokens; nothing else in the shell shows a user a snake_case word.
    function prettify(s) {
        const t = (s || "").replace(/[_-]+/g, " ").trim();
        if (!t.length)
            return "—";
        if (t === "partlycloudy")
            return "Partly cloudy";
        return t.charAt(0).toUpperCase() + t.slice(1);
    }

    function dayName(iso) {
        // ISO date only ("2026-08-19"): parsed as parts rather than through Date(string), which
        // treats a bare date as UTC and can name the wrong weekday west of Greenwich.
        const m = (iso || "").match(/^(\d{4})-(\d{2})-(\d{2})/);
        if (!m)
            return "";
        const d = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
        return Qt.formatDate(d, "ddd");
    }

    // ---------------------------------------------------------------------------------------
    // Fetch. curl in a Process rather than XMLHttpRequest: the Home Assistant path needs a
    // token that must never be written into a file or a QML string, and `dotfiles-secrets`
    // hands it over inside the same shell that makes the request, so it exists only in that
    // subprocess's memory.
    // ---------------------------------------------------------------------------------------

    function fail(why) {
        root.status = "error";
        root.error = why;
    }

    function refresh() {
        if (!root.configured) {
            root.fail(root.missing);
            return;
        }
        if (fetchProc.running)
            return;
        const cmd = root.buildCommand();
        if (!cmd) {
            root.fail("no request for provider " + root.provider);
            return;
        }
        root.error = "";
        root.status = "loading";
        fetchProc.command = cmd;
        fetchProc.running = true;
    }

    function buildCommand() {
        const t = String(root.timeoutSec);
        if (root.provider === "open-meteo") {
            const url = "https://api.open-meteo.com/v1/forecast" + "?latitude=" + root.latitude + "&longitude=" + root.longitude + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m" + "&daily=weather_code,temperature_2m_max,temperature_2m_min" + "&forecast_days=" + root.forecastDays + "&timezone=auto" + "&temperature_unit=" + (root.metric ? "celsius" : "fahrenheit") + "&wind_speed_unit=" + (root.metric ? "kmh" : "mph");
            return ["curl", "-fsS", "--max-time", t, url];
        }
        if (root.provider === "wttr.in") {
            return ["curl", "-fsS", "--max-time", t, "https://wttr.in/" + encodeURIComponent(root.wttrLocation) + "?format=j1"];
        }
        if (root.provider === "home-assistant") {
            // The secret NAME is validated before it reaches a shell, the same rule
            // dotfiles-secrets applies to its own argument. The URL and the name are passed as
            // positional parameters, never interpolated into the script text, so nothing in the
            // config file can become a command.
            if (!/^[A-Za-z0-9_]+$/.test(root.haTokenSecret)) {
                root.fail("homeAssistant.tokenSecret must match [A-Za-z0-9_]+");
                return null;
            }
            const script = 'tok=$(dotfiles-secrets --get "$1" 2>/dev/null); ' + '[ -n "$tok" ] || { echo "no secret $1" >&2; exit 3; }; ' + 'exec curl -fsS --max-time "$3" -H "Authorization: Bearer $tok" "$2"';
            return ["sh", "-c", script, "sh", root.haTokenSecret, root.haBaseUrl + "/api/states/" + root.haEntity, t];
        }
        return null;
    }

    Process {
        id: fetchProc
        stderr: StdioCollector {}
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (!t.length)
                    return;
                try {
                    root.apply(JSON.parse(t));
                } catch (e) {
                    console.warn("weather: unparseable response —", e);
                    root.fail("bad response from " + root.provider);
                }
            }
        }
        onExited: exitCode => {
            if (exitCode === 0)
                return;
            // 127 = no curl (or no dotfiles-secrets on the HA path); 3 is this script's own
            // "the secret is not available". Anything else is curl's, and its message on
            // stderr is more useful than its number.
            const why = exitCode === 127 ? "curl not found" : (exitCode === 3 ? "secret " + root.haTokenSecret + " unavailable" : (fetchProc.stderr.text.trim() || ("curl exited " + exitCode)));
            console.warn("weather:", root.provider, "fetch failed —", why);
            root.fail(why);
        }
    }

    // One entry point per provider shape, all producing the same two objects. A view that had
    // to know which provider answered would grow a branch per widget.
    function apply(doc) {
        if (root.provider === "open-meteo")
            root.applyOpenMeteo(doc);
        else if (root.provider === "wttr.in")
            root.applyWttr(doc);
        else
            root.applyHomeAssistant(doc);
    }

    function commit(cur, days) {
        root.current = cur;
        root.forecast = days;
        root.readingTempUnit = root.tempUnit;
        root.readingWindUnit = root.windUnit;
        root.updatedAt = Date.now();
        root.status = "ok";
        root.error = "";
    }

    function applyOpenMeteo(doc) {
        const c = doc.current;
        if (!c) {
            root.fail("open-meteo returned no current conditions");
            return;
        }
        const cur = {
            temp: root.num(c.temperature_2m, NaN),
            feelsLike: root.num(c.apparent_temperature, NaN),
            humidity: root.num(c.relative_humidity_2m, NaN),
            wind: root.num(c.wind_speed_10m, NaN),
            desc: root.wmoDesc(c.weather_code),
            icon: root.wmoIcon(c.weather_code)
        };
        const days = [];
        const d = doc.daily;
        if (d && Array.isArray(d.time)) {
            for (let i = 0; i < d.time.length; i++)
                days.push({
                    day: root.dayName(d.time[i]),
                    hi: root.num(d.temperature_2m_max[i], NaN),
                    lo: root.num(d.temperature_2m_min[i], NaN),
                    desc: root.wmoDesc(d.weather_code[i]),
                    icon: root.wmoIcon(d.weather_code[i])
                });
        }
        root.commit(cur, days);
    }

    function applyWttr(doc) {
        const c = (doc.current_condition || [])[0];
        if (!c) {
            root.fail("wttr.in returned no current conditions");
            return;
        }
        const desc = ((c.weatherDesc || [])[0] || {}).value || "—";
        const cur = {
            temp: root.num(root.metric ? c.temp_C : c.temp_F, NaN),
            feelsLike: root.num(root.metric ? c.FeelsLikeC : c.FeelsLikeF, NaN),
            humidity: root.num(c.humidity, NaN),
            wind: root.num(root.metric ? c.windspeedKmph : c.windspeedMiles, NaN),
            desc: desc,
            icon: root.textIcon(desc)
        };
        const days = [];
        for (const w of (doc.weather || []).slice(0, root.forecastDays)) {
            // wttr gives a condition per 3-hour block; midday is the one a day summary means.
            const noon = (w.hourly || [])[4] || (w.hourly || [])[0] || {};
            const dd = ((noon.weatherDesc || [])[0] || {}).value || "—";
            days.push({
                day: root.dayName(w.date),
                hi: root.num(root.metric ? w.maxtempC : w.maxtempF, NaN),
                lo: root.num(root.metric ? w.mintempC : w.mintempF, NaN),
                desc: dd,
                icon: root.textIcon(dd)
            });
        }
        root.commit(cur, days);
    }

    function applyHomeAssistant(doc) {
        if (!doc || typeof doc.state !== "string") {
            root.fail("no such entity: " + root.haEntity);
            return;
        }
        const a = doc.attributes || {};
        const cur = {
            temp: root.num(a.temperature, NaN),
            feelsLike: root.num(a.apparent_temperature, NaN),
            humidity: root.num(a.humidity, NaN),
            wind: root.num(a.wind_speed, NaN),
            desc: root.prettify(doc.state),
            icon: root.textIcon(doc.state)
        };
        // `attributes.forecast` was removed from weather entities in HA 2024.4 — a forecast now
        // needs a weather.get_forecasts service call, which is a POST and a different shape. It
        // is read when a legacy integration still publishes it; otherwise the strip is empty and
        // the current conditions still render, which is the useful half.
        const days = [];
        for (const f of (a.forecast || []).slice(0, root.forecastDays))
            days.push({
                day: root.dayName(String(f.datetime || "").slice(0, 10)),
                hi: root.num(f.temperature, NaN),
                lo: root.num(f.templow, NaN),
                desc: root.prettify(f.condition),
                icon: root.textIcon(f.condition)
            });
        root.commit(cur, days);
    }

    // ---------------------------------------------------------------------------------------

    Timer {
        interval: Math.max(5, root.refreshMinutes) * 60000
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        // Optional by design: a machine with no weather.json shows "not configured" in the
        // panel, which says more than a read error at every startup.
        printErrors: false
        onLoaded: root.rebuild()
        onLoadFailed: root.rebuild()
        onFileChanged: {
            reload();
            root.rebuild();
        }
    }

    Component.onCompleted: root.rebuild()
}
