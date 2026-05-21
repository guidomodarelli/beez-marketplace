---
description: Detecta tickets en riesgo de SLA y envía alertas por Slack DM al responsable.
---

# /groot-queue:alerts

Detectar tickets en riesgo de SLA y notificar por Slack DM.

## Procedimiento

1. Leer las referencias:
   - `~/.claude/skills/groot-queue/knowledge/classification.md`
   - `~/.claude/skills/groot-queue/knowledge/triage-rules.md`
2. Obtener todos los tickets abiertos (JQL base).
3. Clasificar cada uno (incluye triage de veredicto).
4. Filtrar los que tienen **urgencia >= 4** O están en **"Esperando por Soporte" sin asignar hace >24h**.
5. Para cada ticket en riesgo, enviar Slack DM a **lucas.padularrosa@mercadolibre.com** usando las tools de Slack MCP. Primero autenticarse con `mcp__plugin_slack_slack__authenticate` si es necesario, luego enviar mensaje con formato:
   - 🔴 **SLA Risk** — SSHP-XXXXXX
   - Summary del ticket
   - Categoría | Urgencia X/5 | Edad Xh
   - Link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`
6. Mostrar resumen en consola de cuántos alerts se enviaron.

**Nota**: usar Slack MCP tools solo si el usuario lo solicita explícitamente la primera vez; después mantener la preferencia.
