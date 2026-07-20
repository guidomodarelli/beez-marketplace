# Slack MCP — Instalación

Referencia centralizada para subcommands que usan el MCP de Slack.

Documentación oficial: [Connect to Claude — Slack MCP Server](https://docs.slack.dev/ai/slack-mcp-server/connect-to-claude/)

---

## Instalación

El nombre de las herramientas Slack varía según el proveedor — buscar cualquier tool cuyo nombre contenga `slack`.

**Claude Code — UI (recomendado):**
Settings → Integrations → Slack → autorizar el workspace.

**Claude Code — plugin (CLI):**
Desde una sesión activa de Claude Code:
```
/plugin install slack
```
O desde la línea de comandos:
```bash
claude plugin install slack
```
El plugin configura el MCP automáticamente (OAuth incluido vía `clientId` y `callbackPort`).

**Codex** — agregar en `~/.codex/config.toml`:
```toml
[mcp_servers.SlackMCP]
command = "npx"
args = ["-y", "mcp-remote", "https://mcp.slack.com/mcp"]
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
