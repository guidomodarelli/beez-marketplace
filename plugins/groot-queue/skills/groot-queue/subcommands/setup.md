---
description: Verifica e instala dependencias necesarias (ACLI, Slack MCP, permisos, estado round-robin) para usar la skill groot-queue.
---

# /groot-queue:setup

Verificar e instalar todo lo necesario para usar la skill. Ejecutar en orden:

## 1. ACLI (Atlassian CLI)

- Verificar: `acli --version`
- Si no está instalado: mostrar instrucciones → `brew install acli` o https://acli.atlassian.com
- Si está instalado, verificar autenticación: `acli jira serverinfo`
  - Si falla: mostrar `acli jira login --server https://mercadolibre.atlassian.net`

## 2. Slack MCP

- Verificar si el tool `mcp__plugin_slack_slack__authenticate` está disponible en el contexto
- Si no está disponible: indicar al usuario que instale el plugin de Slack:
  ```
  claude mcp add slack
  ```
- Si está disponible pero no autenticado: ejecutar `mcp__plugin_slack_slack__authenticate`

## 3. Permisos ACLI en settings

- Verificar que el directorio `.claude/` existe en el directorio actual
- Verificar que `.claude/settings.local.json` contiene `"Bash(acli jira *)"` en `permissions.allow`
- Si no: crear o actualizar el archivo con el permiso mínimo necesario:
  ```json
  { "permissions": { "allow": ["Bash(acli jira *)"] } }
  ```

## 4. Estado round-robin

- Verificar si existe el archivo `roundrobin-state.json` en la knowledge base
- Si no existe: crearlo con `{ "last_updated": "", "next_assignee_index": 0, "history": [] }`
- Path esperado: `~/.claude/skills/groot-queue/knowledge/roundrobin-state.json`

## 5. Verificación del TEAM

- Leer la sección TEAM del SKILL.md (`~/.claude/skills/groot-queue/SKILL.md`)
- Si está vacía: advertir que `/groot-queue:assign-unassigned` no funcionará hasta configurarlo

## Output esperado

```
✅ ACLI instalado (v8.x.x)
✅ ACLI autenticado en mercadolibre.atlassian.net
✅ Slack MCP disponible y autenticado
✅ Permiso Bash(acli jira *) configurado
✅ Estado round-robin inicializado
✅ Equipo configurado (9 miembros)

Setup completo. Podés usar /groot-queue:list para empezar.
```
