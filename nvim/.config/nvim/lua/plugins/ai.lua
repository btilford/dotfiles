-- A WORK MACHINE MUST NOT REACH THE HOMELAB GATEWAY. This is a hard
-- requirement, not a preference: that gateway, its models and its hostnames
-- must not be contacted from, or named on, the work laptop.
--
-- The gate tests the ENDPOINT, not the machine's identity. A profile check
-- answers "whose laptop is this", which is the wrong question — what matters is
-- where the buffer text goes. An endpoint on this host's loopback is safe
-- anywhere; a remote one is not, whatever the profile says. Keying on the
-- profile also made "work" mean "no AI at all", which blocks the supported
-- case: an inference server running on the work machine itself.
--
-- Three variables, in order of authority:
--
--   DOTFILES_AI=off   kill switch. Nothing loads, whatever else is set.
--   AI_GATEWAY        this host's OpenAI-compatible endpoint. Falls back to
--                     LITELLM_GATEWAY so the homelab keeps working unchanged.
--   DOTFILES_PROFILE  "personal" permits a remote gateway. Anything else, or
--                     unset, permits loopback only.
--
-- Absence of a gateway means OFF, never "try somewhere else". That rule is why
-- the inferred gate it replaced was harmful:
--
--   local litellm = vim.env.LITELLM_GATEWAY or "http://localhost:4000"
--
-- With the variable unset it disabled nothing — it loaded every adapter pointed
-- at localhost:4000, so the plugins appeared installed and failed only at the
-- moment of use, looking like a network fault rather than a machine that was
-- never meant to have them. Same rule as the empty ATUIN_* variables in the
-- repo CLAUDE.md.
local gateway = vim.env.AI_GATEWAY or vim.env.LITELLM_GATEWAY

-- Loopback literals only. A hostname that merely resolves to 127.0.0.1 today is
-- not the same guarantee — DNS can move, and this decides whether work code
-- leaves the machine.
local function is_loopback(url)
  if not url then
    return false
  end
  -- Bracketed IPv6 first: "[^/:]+" would otherwise stop at the first colon of
  -- "[::1]" and return "[", which is truthy and short-circuits the `or`.
  local host = url:match("^https?://%[([^%]]+)%]") or url:match("^https?://([^/:]+)")
  return host == "127.0.0.1" or host == "localhost" or host == "::1"
end

local local_ai
if vim.env.DOTFILES_AI == "off" or gateway == nil or gateway == "" then
  local_ai = false
elseif (vim.env.DOTFILES_PROFILE or "work") == "personal" then
  local_ai = true
else
  local_ai = is_loopback(gateway)
end

-- Named for the variable that supplies it, not for whatever happens to be
-- serving: LiteLLM on the homelab, Ollama on a laptop. The adapters below only
-- load when local_ai is true, so this is never nil at a use site.
local litellm = gateway

-- The API key is NOT read from the environment. Nothing exports it, nothing
-- caches it to disk, and no shell calls infisical at startup — see
-- commands/.local/bin/dotfiles-secrets for why. It is fetched at the moment an
-- adapter actually needs it.
--
-- Every call site below passes this function rather than a value, so the fetch
-- happens on first AI request instead of at config load. A logged-out infisical
-- therefore costs an error when you use AI, not a broken nvim startup, and never
-- the old failure mode: the literal string "missing-NEOVIM_API_KEY" silently sent
-- as a credential.
--
-- THE RESULT MUST BE MEMOISED, and this is not an optimisation — it is the
-- difference between a usable editor and an unusable one.
--
-- "at the moment an adapter actually needs it" turned out to mean *every
-- keystroke*. minuet is registered as a blink source (see blink.lua), and blink
-- calls `source:enabled()` on every completion trigger; that reaches
-- `minuet/backends/openai_compatible.lua:is_available()`, which calls
-- `utils.get_api_key(options.api_key)`, which invokes this function. The request
-- builder (`openai_base.lua`) calls it again per request. So one character typed
-- ran a synchronous `vim.fn.system()` on the UI thread.
--
-- Measured 2026-08-09, with the session cache warm: ~3ms per call — a fork+exec
-- of a shell script, per keystroke, for a value that cannot change mid-session.
-- With the cache MISSING (dotfiles-secrets.service had failed at login and stayed
-- failed for 27h) `--get` falls through to the network: 450-540ms per call, i.e.
-- half a second of frozen editor per character. That was the whole bug.
--
-- A failure is cached too, with a cooldown rather than forever: caching it
-- permanently would mean a fetch that failed once needs a full nvim restart even
-- after `secrets-refresh`, and NOT caching it puts the slow path back on every
-- keystroke exactly when it is slowest.
local api_key_cache = nil
local api_key_retry_after = 0
local API_KEY_RETRY_COOLDOWN_S = 60

local function neovim_api_key()
  -- A loopback gateway is this machine's own inference server and takes no
  -- auth, so there is no key to fetch. Short-circuit before the shell-out:
  -- everything in the comment above about per-keystroke cost applies here too,
  -- and on a machine with no Infisical access this would otherwise buy a 60s
  -- error cooldown, plus an error toast, for a credential nothing wants. The
  -- adapters require a non-nil value, hence a placeholder rather than nil.
  if is_loopback(gateway) then
    return "local"
  end

  if api_key_cache then
    return api_key_cache
  end
  if os.time() < api_key_retry_after then
    return nil
  end

  local key = vim.fn.system({ "dotfiles-secrets", "--get", "NEOVIM_API_KEY" })
  if vim.v.shell_error ~= 0 then
    -- dotfiles-secrets already logged the specific reason to
    -- ~/.local/state/dotfiles/secrets.log; surface it here so it is not silent.
    api_key_retry_after = os.time() + API_KEY_RETRY_COOLDOWN_S
    vim.notify(
      "NEOVIM_API_KEY unavailable — see ~/.local/state/dotfiles/secrets.log\n"
        .. vim.trim(key or ""),
      vim.log.levels.ERROR,
      { title = "dotfiles-secrets" }
    )
    return nil
  end

  api_key_cache = vim.trim(key)
  return api_key_cache
end

-- Escape hatch for the memoisation above: after `secrets-refresh` rotates the key,
-- this drops the cached copy so the next AI request picks up the new one without
-- restarting nvim.
vim.api.nvim_create_user_command("SecretsForget", function()
  api_key_cache = nil
  api_key_retry_after = 0
  vim.notify("NEOVIM_API_KEY cache cleared", vim.log.levels.INFO, { title = "dotfiles-secrets" })
end, { desc = "Forget the memoised NEOVIM_API_KEY (after secrets-refresh)" })

return {
  {
    "NickvanDyke/opencode.nvim",
    -- Loads only when an AI gateway is configured and permitted; see the top of this file.
    cond = local_ai,
    dependencies = {
      -- Recommended for `ask()` and `select()`.
      -- Required for `snacks` provider.
      ---@module 'snacks' <- Loads `snacks.nvim` types for configuration intellisense.
      { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        -- Your configuration, if any — see `lua/opencode/config.lua`, or "goto definition".
      }

      -- Required for `opts.events.reload`.
      vim.o.autoread = true

      -- Recommended/example keymaps.
      vim.keymap.set({ "n", "x" }, "<A-a>", function()
        require("opencode").ask("@this: ", { submit = true })
      end, { desc = "AI (OpenCode): Ask about this" })
      vim.keymap.set({ "n", "x" }, "<A-x>", function()
        require("opencode").select()
      end, { desc = "AI (OpenCode): Action menu" })
      vim.keymap.set({ "n", "x" }, "ga", function()
        require("opencode").prompt("@this")
      end, { desc = "AI (OpenCode): Add to context" })
      vim.keymap.set({ "n", "t" }, "<C-.>", function()
        require("opencode").toggle()
      end, { desc = "AI (OpenCode): Toggle panel" })
      vim.keymap.set("n", "<S-C-u>", function()
        require("opencode").command("session.half.page.up")
      end, { desc = "AI (OpenCode): Scroll up" })
      vim.keymap.set("n", "<S-C-d>", function()
        require("opencode").command("session.half.page.down")
      end, { desc = "AI (OpenCode): Scroll down" })
      -- You may want these if you stick with the opinionated "<C-a>" and "<C-x>" above — otherwise consider "<leader>o".
      vim.keymap.set("n", "+", "<C-a>", { desc = "Increment", noremap = true })
      vim.keymap.set("n", "-", "<C-x>", { desc = "Decrement", noremap = true })
    end,
  },
  {
    "github/copilot.vim",
    -- DISABLED 2026-08-09. Not lazily loaded and not gated — it was the one AI
    -- plugin in this file with neither `cond = local_ai` nor a load event, so it
    -- started its Node agent on every nvim regardless of DOTFILES_PROFILE and
    -- requested inline suggestions on every keystroke. That put a second
    -- completion engine on the same hot path as minuet (registered as a blink
    -- source in blink.lua), for no benefit — minuet through LiteLLM is the
    -- intended completion provider here.
    --
    -- `enabled = false` rather than `cond = local_ai`: cond still installs the
    -- plugin and only skips loading it, and there is no machine where this one
    -- is wanted. Gating it to personal machines would also have left the leak
    -- the file's opening comment forbids — a work laptop running Copilot with no
    -- deliberate decision behind it.
    --
    -- Re-enabling means deciding what owns insert-mode completion first. Two
    -- engines racing on every keystroke is the state this removed, and the
    -- keymaps below still claim <C-m>/<C-x>/<C-/>/<C-\> when they come back.
    enabled = false,
    config = function()
      vim.g.copilot_no_tab_map = true
      vim.g.copilot_assume_mapped = true
      -- vim.keymap.set("i", "<C-a>",  "copilot#Accept()",           { expr = true, silent = true, noremap = false, desc = "AI (Copilot): Accept suggestion" })
      vim.keymap.set(
        "i",
        "<C-m>",
        "copilot#Next()",
        { expr = true, silent = true, noremap = false, desc = "AI (Copilot): Next suggestion" }
      )
      vim.keymap.set(
        "i",
        "<C-M>",
        "copilot#Previous()",
        { expr = true, silent = true, noremap = false, desc = "AI (Copilot): Previous suggestion" }
      )
      vim.keymap.set(
        "i",
        "<C-x>",
        "copilot#Clear()",
        { expr = true, silent = true, noremap = false, desc = "AI (Copilot): Clear suggestion" }
      )
      vim.keymap.set(
        "i",
        "<C-/>",
        "copilot#Dismiss()",
        { expr = true, silent = true, noremap = false, desc = "AI (Copilot): Dismiss suggestion" }
      )
      vim.keymap.set(
        "i",
        "<C-\\>",
        "copilot#Complete()<Esc><CR>",
        { expr = true, silent = true, noremap = false, desc = "AI (Copilot): Complete and insert" }
      )
    end,
  },
  -- Custom Parameters (with defaults)
  {
    -- ka codium
    "David-Kunz/gen.nvim",
    -- Loads only when an AI gateway is configured and permitted; see the top of this file.
    cond = local_ai,
    opts = {
      model = "qwen3-coder-next", -- The default model to use.
      quit_map = "q", -- set keymap to close the response window
      retry_map = "<c-r>", -- set keymap to re-send the current prompt
      accept_map = "<c-cr>", -- set keymap to replace the previous selection with the last result
      host = vim.env.OLLAMA_HOST or "localhost", -- The host running the Ollama service.
      port = "11434", -- The port on which the Ollama service is listening.
      display_mode = "float", -- The display mode. Can be "float" or "split" or "horizontal-split" or "vertical-split".
      show_prompt = false, -- Shows the prompt submitted to Ollama. Can be true (3 lines) or "full".
      show_model = false, -- Displays which model you are using at the beginning of your chat session.
      no_auto_close = false, -- Never closes the window automatically.
      file = false, -- Write the payload to a temporary file to keep the command short.
      hidden = false, -- Hide the generation window (if true, will implicitly set `prompt.replace = true`), requires Neovim >= 0.10
      init = function()
        -- Ollama host is machine-local: set OLLAMA_HOST in ~/.config/dotfiles/local.env
      end,
      -- Function to initialize Ollama
      command = function(options)
        -- `$body` below is gen.nvim's own placeholder — the plugin builds and
        -- shellescapes the JSON payload itself, so nothing is constructed here.
        return string.format(
          "curl --silent --no-buffer -X POST http://%s:%s/api/chat -d $body",
          options.host,
          options.port
        )
      end,
      -- The command for the Ollama service. You can use placeholders $prompt, $model and $body (shellescaped).
      -- This can also be a command string.
      -- The executed command must return a JSON object with { response, context }
      -- (context property is optional).
      -- list_models = '<omitted lua function>', -- Retrieves a list of model names
      result_filetype = "markdown", -- Configure filetype of the result buffer
      debug = false, -- Prints errors and the command which is run.
    },
  },
  -- {
  -- 	"Exafunction/windsurf.vim",
  -- 	event = "BufEnter",
  -- 	config = function()
  -- 		-- Change '<C-g>' here to any keycode you like.
  -- 		vim.keymap.set("i", "<C-g>", function()
  -- 			return vim.fn["codeium#Accept"]()
  -- 		end, { expr = true, silent = true })
  -- 		vim.keymap.set("i", "<c-;>", function()
  -- 			return vim.fn["codeium#CycleCompletions"](1)
  -- 		end, { expr = true, silent = true })
  -- 		vim.keymap.set("i", "<c-,>", function()
  -- 			return vim.fn["codeium#CycleCompletions"](-1)
  -- 		end, { expr = true, silent = true })
  -- 		vim.keymap.set("i", "<c-x>", function()
  -- 			return vim.fn["codeium#Clear"]()
  -- 		end, { expr = true, silent = true })
  -- 	end,
  -- },
  {
    "olimorris/codecompanion.nvim",
    -- Loads only when an AI gateway is configured and permitted; see the top of this file.
    cond = local_ai,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "echasnovski/mini.diff",
    },
    config = function()
      local map = vim.keymap.set

      map(
        { "n", "v" },
        "<leader>cc",
        "<cmd>CodeCompanionChat Toggle<cr>",
        { desc = "AI (CodeCompanion): Toggle chat" }
      )
      map(
        { "n", "v" },
        "<leader>ca",
        "<cmd>CodeCompanionActions<cr>",
        { desc = "AI (CodeCompanion): Actions menu" }
      )
      map("v", "<leader>ci", "<cmd>CodeCompanion<cr>", { desc = "AI (CodeCompanion): Inline edit" })
      map(
        "v",
        "<leader>ce",
        "<cmd>CodeCompanion /explain<cr>",
        { desc = "AI (CodeCompanion): Explain code" }
      )

      require("codecompanion").setup({
        adapters = {
          -- Reasoning/chat model — Lemonade via LiteLLM
          litellm_chat = function()
            return require("codecompanion.adapters").extend("openai_compatible", {
              env = {
                url = litellm,
                api_key = neovim_api_key,
                chat_url = "/v1/chat/completions",
              },
              schema = {
                model = { default = "role/reasoning" },
                max_tokens = { default = 8192 },
                temperature = { default = 0.6 },
              },
            })
          end,

          -- Fast inline model — Ollama via LiteLLM
          litellm_inline = function()
            return require("codecompanion.adapters").extend("openai_compatible", {
              env = {
                url = litellm,
                api_key = neovim_api_key,
                chat_url = "/v1/chat/completions",
              },
              schema = {
                model = { default = "role/completion" },
                max_tokens = { default = 2048 },
                temperature = { default = 0.2 },
              },
            })
          end,
        },

        strategies = {
          chat = { adapter = "litellm_chat" },
          inline = { adapter = "litellm_inline" },
          agent = { adapter = "litellm_chat" },
        },

        display = {
          chat = {
            window = {
              layout = "vertical",
              width = 0.40,
            },
            show_settings = true,
          },
          diff = { provider = "mini_diff" },
        },

        opts = {
          log_level = "ERROR",
          send_code = true,
          use_default_actions = true,
          use_default_prompt_library = true,
        },
      })

      -- role/reasoning is a 35B on the homelab and has no local equivalent: the
      -- largest model that belongs on a laptop is an 8B. Chat and agent are
      -- left pointing at it deliberately, so they fail with a missing-model
      -- error rather than quietly answering from something a quarter the size —
      -- a silent downgrade on agent work is the worse outcome. Inline edits use
      -- role/completion and work normally.
      if is_loopback(gateway) then
        vim.notify(
          "chat and agent need role/reasoning, which this host does not serve.\n"
            .. "Inline edits and minuet completion are unaffected.",
          vim.log.levels.WARN,
          { title = "codecompanion" }
        )
      end
    end,
  },

  {
    "milanglacier/minuet-ai.nvim",
    -- Loads only when an AI gateway is configured and permitted; see the top of this file.
    cond = local_ai,
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("minuet").setup({
        provider = "openai_compatible",
        provider_options = {
          openai_compatible = {
            model = "role/completion",
            end_point = litellm .. "/v1/chat/completions",
            api_key = neovim_api_key,
            stream = true,
            optional = {
              max_tokens = 256,
              temperature = 0.2,
              top_p = 0.95,
              stop = { "```" },
            },
          },
        },
        context_window = 4096,
        context_ratio = 0.75,

        -- Tuned to the round trip, which differs by an order of magnitude
        -- between the two backends this file serves. Measured on the local
        -- Ollama, 2026-08-31: role/completion (qwen2.5-coder:3b) answers in
        -- 171ms to first token at 57 tok/s, warm and fully on GPU. The previous
        -- 1000/400 was fitted to the homelab gateway across the network, and at
        -- local latency it is the dominant cost — it makes a fast model feel
        -- slower than it is.
        --
        -- These are a floor, not a target: too low and every keystroke burns a
        -- request the next keystroke discards, which on a laptop is battery and
        -- heat rather than someone else's GPU.
        throttle = is_loopback(gateway) and 400 or 1000,
        debounce = is_loopback(gateway) and 150 or 400,
        notify = false,
        virtualtext = {
          auto_trigger_ft = {},
          -- keymap managed via explicit vim.keymap.set below for telescope/fzf searchability
        },
      })

      -- Explicit keymaps so they appear in telescope/fzf keymap search
      vim.keymap.set("i", "<Tab>", function()
        require("minuet").accept()
      end, { desc = "AI (Minuet): Accept completion", silent = true })
      vim.keymap.set("i", "<S-Tab>", function()
        require("minuet").accept_line()
      end, { desc = "AI (Minuet): Accept line", silent = true })
      vim.keymap.set("i", "<C-y>", function()
        require("minuet").complete()
      end, { desc = "AI (Minuet): Trigger completion", silent = true })
      vim.keymap.set("i", "<C-k>", function()
        require("minuet").prev()
      end, { desc = "AI (Minuet): Previous suggestion", silent = true })
      vim.keymap.set("i", "<C-j>", function()
        require("minuet").next()
      end, { desc = "AI (Minuet): Next suggestion", silent = true })
      vim.keymap.set("i", "<C-e>", function()
        require("minuet").dismiss()
      end, { desc = "AI (Minuet): Dismiss completion", silent = true })
    end,
  },
}
