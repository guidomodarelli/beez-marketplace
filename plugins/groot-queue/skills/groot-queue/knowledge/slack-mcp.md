# Slack MCP — Instalación

Referencia centralizada para subcommands que usan el MCP de Slack.

---

## Instalación

El nombre de las herramientas Slack varía según el proveedor — buscar cualquier tool cuyo nombre contenga `slack`.

**Claude Code:**
```bash
claude mcp add --transport http "SlackMCP" https://mcp.slack.com/v1/mcp
```
Luego ejecutar `/mcp` dentro de Claude Code para completar el flujo OAuth.

**Codex** — agregar en `~/.codex/config.toml`:
```toml
[mcp_servers.SlackMCP]
command = "npx"
args = ["-y", "mcp-remote", "https://mcp.slack.com/v1/mcp"]
```
Reiniciar Codex y completar el flujo OAuth con `/mcp`.

**GitHub Copilot CLI** — agregar en `~/.copilot/mcp-config.json`:
```json
{
  "mcpServers": {
    "SlackMCP": {
      "type": "http",
      "url": "https://mcp.slack.com/mcp"
    }
  }
}
```
Reiniciar Copilot CLI y completar el flujo OAuth.
