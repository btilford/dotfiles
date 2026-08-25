-- Notification rules. Copy to ~/.config/quickshell/notifications.lua to use it; the live
-- shell reloads on save, no restart. QS_NOTIFY_RULES=<path> reads a different file instead
-- (that is the seam a nested session or the capture harness uses).
--
-- The file returns a LIST of rules. Every matching rule runs, in order, and later writes
-- beat earlier ones — so a broad rule can be layered with a narrow exception instead of
-- restating the matcher in every combination. `stop = true` ends evaluation.
--
--   {
--     name = "…",                         -- shows up in log lines
--     when = function(n, s) … end,        -- omit = always matches
--     set  = { durationMs = 0 },          -- or function(p, n, s) that mutates p
--     stop = false,
--   }
--
-- `n` — the notification:
--     appName appIcon summary body category urgency (0/1/2) urgencyName ("low"/"normal"/
--     "critical") image value transient resident durationMs timestamp (epoch ms)
--
-- `s` — the shell right now:
--     dnd monitor workspace fullscreen visible (cards on screen) hour (0-23)
--
-- `p` — what you may change:
--     durationMs   > 0 show that long · 0 sticky · < 0 drawer-only (recorded, never popped)
--     screenName   monitor name, "" = follow focus
--     anchorH      "left" | "center" | "right"
--     anchorV      "top"  | "center" | "bottom"
--
-- A rule that throws is skipped and logged; a file that does not parse is ignored entirely.
-- In every failure case the notification is still shown, with its defaults. Rules cannot
-- drop a notification — the strongest thing you can say is "drawer-only".

return {

  -- Build noise: recorded in the history and counted unread, never popped. This is the
  -- honest version of "muting" an app — nothing is lost, it just stops interrupting.
  {
    name = "build noise is drawer-only",
    when = function(n)
      return n.appName == "cargo" or n.appName == "mise" or n.category == "build"
    end,
    set = { durationMs = -1 },
  },

  -- A chatty app during focused hours: shortened rather than silenced. Gated on `not s.dnd` —
  -- a rule that sets durationMs unconditionally is an implicit DND exception (see notif-dnd-core
  -- below); this one is not meant to be one.
  {
    name = "chatty app, short dwell",
    when = function(n, s)
      return not s.dnd and n.appName == "Discord" and s.hour >= 9 and s.hour < 18
    end,
    set = { durationMs = 2000 },
  },

  -- Homelab criticals go to the secondary monitor, top anchor, and stay until dismissed.
  -- Replace "DP-2" with a monitor you actually have: an unknown name falls back to the
  -- focused monitor rather than disappearing. Gated on `not s.dnd` too, even though it only
  -- matches criticals — being critical does not make it the "dnd exception" rule below, and
  -- without the gate it would silently double as one.
  {
    name = "homelab criticals to the side screen",
    when = function(n, s)
      return not s.dnd
        and n.urgencyName == "critical"
        and (n.category == "homelab" or n.appName:match("^alert"))
    end,
    set = {
      screenName = "DP-2",
      anchorV = "top",
      anchorH = "right",
      durationMs = 0,
    },
  },

  -- Do Not Disturb (story: notif-dnd-core) already suppresses everything to drawer-only while
  -- `s.dnd` is true — that is the shell's own default, applied before this file ever runs. A
  -- rule is how you punch a hole in it: this lets criticals and incoming calls through anyway.
  -- Without a rule like this, DND is unconditional; with one, it is DND you can trust to still
  -- wake you for what matters.
  {
    name = "dnd exception: criticals and calls get through",
    when = function(n, s)
      return s.dnd and (n.urgencyName == "critical" or n.category == "call")
    end,
    set = { durationMs = 6000 },
  },

  -- Nothing interrupts a fullscreen window except a critical. Late in the list on purpose:
  -- it overrides the durations above, and it is written as a function because it needs to
  -- read the notification and the shell state together.
  {
    name = "fullscreen: only criticals pop",
    when = function(n, s)
      return s.fullscreen and n.urgencyName ~= "critical"
    end,
    set = function(p)
      p.durationMs = -1
    end,
  },
}
