local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
-- map("<leader>", "e", "Treesitter file_browser")
-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Diagnostic keymaps
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- TIP: Disable arrow keys in normal mode
-- vim.keymap.set("n", "<left>", '<cmd>echo "Use h to move!!"<CR>')
-- vim.keymap.set("n", "<right>", '<cmd>echo "Use l to move!!"<CR>')
-- vim.keymap.set("n", "<up>", '<cmd>echo "Use k to move!!"<CR>')
-- vim.keymap.set("n", "<down>", '<cmd>echo "Use j to move!!"<CR>')
--
-- Keybinds to make split navigation easier.
--  Use ALT+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set("n", "<C-Right>", "<C-w><C-l>", { desc = "Move focus to the right window" })
vim.keymap.set("n", "<C-Left>", "<C-w><C-h>", { desc = "Move focus to the left window" })
vim.keymap.set("n", "<C-Down>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
vim.keymap.set("n", "<C-Up>", "<C-w><C-k>", { desc = "Move focus to the upper window" })
vim.keymap.set('n', '<leader>bn', ':bnext<CR>', {desc = 'Next buffer '})
vim.keymap.set('n', '<leader>bp', ':bprevious<CR>', {desc = 'Previous buffer '})
vim.keymap.set('n', '<leader>bb', '<cmd>e #<cr>', {desc = 'Switch to other buffer'})

-- NOTE: Some terminals have colliding keymaps or are not able to send distinct keycodes
vim.keymap.set("n", "<C-S-h>", "<C-w>H", { desc = "Move window to the left" })
vim.keymap.set("n", "<C-S-l>", "<C-w>L", { desc = "Move window to the right" })
vim.keymap.set("n", "<C-S-j>", "<C-w>J", { desc = "Move window to the lower" })
vim.keymap.set("n", "<C-S-k>", "<C-w>K", { desc = "Move window to the upper" })

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end,
})

vim.keymap.set("n", ",p", '"0p', { desc = "Paste from the default register" })
vim.keymap.set("x", ",p", '"0p', { desc = "Paste from the default register" })

vim.keymap.set("x", "<C-d>", "<C-d>zz", { noremap = true, desc = "Scroll down and extend selection" })
vim.keymap.set("x", "<C-u>", "<C-u>zz", { noremap = true, desc = "Scroll up and extend selection" })

-- visual lines
vim.keymap.set({'n', 'x'}, 'j', "v:count == 0 ? 'gj' : 'j'", { desc = 'Down', expr = true, silent = true})
vim.keymap.set({'n', 'x'}, 'k', "v:count == 0 ? 'gk' : 'k'", { desc = 'Up', expr = true, silent = true})


-- Move lines up/down (Alt+j/k like VSCode)

map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move Down" })
map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move Up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
map("v", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move Down" })
map("v", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move Up" })

-- Alternative line movement (for terminals that don't support Alt)
-- map("v", "J", ":move '>+1<CR>gv=gv", { desc = "Move Block Down" })
-- map("v", "K", ":move '<-2<CR>gv=gv", { desc = "Move Block Up" })
-- map("n", "<A-Down>", ":m .+1<CR>", opts)
-- map("n", "<A-Up>", ":m .-2<CR>", opts)
-- map("i", "<A-Down>", "<Esc>:m .+1<CR>==gi", opts)
-- map("i", "<A-Up>", "<Esc>:m .-2<CR>==gi", opts)
-- map("v", "<A-Down>", ":m '>+1<CR>gv=gv", opts)
-- map("v", "<A-Up>", ":m '<-2<CR>gv=gv", opts)
--
-- Select all content
map("n", "==", "gg<S-v>G")
map("n", "<A-a>", "ggVG", { noremap = true, silent = true, desc = "Select all" })


-- Better indenting (stay in visual mode)
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Commenting (add comment above/below current line)
map("n", "gco", "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", { desc = "Add Comment Below" })
map("n", "gcO", "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", { desc = "Add Comment Above" })

