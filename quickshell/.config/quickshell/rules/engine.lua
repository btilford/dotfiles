-- Notification rules evaluator (story: notif-lua-rules).
--
-- Runs as a long-lived subprocess of the quickshell daemon, NOT in it: quickshell 0.3.0
-- has no Lua binding, and an in-process VM would put user code on the same thread as the
-- popup stack — a rule with an infinite loop would freeze the shell rather than one
-- notification. Out here, the worst a rule can do is miss its deadline, and the shell
-- falls back to defaults.
--
-- Protocol: one JSON object per line in, one per line out.
--   in   {"seq":7,"n":{...notification...},"p":{...presentation...},"s":{...shell state...}}
--   out  {"seq":7,"p":{...presentation...}}            -- rules ran
--        {"seq":7,"p":{...},"err":"…"}                 -- a rule threw; p is what survived
-- `seq` is echoed back because the shell may have several notifications in flight and
-- must never apply one notification's answer to another.
--
-- Usage: lua engine.lua <rules-file>
-- The rules file is re-read on SIGHUP-free terms: the shell restarts this process when the
-- file changes, so there is no reload path to get wrong here.

local RULES_PATH = arg and arg[1] or nil

-- ---------------------------------------------------------------------------------------
-- Minimal JSON. Deliberately not a dependency: lua-cjson is not installed by default on
-- every machine this config lands on, and a rules engine that fails to start because a
-- rock is missing would take notifications down with it. Only has to handle what the shell
-- emits (JSON.stringify output) and what we emit back.
-- ---------------------------------------------------------------------------------------

local json = {}

local escapes = {
  ['"'] = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local function escape(s)
  return (s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format('\\u%04x', string.byte(c))
  end))
end

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' then
      return false
    end
    n = n + 1
  end
  return n == #t
end

function json.encode(v)
  local t = type(v)
  if v == nil then
    return 'null'
  elseif t == 'boolean' then
    return tostring(v)
  elseif t == 'number' then
    -- %.14g keeps integers integral and avoids scientific notation for our ranges
    return string.format('%.14g', v)
  elseif t == 'string' then
    return '"' .. escape(v) .. '"'
  elseif t == 'table' then
    local out = {}
    if is_array(v) then
      for i = 1, #v do
        out[#out + 1] = json.encode(v[i])
      end
      return '[' .. table.concat(out, ',') .. ']'
    end
    for k, val in pairs(v) do
      if val ~= nil then
        out[#out + 1] = '"' .. escape(tostring(k)) .. '":' .. json.encode(val)
      end
    end
    return '{' .. table.concat(out, ',') .. '}'
  end
  return 'null'
end

local decode_value

local function skip_ws(s, i)
  local _, j = s:find('^[ \t\r\n]*', i)
  return j + 1
end

local function decode_string(s, i)
  local out = {}
  i = i + 1 -- opening quote
  while true do
    local c = s:sub(i, i)
    if c == '' then
      error('unterminated string')
    elseif c == '"' then
      return table.concat(out), i + 1
    elseif c == '\\' then
      local e = s:sub(i + 1, i + 1)
      if e == 'u' then
        local hex = s:sub(i + 2, i + 5)
        local code = tonumber(hex, 16) or 63
        -- utf8.char exists in 5.3+; string.char covers the ASCII range we care about and
        -- anything above it degrades to '?' rather than corrupting the stream
        if code < 128 then
          out[#out + 1] = string.char(code)
        elseif utf8 and utf8.char then
          out[#out + 1] = utf8.char(code)
        else
          out[#out + 1] = '?'
        end
        i = i + 6
      else
        local map = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
        out[#out + 1] = map[e] or e
        i = i + 2
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
end

decode_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '{' then
    local obj = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == '}' then
      return obj, i + 1
    end
    while true do
      local key
      i = skip_ws(s, i)
      key, i = decode_string(s, i)
      i = skip_ws(s, i)
      i = i + 1 -- colon
      local val
      val, i = decode_value(s, i)
      obj[key] = val
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      i = i + 1
      if d == '}' then
        return obj, i
      end
    end
  elseif c == '[' then
    local arr = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == ']' then
      return arr, i + 1
    end
    while true do
      local val
      val, i = decode_value(s, i)
      arr[#arr + 1] = val
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      i = i + 1
      if d == ']' then
        return arr, i
      end
    end
  elseif c == '"' then
    return decode_string(s, i)
  elseif s:sub(i, i + 3) == 'true' then
    return true, i + 4
  elseif s:sub(i, i + 4) == 'false' then
    return false, i + 5
  elseif s:sub(i, i + 3) == 'null' then
    return nil, i + 4
  end
  local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
  if num and #num > 0 then
    return tonumber(num), i + #num
  end
  error('unexpected character at ' .. i .. ': ' .. c)
end

function json.decode(s)
  local v = decode_value(s, 1)
  return v
end

-- ---------------------------------------------------------------------------------------
-- Rules
--
-- The rules file returns a list. Each entry:
--   when  function(n, s) -> boolean   (omitted = always matches)
--   set   table of presentation fields, OR function(p, n, s) that mutates p
--   stop  true = no later rule runs
--   name  for log lines
--
-- Semantics: EVERY matching rule runs, in file order, and later writes beat earlier ones.
-- That is what lets a broad rule ("mute this app") be layered with a narrow exception
-- ("...except criticals") instead of duplicating the matcher into every combination.
-- ---------------------------------------------------------------------------------------

local rules = {}
local load_error = nil

local function load_rules()
  rules = {}
  load_error = nil
  if not RULES_PATH then
    return
  end
  local chunk, err = loadfile(RULES_PATH)
  if not chunk then
    -- Missing file is not an error: it is the normal state for a machine with no rules.
    if not tostring(err):match('No such file') then
      load_error = tostring(err)
      io.stderr:write('notify-rules: ' .. load_error .. '\n')
    end
    return
  end
  local ok, result = pcall(chunk)
  if not ok then
    load_error = tostring(result)
    io.stderr:write('notify-rules: ' .. load_error .. '\n')
    return
  end
  -- An empty file (or one that returns nothing) is "no rules", not a mistake: it is what
  -- a harness writes to clear the rules between scenes, and what a half-finished edit looks
  -- like for the moment before the user types `return`.
  if result == nil then
    return
  end
  if type(result) ~= 'table' then
    load_error = RULES_PATH .. ' did not return a table of rules'
    io.stderr:write('notify-rules: ' .. load_error .. '\n')
    return
  end
  rules = result
end

-- Only these fields may be written back. Anything else a rule sets is ignored rather than
-- forwarded: the shell validates again on its side, and a typo should not look like it
-- worked.
local WRITABLE = {
  durationMs = true,
  screenName = true,
  anchorH = true,
  anchorV = true,
  -- accepted and forwarded now, honoured by the stories that own them
  group = true,     -- notif-grouping
  actions = true,   -- notif-actions (false = veto this notification's actions)
}

local function sanitize(p)
  local out = {}
  for k in pairs(WRITABLE) do
    if p[k] ~= nil then
      out[k] = p[k]
    end
  end
  return out
end

local function evaluate(n, p, s)
  local err = nil
  for i = 1, #rules do
    local rule = rules[i]
    if type(rule) == 'table' then
      local matched = true
      if type(rule.when) == 'function' then
        local ok, res = pcall(rule.when, n, s)
        if not ok then
          -- One bad predicate must not cost the notification its remaining rules, and
          -- must never cost it its display. Skip the rule, keep going, report once.
          err = (err and err .. '; ' or '') .. (rule.name or ('rule ' .. i)) .. ': ' .. tostring(res)
          matched = false
        else
          matched = res and true or false
        end
      end
      if matched then
        if type(rule.set) == 'function' then
          local ok, res = pcall(rule.set, p, n, s)
          if not ok then
            err = (err and err .. '; ' or '') .. (rule.name or ('rule ' .. i)) .. ': ' .. tostring(res)
          end
        elseif type(rule.set) == 'table' then
          for k, v in pairs(rule.set) do
            p[k] = v
          end
        end
        if rule.stop then
          break
        end
      end
    end
  end
  return p, err
end

-- ---------------------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------------------

load_rules()
io.stdout:setvbuf('line')

for line in io.lines() do
  if #line > 0 then
    local ok, req = pcall(json.decode, line)
    if ok and type(req) == 'table' then
      local p = req.p or {}
      local err = load_error
      local rerr
      p, rerr = evaluate(req.n or {}, p, req.s or {})
      if rerr then
        err = (err and err .. '; ' or '') .. rerr
      end
      local reply = { seq = req.seq, p = sanitize(p) }
      if err then
        reply.err = err
      end
      io.write(json.encode(reply), '\n')
    else
      -- Unparseable input still gets an answer, because the shell is waiting on one and
      -- silence would cost that notification its (fail-open) deadline for no reason.
      io.write('{"err":"bad request"}\n')
    end
  end
end
