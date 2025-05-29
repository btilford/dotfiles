local sdkman_home = os.getenv("HOME") .. "/.sdkman/candidates/java"
return {
	-- {
	-- 	"mfussenegger/nvim-jdtls",
	-- 	-- ft = "java",
	-- },
	{
		"nvim-java/nvim-java",
		config = false,
		dependencies = {
			{
				"neovim/nvim-lspconfig",
				opts = {
					servers = {
						-- Your JDTLS configuration goes here
						jdtls = {
							settings = {
								java = {
									home = sdkman_home .. "/21.0.6-graal",

									eclipse = {
										downloadSources = true,
									},
									configuration = {
										updateBuildConfiguration = "interactive",
										-- The runtimes' name parameter needs to match a specific Java execution environments.  See https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line#initialize-request and search "ExecutionEnvironment".
										runtimes = {
											{
												name = "Graal 21",
												path = sdkman_home .. "/21.0.6-graal",
											},
										},
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
									format = {
										enabled = true,
										-- Formatting works by default, but you can refer to a specific file/URL if you choose
										-- settings = {
										--   url = "https://github.com/google/styleguide/blob/gh-pages/intellij-java-google-style.xml",
										--   profile = "GoogleStyle",
										-- },
									},
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
										importOrder = {
											"java",
											"javax",
											"com",
											"org",
										},
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

									-- java = {
									-- 	configuration = {
									-- 		runtimes = {
									-- 			{
									-- 				default = true,
									-- 				name = "graal-v21",
									-- 				path = "~/.sdkman/candidates/java/21.0.6-graalk",
									-- 			},
									-- 		},
									-- 	},
									-- },
								},
							},
						},
					},
					setup = {
						jdtls = function()
							-- your nvim-java configuration goes here
							require("java").setup({
								root_markers = {
									"settings.gradle",
									"settings.gradle.kts",
									"pom.xml",
									"build.gradle",
									"mvnw",
									"gradlew",
									"build.gradle",
									"build.gradle.kts",
								},
								-- java_test = {
								-- 	enable = true,
								-- },
								-- java_debug_adapter = {
								-- 	enable = true,
								-- },
								-- spring_boot_tools = {
								-- 	enable = true,
								-- },
								jdk = {
									auto_install = false,
									version = "21.0.6",
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
