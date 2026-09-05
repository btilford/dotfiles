-- Cheat sheet for the AI, completion and LSP keys, which a plain keymap picker
-- reports wrongly.
--
-- blink.cmp runs its preset from its own layer rather than through a keymap, so
-- `:Telescope keymaps` never lists it and shows only the map blink falls back
-- to. Several keys are shared that way: `<C-y>` accepts a blink item while the
-- menu is open and asks minuet for a suggestion otherwise. Each row below says
-- which layer answers, so a shared key reads as a stack instead of a conflict.

local M = {}

-- Descriptions carry a stable prefix or suffix, so the picker collects itself
-- from live keymaps rather than a list that goes stale beside the config it
-- describes. Trouble labels its own the other way round.
local OWNED = { "^AI %(", "^Luasnip:", "^LSP:", "%(Trouble%)$" }

-- blink.cmp's `default` preset, which no scan can see. Keep in step with the
-- `preset` set in plugins/blink.lua.
local BLINK = {
  { "i", "<C-space>", "blink.cmp", "Open menu, then docs" },
  { "i", "<C-y>", "blink.cmp", "Accept item (menu open)" },
  { "i", "<C-e>", "blink.cmp", "Cancel (menu open)" },
  { "i", "<C-n>", "blink.cmp", "Next item" },
  { "i", "<C-p>", "blink.cmp", "Previous item" },
  { "i", "<C-b>", "blink.cmp", "Scroll docs up" },
  { "i", "<C-f>", "blink.cmp", "Scroll docs down" },
  { "i", "<C-k>", "blink.cmp", "Toggle signature help" },
  { "i", "<Tab>", "blink.cmp", "Snippet jump forward" },
  { "i", "<S-Tab>", "blink.cmp", "Snippet jump backward" },
}

local function owned(desc)
  if not desc then
    return false
  end
  for _, pattern in ipairs(OWNED) do
    if desc:match(pattern) then
      return true
    end
  end
  return false
end

-- "AI (Minuet): Accept line" -> "Minuet", "Accept line". The label groups the
-- list; without it every row would repeat the plugin name in its own text.
-- Bracket markers ("[G]oto [R]eferences") are the which-key hint convention and
-- only add noise once the key is already in its own column.
local function split_desc(desc)
  local source, action = desc:match("^AI %(([^)]+)%):%s*(.+)$")
  if not source then
    source, action = desc:match("^(.-)%s*%((Trouble)%)$")
    if source then
      source, action = "Trouble", source
    end
  end
  if not source then
    source, action = desc:match("^([^:]+):%s*(.+)$")
  end
  source, action = source or "?", action or desc
  return source, (action:gsub("[%[%]]", ""))
end

-- `nvim_get_keymap` returns the leader as the raw space it expands to, and
-- writes a control key in whatever case the config used. `<C-Y>` and `<C-y>`
-- are one key to vim, so they must read as one key here too -- but `<C-S-D>`
-- carries a real shift, so only a lone letter is folded.
local function normalize_key(lhs)
  local leader = vim.g.mapleader == " " and lhs:sub(1, 1) == " "
  if leader then
    lhs = "<leader>" .. lhs:sub(2)
  end
  return (
    lhs:gsub("<([CMDAS])%-(%a)>", function(mod, key)
      return "<" .. mod .. "-" .. key:lower() .. ">"
    end)
  )
end

function M.collect()
  local rows = {}
  local index = {}

  for _, mode in ipairs({ "i", "n", "v", "s" }) do
    -- Buffer-local maps are marked because they beat the global one silently.
    -- `<leader>ca` is both an LSP code action and the CodeCompanion menu, and
    -- the sheet is worthless on that key if it cannot say which one answers.
    local scopes = {
      { vim.api.nvim_get_keymap(mode), "" },
      { vim.api.nvim_buf_get_keymap(0, mode), " (buf)" },
    }
    for _, scope in ipairs(scopes) do
      local maps, suffix = scope[1], scope[2]
      for _, map in ipairs(maps) do
        if owned(map.desc) then
          local source, action = split_desc(map.desc)
          source = source .. suffix
          local key = normalize_key(map.lhs)
          -- One row per binding, with the modes collected onto it. Without this
          -- a mapping set for { "i", "s", "v" } fills three lines of the sheet
          -- with the same text.
          local id = key .. "\0" .. source .. "\0" .. action
          local row = index[id]
          if row then
            if not row[1]:find(mode, 1, true) then
              row[1] = row[1] .. mode
            end
          else
            row = { mode, key, source, action }
            index[id] = row
            rows[#rows + 1] = row
          end
        end
      end
    end
  end

  vim.list_extend(rows, BLINK)

  table.sort(rows, function(a, b)
    local left, right = a[3]:lower(), b[3]:lower()
    if left ~= right then
      return left < right
    end
    return a[4] < b[4]
  end)

  return rows
end

local function format(rows)
  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row[2])
  end
  local lines = {}
  for _, row in ipairs(rows) do
    lines[#lines + 1] =
      string.format("%-4s %-" .. width .. "s  %-15s %s", row[1], row[2], row[3], row[4])
  end
  return lines
end

-- Fallback for a session where telescope has not loaded. Scratch buffer rather
-- than `:echo`, so the list can be searched and stays until dismissed.
local function float(rows)
  local lines = format(rows)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.min(width + 2, vim.o.columns - 4),
    height = math.min(#lines, vim.o.lines - 6),
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " AI, completion & LSP keys ",
  })
  vim.wo[win].cursorline = true

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<Cmd>close<CR>", { buffer = buf, nowait = true, silent = true })
  end
end

--- @param opts? { float?: boolean } float forces the static sheet over telescope.
function M.show(opts)
  local rows = M.collect()

  if opts and opts.float then
    return float(rows)
  end

  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return float(rows)
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local entry_display = require("telescope.pickers.entry_display")
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")

  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row[2])
  end

  local displayer = entry_display.create({
    separator = " ",
    items = { { width = 4 }, { width = width }, { width = 15 }, { remaining = true } },
  })

  pickers
    .new({}, {
      prompt_title = "AI, completion & LSP keys",
      finder = finders.new_table({
        results = rows,
        entry_maker = function(row)
          return {
            value = row,
            ordinal = table.concat(row, " "),
            display = function()
              return displayer({ row[1], row[2], { row[3], "Comment" }, row[4] })
            end,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr)
        -- Yank rather than execute: most of these only mean anything part way
        -- through an insert, which is not where the picker leaves you.
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(bufnr)
          if entry then
            vim.fn.setreg(vim.v.register or '"', entry.value[2])
            vim.notify("Yanked " .. entry.value[2], vim.log.levels.INFO)
          end
        end)
        return true
      end,
    })
    :find()
end

vim.api.nvim_create_user_command("Cheatsheet", function(cmd)
  M.show({ float = cmd.args == "float" })
end, {
  desc = "Cheat sheet: AI, completion and LSP keys",
  nargs = "?",
  complete = function()
    return { "float" }
  end,
})

vim.keymap.set("n", "<leader>sc", function()
  M.show()
end, { desc = "[s]earch [c]heat sheet: AI, completion, LSP" })

return M
