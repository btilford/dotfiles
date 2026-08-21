return {
  {
    "zaucy/mcos.nvim",
    dependencies = {
      "jake-stewart/multicursor.nvim",
    },
    config = function()
      local mcos = require("mcos")
      mcos.setup({})

      -- mcos doesn't setup any keymaps
      -- here are some recommended ones
      vim.keymap.set(
        { "n", "v" },
        "gms",
        mcos.opkeymapfunc,
        { expr = true, desc = "Multi-cursor: Add cursors by motion" }
      )
      vim.keymap.set(
        { "n" },
        "gmss",
        mcos.bufkeymapfunc,
        { desc = "Multi-cursor: Add cursors to buffer" }
      )
    end,
  },
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()

      local set = vim.keymap.set

      -- Add or skip cursor above/below the main cursor.
      set({ "n", "x" }, "<up>", function()
        mc.lineAddCursor(-1)
      end, { desc = "Multi-cursor: Add cursor above" })
      set({ "n", "x" }, "<down>", function()
        mc.lineAddCursor(1)
      end, { desc = "Multi-cursor: Add cursor below" })
      set({ "n", "x" }, "<leader><up>", function()
        mc.lineSkipCursor(-1)
      end, { desc = "Multi-cursor: Skip cursor above" })
      set({ "n", "x" }, "<leader><down>", function()
        mc.lineSkipCursor(1)
      end, { desc = "Multi-cursor: Skip cursor below" })

      -- Add or skip adding a new cursor by matching word/selection
      set({ "n", "x" }, "<leader>n", function()
        mc.matchAddCursor(1)
      end, { desc = "Multi-cursor: Match add next" })
      set({ "n", "x" }, "<leader>s", function()
        mc.matchSkipCursor(1)
      end, { desc = "Multi-cursor: Match skip next" })
      set({ "n", "x" }, "<leader>N", function()
        mc.matchAddCursor(-1)
      end, { desc = "Multi-cursor: Match add previous" })
      set({ "n", "x" }, "<leader>S", function()
        mc.matchSkipCursor(-1)
      end, { desc = "Multi-cursor: Match skip previous" })

      -- Add and remove cursors with control + left click.
      set("n", "<c-leftmouse>", mc.handleMouse, { desc = "Multi-cursor: Add cursor with mouse" })
      set("n", "<c-leftdrag>", mc.handleMouseDrag, { desc = "Multi-cursor: Drag add cursors" })
      set("n", "<c-leftrelease>", mc.handleMouseRelease, { desc = "Multi-cursor: Mouse release" })

      -- Disable and enable cursors.
      set({ "n", "x" }, "<c-q>", mc.toggleCursor, { desc = "Multi-cursor: Toggle cursor" })

      -- Mappings defined in a keymap layer only apply when there are
      -- multiple cursors. This lets you have overlapping mappings.
      mc.addKeymapLayer(function(layerSet)
        -- Select a different cursor as the main one.
        layerSet({ "n", "x" }, "<left>", mc.prevCursor, { desc = "Multi-cursor: Previous cursor" })
        layerSet({ "n", "x" }, "<right>", mc.nextCursor, { desc = "Multi-cursor: Next cursor" })

        -- Delete the main cursor.
        layerSet(
          { "n", "x" },
          "<leader>x",
          mc.deleteCursor,
          { desc = "Multi-cursor: Delete cursor" }
        )

        -- Enable and clear cursors using escape.
        layerSet("n", "<esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end, { desc = "Multi-cursor: Clear cursors" })
      end)

      -- Customize how cursors look.
      local hl = vim.api.nvim_set_hl
      hl(0, "MultiCursorCursor", { reverse = true })
      hl(0, "MultiCursorVisual", { link = "Visual" })
      hl(0, "MultiCursorSign", { link = "SignColumn" })
      hl(0, "MultiCursorMatchPreview", { link = "Search" })
      hl(0, "MultiCursorDisabledCursor", { reverse = true })
      hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
      hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
    end,
  },
}
