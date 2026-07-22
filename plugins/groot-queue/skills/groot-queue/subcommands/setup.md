---
description: Verifica e instala dependencias necesarias (ACLI, Atlassian MCP, Slack MCP, permisos) para usar la skill groot-queue.
---

# /groot-queue:setup

Verificar e instalar todo lo necesario para usar la skill. Ejecutar en orden.

> **Re-ejecutable**: este subcomando es idempotente. Correrlo de nuevo no rompe nada — sólo revalida lo ya configurado y completa lo que falte. Usalo cuando algo deje de andar.

## 1. ACLI (Atlassian CLI)

- Verificar: `acli --version`
- Si no está instalado: mostrar instrucciones → `brew install acli` o https://acli.atlassian.com
- Si está instalado, verificar autenticación: `acli jira serverinfo`
  - Si falla: mostrar `acli jira auth login --web` y pedir seleccionar https://mercadolibre.atlassian.net

## 2. Atlassian MCP

El subcomando `derive` usa el MCP de Atlassian para ejecutar la transición "Derivar a otro equipo" (requiere campos de pantalla que ACLI no puede proveer: Squad destino + comentario privado de traspaso). Ver `$SKILL_DIR/knowledge/config/atlassian-mcp.md` para la referencia canónica de instalación y mensajes de error.

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

El subcomando `alerts` usa el MCP de Slack para enviar DMs de resumen de SLA. El nombre de las herramientas Slack **varía según el proveedor y la configuración del MCP** — no hardcodear un nombre exacto.

- Buscar en el contexto **cualquier** tool cuyo nombre contenga `slack` y exponga capacidad de buscar usuarios y enviar mensajes (ej: `mcp__slack__search_users`, `mcp__plugin_slack_slack__search_users`, `mcp__<id>__slack_search_users`, u otra variante).
- Si **no existe ninguna** tool de Slack:
  ```
  ⚠️  Slack MCP no detectado.
  Para Claude Code: instalá el plugin/connector de Slack (Settings → Integrations) o vía `claude mcp add`.
  Para Codex: configurá el MCP de Slack en .codex/mcp.json.
  El subcomando /groot-queue:alerts sólo podrá correr en modo --dry-run sin este MCP.
  ```
- Si existe pero no está autenticado: ejecutar la tool de autenticación de Slack disponible (si el proveedor la expone) o indicar al usuario que complete el login del connector.
- Si existe y está autenticado → ✅.

## 4. Permisos ACLI en settings

- Verificar que el directorio `.claude/` existe en el directorio actual
- Verificar que `.claude/settings.local.json` contiene `"Bash(acli jira *)"` en `permissions.allow`
- Si no: crear o actualizar el archivo con el permiso mínimo necesario:
  ```json
  { "permissions": { "allow": ["Bash(acli jira *)"] } }
  ```

## 5. Verificación del TEAM

- Leer la sección TEAM del SKILL.md (`$SKILL_DIR/SKILL.md`)
- Si está vacía: advertir que `/groot-queue:assign-unassigned` no funcionará hasta configurarlo

## 6. Grid Sharing (plugin) — OBLIGATORIO

Cualquier subcomando de `/groot-queue` puede necesitar consultar documentación operativa alojada en Grid (grid.adminml.com). El plugin `grid-sharing` es **mandatorio** para operar la skill.

- Verificar si la skill `/grid-sharing:grid` está disponible en el contexto (aparece en la lista de skills disponibles).
- Si **no está disponible**:
  ```
  ❌  Plugin grid-sharing no detectado.
  Instalá con: /plugins (en Claude Code).
  /groot-queue NO puede operar sin este plugin.
  ```
- Si está disponible → ✅.

## Output esperado

Renderizar una tabla de estado con el resultado **real** de cada check (no valores de ejemplo). Reemplazar cada `<...>` con lo que se obtuvo en tiempo de ejecución:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Setup — Groot Queue
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
| Check                         | Estado | Detalle                                  |
|-------------------------------|--------|------------------------------------------|
| ACLI instalado                | <✅/❌> | <versión real, ej: v8.x.x>               |
| ACLI autenticado              | <✅/❌> | mercadolibre.atlassian.net               |
| Atlassian MCP + cloudId       | <✅/❌/⚠️> | <cloudId validado / no verificable>   |
| Slack MCP                     | <✅/❌/⚠️> | <disponible y autenticado / no detectado> |
| Permiso Bash(acli jira *)     | <✅/❌> | .claude/settings.local.json              |
| TEAM configurado              | <✅/⚠️> | <N miembros / vacío>                      |
| Grid Sharing plugin           | <✅/❌> | <disponible / no detectado>              |
```

- `✅` = OK · `❌` = falta y es bloqueante para algún subcomando · `⚠️` = degradado o no verificable en este proveedor.
- Los valores entre `<...>` son placeholders: rellenarlos con el resultado real de cada verificación.

### Cierre

- Si **todos** los checks críticos (ACLI instalado + autenticado + permiso) están en ✅:
  > ✅ Setup completo. Podés usar `/groot-queue list` para empezar.
- Si hay ❌ o ⚠️, listar debajo **qué falló, cómo arreglarlo y qué subcomandos quedan limitados** mientras tanto. Ejemplo:
  ```
  ⚠️ Setup incompleto:
  • Slack MCP no detectado → /groot-queue alerts sólo corre con --dry-run. Arreglo: ver sección 3.
  • TEAM vacío → /groot-queue assign-unassigned no funciona. Arreglo: completá la sección TEAM del SKILL.md.

  El resto de los comandos (list, classify, detail, solve, derive, discard) ya está operativo.
  ```
