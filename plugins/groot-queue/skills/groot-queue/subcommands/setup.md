---
description: Verifica e instala dependencias necesarias (ACLI, Atlassian MCP, Slack MCP, permisos) para usar la skill groot-queue.
---

# /groot-queue:setup

Verificar e instalar todo lo necesario para usar la skill. Ejecutar en orden:

## 1. ACLI (Atlassian CLI)

- Verificar: `acli --version`
- Si no está instalado: mostrar instrucciones → `brew install acli` o https://acli.atlassian.com
- Si está instalado, verificar autenticación: `acli jira serverinfo`
  - Si falla: mostrar `acli jira auth login --web` y pedir seleccionar https://mercadolibre.atlassian.net

## 2. Atlassian MCP

El subcomando `derive` usa el MCP de Atlassian para ejecutar la transición "Derivar a otro equipo" (requiere campos de pantalla que ACLI no puede proveer: Squad destino + comentario privado de traspaso).

- Verificar si el contexto expone un MCP de Atlassian compatible. Si se instaló con el nombre `Atlassian`, las herramientas deben aparecer con prefijo `mcp__Atlassian__...` (por ejemplo `mcp__Atlassian__getAccessibleAtlassianResources`, `mcp__Atlassian__getTransitionsForJiraIssue`, `mcp__Atlassian__addCommentToJiraIssue` y `mcp__Atlassian__transitionJiraIssue`).
- Si el proveedor actual no expone herramientas MCP de Atlassian, informar que `/groot-queue:derive` no puede ejecutar la transición automática desde ese proveedor y que se debe completar la derivación manualmente en Jira.
- Si el proveedor solo expone comentarios públicos (`addCommentToJiraIssue`) y no una capacidad equivalente para crear **nota interna de Jira Service Management**, informar que `/groot-queue:derive` no puede automatizar la derivación sin riesgo de publicar información interna al reporter. En ese caso debe completarse manualmente en Jira.
- Si **no está disponible**, instalarlo con una de estas opciones:

  **Opción A — CLI (recomendado):**
  ```bash
  claude mcp add --transport http "Atlassian" https://mcp.atlassian.com/v1/mcp
  ```
  Luego completar el flujo OAuth con `/mcp` dentro de Claude Code y autorizar el acceso a `mercadolibre.atlassian.net`.

  **Opción B — UI:**
  Claude Code → Settings → Integrations → Atlassian → autorizar acceso a `mercadolibre.atlassian.net`.

  Mostrar mensaje:
  ```
  ⚠️  Atlassian MCP no detectado.
  Instalá con: claude mcp add --transport http "Atlassian" https://mcp.atlassian.com/v1/mcp
  Luego ejecutá /mcp para completar el flujo OAuth.
  El subcomando /groot-queue:derive no puede ejecutar la transición de estado sin este MCP.
  ```

- Si **está disponible**, verificar autenticación y resolver el `cloudId` intentando:
  - Llamar `mcp__Atlassian__atlassianUserInfo` o la herramienta equivalente expuesta por el MCP de Atlassian del proveedor actual.
  - Si retorna datos del usuario: ✅ autenticado
  - Si falla con error de auth: llamar `mcp__Atlassian__authenticate` o la herramienta equivalente, e indicar al usuario que complete el flujo OAuth
  - Llamar `mcp__Atlassian__getAccessibleAtlassianResources` o la herramienta equivalente y elegir el recurso que represente `mercadolibre.atlassian.net`.
  - Usar el `cloudId` retornado por ese recurso en las llamadas posteriores. Si el proveedor documenta o valida otro formato para ese sitio (por ejemplo URL completa o hostname), usar ese valor validado y dejarlo explícito.

> **Nota**: no hardcodear el `cloudId` sin validarlo contra el MCP actual. Resolverlo durante setup y reutilizar el valor validado para `/groot-queue:derive`.

## 3. Slack MCP

- Verificar si el tool `mcp__plugin_slack_slack__authenticate` está disponible en el contexto
- Si no está disponible: indicar al usuario que instale el plugin de Slack:
  ```
  claude mcp add slack
  ```
- Si está disponible pero no autenticado: ejecutar `mcp__plugin_slack_slack__authenticate`

## 4. Permisos ACLI en settings

- Verificar que el directorio `.claude/` existe en el directorio actual
- Verificar que `.claude/settings.local.json` contiene `"Bash(acli jira *)"` en `permissions.allow`
- Si no: crear o actualizar el archivo con el permiso mínimo necesario:
  ```json
  { "permissions": { "allow": ["Bash(acli jira *)"] } }
  ```

## 5. Verificación del TEAM

- Leer la sección TEAM del SKILL.md (`~/.claude/skills/groot-queue/SKILL.md`)
- Si está vacía: advertir que `/groot-queue:assign-unassigned` no funcionará hasta configurarlo

## Output esperado

```
✅ ACLI instalado (v8.x.x)
✅ ACLI autenticado en mercadolibre.atlassian.net
✅ Atlassian MCP disponible, autenticado y con cloudId validado para mercadolibre.atlassian.net
✅ Slack MCP disponible y autenticado
✅ Permiso Bash(acli jira *) configurado
✅ Equipo configurado (8 miembros)

Setup completo. Podés usar /groot-queue:list para empezar.
```
