# docker — MCP Gateway configuration

Stow package. `stow --no-folding docker` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.docker/mcp/tools.yaml` | `~/.docker/mcp/tools.yaml` |
| `.docker/mcp/config.example.yaml` | `~/.docker/mcp/config.example.yaml` |
| `.docker/mcp/README.md` | *(not stowed — stow ignores `README.*`)* |

Runs MCP servers as containers through Docker's MCP Gateway, so each server is
isolated and its credentials live outside the tool that uses them.
`.docker/mcp/README.md` in this package is the full setup guide.

## `config.yaml` is untracked — provision it

The real `~/.docker/mcp/config.yaml` holds a **Google app password** for the gmail
MCP server, plus a personal address and machine-local paths. It is in
`.gitignore`, and excluded from `mise-scripts/yaml-files.sh` so a provisioned
machine's lint run agrees with CI's (CI sees a fresh clone, where the file does
not exist).

```sh
cp ~/.docker/mcp/config.example.yaml ~/.docker/mcp/config.yaml
$EDITOR ~/.docker/mcp/config.yaml    # then chmod 600
```

The example is linted normally, so keep it in valid YAML with placeholder values.

`.gitleaks.toml` carries a custom `google-app-password` rule because one was
committed here before this rule existed. Don't remove it.

Secrets (`.env`, `registry.yaml`, `catalogs/`) are written by the gateway itself
and are not tracked.
