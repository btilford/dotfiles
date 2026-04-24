local sdkman_home = os.getenv("HOME") .. "/.sdkman/candidates/java"
local java21 = sdkman_home .. "/21.0.7-zulu"

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
									home = java21,

									eclipse = {
										downloadSources = true,
									},
									configuration = {
										updateBuildConfiguration = "interactive",
										-- Name must match a jdtls execution environment:
										-- https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line#initialize-request
										runtimes = {
											{
												name = "JavaSE-21",
												path = java21,
											},
											{
												name = "JavaSE-17",
												path = sdkman_home .. "/17.0.15-zulu",
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
									auto_install = false,
									-- Match the installed version
									version = "21.0.7",
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
