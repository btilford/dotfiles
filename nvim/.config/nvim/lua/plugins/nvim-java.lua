-- JDK homes come from mise (sdkman was removed 2026-08-14). Nothing here is a
-- hardcoded version path: metapac declares `java@temurin-25` and any extra JDK is
-- added per machine with `mise use -g java@temurin-21`, so this resolves whatever
-- is actually installed and silently drops the runtimes that are not.
--
-- A glob rather than `mise where java@25`: this table is built when the plugin
-- spec is sourced, and a subprocess there costs startup time on every nvim launch
-- including the ones that never touch Java. It also keeps working when nvim is
-- started from a desktop entry, whose environment has no mise on PATH.
local function mise_installs_dir()
  local explicit = os.getenv("MISE_DATA_DIR")
  if explicit and explicit ~= "" then
    return explicit .. "/installs/java"
  end
  local data = os.getenv("XDG_DATA_HOME")
  if not data or data == "" then
    data = os.getenv("HOME") .. "/.local/share"
  end
  return data .. "/mise/installs/java"
end

-- macOS JDK tarballs carry a Contents/Home wrapper; mise flattens most of them,
-- but not every distribution. Accept either shape, and only if java is really there.
local function java_home(dir)
  for _, home in ipairs({ dir, dir .. "/Contents/Home" }) do
    if vim.fn.executable(home .. "/bin/java") == 1 then
      return home
    end
  end
  return nil
end

-- Strip the vendor prefix: everything up to the first `-` that a digit follows.
-- Not `^%a[%w_]*%-`, which only removes one segment and so leaves
-- graalvm-community-21.0.2 unmatchable. A name with no vendor (17.0.2) is left
-- alone, and temurin-latest keeps its prefix and matches no major, as intended.
local function version_of(name)
  local version = name:gsub("^.-%-(%d)", "%1")
  return version
end

-- Match on that version, anchored at the major. A plain `*17*` glob would also
-- match zulu-21.48.17.0 — vendor build numbers make substring matching wrong.
local function find_jdk(major)
  local found = {}
  for _, dir in ipairs(vim.fn.glob(mise_installs_dir() .. "/*", true, true)) do
    local name = vim.fn.fnamemodify(dir, ":t")
    local version = version_of(name)
    if version == major or version:match("^" .. major .. "[%.%-+_]") then
      local home = java_home(dir)
      if home then
        table.insert(found, { name = name, home = home })
      end
    end
  end
  -- Highest build wins when several of one major are installed.
  table.sort(found, function(a, b)
    return a.name < b.name
  end)
  return found[#found]
end

-- Newest first: the primary JDK is whichever of these is present.
local wanted = { "25", "21", "17" }

local runtimes = {}
local primary = nil
for _, major in ipairs(wanted) do
  local jdk = find_jdk(major)
  if jdk then
    primary = primary or jdk
    table.insert(runtimes, {
      -- Must match a jdtls execution environment name:
      -- https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line#initialize-request
      name = "JavaSE-" .. major,
      path = jdk.home,
    })
  end
end

-- Leaving `home` nil when no mise JDK is installed is deliberate: jdtls then falls
-- back to JAVA_HOME / the java on PATH, which is strictly better than pointing it
-- at a path that does not exist (what the old sdkman constant did on this Mac).
local java_home_primary = primary and primary.home or nil

-- "temurin-25.0.4+7.0.LTS" -> "25.0.4": drop the build suffix too, leaving the
-- plain JDK version nvim-java expects.
local primary_version = primary and (version_of(primary.name):gsub("%+.*$", "")) or nil

return {
  {
    "nvim-java/nvim-java",
    config = false,
    dependencies = {
      {
        "neovim/nvim-lspconfig",
        opts = {
          servers = {
            jdtls = {
              settings = {
                java = {
                  home = java_home_primary,

                  eclipse = {
                    downloadSources = true,
                  },
                  configuration = {
                    updateBuildConfiguration = "interactive",
                    runtimes = runtimes,
                  },
                  maven = {
                    downloadSources = true,
                  },
                  implementationsCodeLens = {
                    enabled = true,
                  },
                  referencesCodeLens = {
                    enabled = true,
                  },
                  references = {
                    includeDecompiledSources = true,
                  },
                  signatureHelp = { enabled = true },
                  format = { enabled = true },
                  completion = {
                    favoriteStaticMembers = {
                      "org.hamcrest.MatcherAssert.assertThat",
                      "org.hamcrest.Matchers.*",
                      "org.hamcrest.CoreMatchers.*",
                      "org.junit.jupiter.api.Assertions.*",
                      "java.util.Objects.requireNonNull",
                      "java.util.Objects.requireNonNullElse",
                      "org.mockito.Mockito.*",
                    },
                    importOrder = { "java", "javax", "com", "org" },
                  },
                  sources = {
                    organizeImports = {
                      starThreshold = 9999,
                      staticStarThreshold = 9999,
                    },
                  },
                  codeGeneration = {
                    toString = {
                      template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
                    },
                    useBlocks = true,
                  },
                },
              },
            },
          },
          setup = {
            jdtls = function()
              require("java").setup({
                root_markers = {
                  "settings.gradle",
                  "settings.gradle.kts",
                  "pom.xml",
                  "build.gradle",
                  "build.gradle.kts",
                  "mvnw",
                  "gradlew",
                },
                jdk = {
                  -- mise owns the JDK, so nvim-java must not install one of its
                  -- own; `version` is only consulted when auto_install is true,
                  -- and is derived rather than pinned so the two cannot disagree.
                  auto_install = false,
                  version = primary_version,
                },
                notifications = {
                  dap = true,
                },
                mason = {
                  registries = {
                    "github:nvim-java/mason-registry",
                  },
                },
              })
            end,
          },
        },
      },
    },
  },
}
