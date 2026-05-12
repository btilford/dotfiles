# Docker MCP Gateway Setup

This directory contains the configuration and secrets for running MCP (Model Context Protocol) servers through Docker's MCP Gateway on Linux.

## Overview

Docker's MCP Gateway allows you to run containerized MCP servers that provide tools and capabilities to AI assistants like Claude. This setup enables:

- **Isolated execution**: Each MCP server runs in its own container
- **Easy management**: Configure multiple servers through YAML files
- **Secure secrets**: API keys stored separately from configuration
- **Large catalog**: Access to dozens of pre-built MCP servers

## Directory Structure

```
~/.docker/mcp/
├── .env                    # API keys and secrets (DO NOT commit!)
├── config.yaml            # Server-specific configuration
├── registry.yaml          # List of enabled MCP servers
├── catalog.json           # Catalog metadata
└── catalogs/
    └── docker-mcp.yaml    # Full catalog of available servers
```

## Files Explained

### `.env` - Secrets File
Contains API keys and authentication tokens. This file has `600` permissions (owner read/write only) for security.

**Format:**
```bash
service.secret_name=YOUR_SECRET_VALUE
```

**Important:** Never commit this file to version control!

### `config.yaml` - Server Configuration
Contains non-secret configuration for MCP servers that need additional parameters (like connection strings, email addresses, etc.).

### `registry.yaml` - Enabled Servers
Lists all MCP servers that are currently installed/enabled in your setup. Each entry has a `ref` field that tracks the specific version.

### `catalog.json` - Catalog Metadata
Points to the Docker MCP catalog URL and tracks the last update time.

### `catalogs/docker-mcp.yaml` - Available Servers
Complete catalog of all available MCP servers from Docker's registry. Browse this file to discover new servers to add.

## Current Setup

This installation currently has the following servers enabled:

- **GitHub Official** - Interact with GitHub repositories, issues, and pull requests
- **Brave Search** - Search the web using Brave's search API

## Secrets Format

The `.env` file stores secrets in this format:

```bash
# GitHub Personal Access Token
github.personal_access_token=YOUR_GITHUB_TOKEN_HERE

# Brave Search API Key
brave.api_key=YOUR_BRAVE_KEY_HERE
```

Each secret follows the pattern: `service_name.secret_key=value`

## Getting API Keys

### GitHub Personal Access Token

1. Visit: https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Give it a descriptive name (e.g., "MCP Server Access")
4. Select scopes:
   - `repo` - Full control of repositories (for read/write operations)
   - Or just `public_repo` if you only need public repository access
5. Generate and copy the token
6. Add to `.env`: `github.personal_access_token=ghp_your_token_here`

### Brave Search API Key

1. Visit: https://brave.com/search/api/
2. Sign up for a free account (1,000 queries/month free tier available)
3. Get your API key from the dashboard
4. Add to `.env`: `brave.api_key=YOUR_KEY_HERE`

## Adding New Servers

### Step 1: Browse the Catalog

Look through `catalogs/docker-mcp.yaml` to find available servers. Each entry shows:
- **title**: Human-readable name
- **description**: What the server does
- **secrets**: Required API keys (if any)
- **config**: Additional configuration needed

### Step 2: Add Secrets

If the server requires secrets, add them to `.env`:

```bash
# Example: Adding Notion server
notion.internal_integration_token=ntn_YOUR_TOKEN_HERE

# Example: Adding Elasticsearch
elasticsearch.api_key=YOUR_API_KEY
```

### Step 3: Add Configuration

If the server needs non-secret configuration, add it to `config.yaml`:

```yaml
notion:
  workspace_id: "your-workspace-id"

elasticsearch:
  url: "https://your-elasticsearch-instance.com"
```

### Step 4: Enable in Registry

Add the server to `registry.yaml`:

```yaml
registry:
  notion:
    ref: ""
  elasticsearch:
    ref: ""
```

### Step 5: Update OpenCode Config

If you're using OpenCode, update your OpenCode configuration to include the new MCP server in your AI assistant's configuration.

## Troubleshooting

### Error: `/.s0` not found

**Problem**: The secrets file path is incorrect or not specified.

**Solution**: Make sure you're using the `--secrets` flag when starting the MCP gateway:
```bash
--secrets=/home/btilford/.docker/mcp/.env
```

### Connection Errors

**Problem**: MCP server fails to connect to external APIs.

**Solution**: 
1. Verify API keys are correct in `.env`
2. Check that keys haven't expired
3. Ensure the service account has necessary permissions

### Server Fails to Start

**Problem**: Container won't start or crashes immediately.

**Solution**:
1. Check Docker daemon is running: `docker ps`
2. Verify the server's required configuration is provided
3. Check Docker logs: `docker logs <container-id>`
4. Ensure all required secrets are present in `.env`

### Permission Denied on `.env`

**Problem**: Cannot read or write to `.env` file.

**Solution**: Check file permissions:
```bash
chmod 600 ~/.docker/mcp/.env
```

### API Rate Limits

**Problem**: Getting rate limit errors from services.

**Solution**:
- Check your API plan limits
- Consider upgrading to a paid tier
- Implement caching or reduce request frequency

## Security Best Practices

### File Permissions

The `.env` file should have restrictive permissions:
```bash
chmod 600 ~/.docker/mcp/.env  # Owner read/write only
```

### Version Control

Never commit secrets to git. Your `.env` file should be in `.gitignore`:
```bash
echo ".env" >> ~/.gitignore
```

### API Key Rotation

- Rotate API keys regularly (every 90 days recommended)
- Immediately rotate if a key is exposed
- Use minimum required permissions for each key

### Key Management

- **Don't share** API keys in chat, email, or public channels
- **Don't hardcode** keys in scripts or configuration
- **Use separate keys** for development and production
- **Monitor usage** through provider dashboards

### Container Security

- Keep Docker and images updated
- Review server source code before enabling
- Limit network access when possible
- Use read-only volumes where appropriate

## Additional Resources

- **MCP Specification**: https://modelcontextprotocol.io/
- **Docker MCP Docs**: https://docs.docker.com/desktop/features/mcp/
- **Available Servers**: Browse `catalogs/docker-mcp.yaml` in this directory

## Example: Adding Playwright Server

Here's a complete example of adding the Playwright server for browser automation:

1. **Review requirements** in `catalogs/docker-mcp.yaml`:
   - No secrets required ✓
   - No additional config needed ✓

2. **Add to registry** in `registry.yaml`:
   ```yaml
   playwright:
     ref: ""
   ```

3. **Restart** your MCP gateway to pick up the changes

4. **Use it** in your AI assistant:
   ```
   "Can you navigate to example.com and take a screenshot?"
   ```

That's it! The Playwright server is now available with tools like `browser_navigate`, `browser_take_screenshot`, etc.

---

**Last Updated**: 2026-02-03  
**Gateway Version**: Docker Desktop MCP Gateway  
**Catalog Version**: v3
