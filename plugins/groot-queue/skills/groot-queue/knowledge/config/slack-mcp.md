# Slack MCP — Configuración y degradación

Referencia centralizada para subcommands que usan el MCP de Slack.

Documentación oficial: [Connect to Claude — Slack MCP Server](https://docs.slack.dev/ai/slack-mcp-server/connect-to-claude/)

---

## Instalación humana

La fuente canónica para instalar y completar OAuth es la sección [Slack MCP de la guía de Groot Queue](installation.md#5-slack-mcp). No duplicar aquí comandos ni configuración de Claude Code.

- **Claude Code**: seguir la sección canónica anterior.
- **Codex**: seguir el [anexo Codex](installation.md#anexo-codex) y aplicar el mismo contrato de capacidades y OAuth.

## Contrato de capacidades y degradación

Los nombres de las tools de Slack varían según provider y configuración. Detectar capacidades compatibles para localizar usuarios y enviar mensajes sin depender de un nombre exacto.

- Si las capacidades requeridas no existen, marcar Slack como degradado y permitir `alerts` únicamente con `--dry-run`.
- Si existen pero OAuth no está listo, no enviar mensajes; mostrar el estado y remitir a la sección "Slack MCP" de la guía canónica de Groot Queue.
- Solo habilitar envíos cuando las capacidades y la autenticación del workspace correcto estén verificadas.
- No enviar un mensaje real como prueba de setup.
