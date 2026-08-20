# Atlassian MCP — Precondición y uso

Referencia centralizada para todos los subcomandos que usan el MCP de Atlassian.

Documentación oficial: [Getting started with the Atlassian Remote MCP Server](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/)

---

## Instalación humana

La fuente canónica para instalar, elegir una única integración y completar OAuth es la sección [Atlassian MCP de la guía de Groot Queue](installation.md#4-atlassian-mcp). No duplicar aquí comandos ni configuración de Claude Code.

- **Claude Code**: seguir la sección canónica anterior.
- **Codex**: seguir el [anexo Codex](installation.md#anexo-codex) y conservar este mismo contrato de OAuth, resolución dinámica de tools y `cloudId`.

Después de configurar el provider soportado, completar OAuth autorizando acceso a `mercadolibre.atlassian.net`. Los nombres de las tools pueden variar por provider; resolver capacidades equivalentes sin hardcodear prefijos.

---

## Precondición modo ABORTAR

Usar en subcommands donde el MCP es **obligatorio** y sin él no se puede continuar (`derive`, `discard`, `backfill-guides`).

**A. Disponibilidad de herramientas:**
Intentar llamar `mcp__Atlassian__getAccessibleAtlassianResources` (o herramienta equivalente si el provider usa un prefijo distinto).

Si la herramienta **no existe** en el contexto → abortar con:
```
❌ MCP Atlassian no disponible.

/groot-queue:<subcomando> requiere el MCP de Atlassian para ejecutar esta acción.
Seguí la sección "Atlassian MCP" de la guía canónica de Groot Queue y completá OAuth.
Podés diagnosticar el entorno completo con /groot-queue setup.
```

**B. Autenticación y `cloudId`:**
Usar el resultado de la llamada anterior:
- Si retorna error de autenticación (401 / 403 o equivalente) → abortar con:
  ```
  ❌ MCP Atlassian no autenticado.

  Completá OAuth para mercadolibre.atlassian.net según
  la sección "Atlassian MCP" de la guía canónica de Groot Queue.
  ```
- Si retorna recursos: elegir el que represente `mercadolibre.atlassian.net` y guardar su `cloudId`.
- Si `mercadolibre.atlassian.net` **no aparece** en los recursos → abortar con:
  ```
  ❌ No se encontró mercadolibre.atlassian.net en los recursos del MCP de Atlassian.

  Verificá que hayas autorizado acceso a ese workspace durante OAuth.
  Ejecutá /groot-queue setup para obtener un diagnóstico completo.
  ```

**C. Capacidad de nota interna JSM** *(solo para subcommands que postean notas internas)*:
Confirmar que el provider expone capacidad de crear **nota interna de Jira Service Management** (no solo comentario público). `addCommentToJiraIssue` por sí sola no alcanza si solo crea comentarios públicos.

Si solo hay capacidad de comentario público y no nota interna → abortar con:
```
❌ El MCP de Atlassian disponible no expone capacidad de nota interna JSM.

/groot-queue:<subcomando> no puede ejecutar esta acción sin riesgo de publicar
información interna al reporter. Completá la acción manualmente en Jira.
```

Solo continuar al algoritmo si todos los puntos aplicables pasaron. El `cloudId` obtenido en B se reutiliza en todos los pasos siguientes; no resolverlo de nuevo.

---

## Precondición modo DEGRADAR

Usar en subcommands donde el MCP es **opcional** y su ausencia degrada, pero no bloquea, el flujo (`assign-unassigned`, `alerts`).

**A. Disponibilidad de herramientas:**
Intentar llamar `mcp__Atlassian__getAccessibleAtlassianResources` (o herramienta equivalente).

- Si la herramienta **no existe** → marcar `MCP_AVAILABLE = false` y mostrar un warning específico del subcomando que remita a la sección "Atlassian MCP" de la guía canónica de Groot Queue.
- Si existe → continuar con B.

**B. Autenticación y `cloudId`:**
- Si retorna error de autenticación → marcar `MCP_AVAILABLE = false`, mostrar un warning y remitir a `$SKILL_DIR/knowledge/config/installation.md#4-atlassian-mcp`.
- Si retorna recursos: elegir el que represente `mercadolibre.atlassian.net`, guardar `cloudId` y marcar `MCP_AVAILABLE = true`.
- Si `mercadolibre.atlassian.net` no aparece → marcar `MCP_AVAILABLE = false` con warning.

**C. Capacidad de nota interna JSM** *(si el subcomando la usa)*:
- Si solo hay comentario público → marcar `MCP_AVAILABLE = false` y mostrar warning.
- Solo marcar `MCP_AVAILABLE = true` cuando pasaron A, B y esta verificación.

Cuando `MCP_AVAILABLE = false`, omitir todos los pasos que requieran el MCP y reflejar el estado en la tabla final.

---

## Identidad del ejecutor para watcher cleanup

Cuando derive o discard necesite remover watcher del ejecutor, resolver identidad sólo mediante capacidad equivalente a `atlassianUserInfo` del MCP Atlassian. Usar su `accountId` únicamente en memoria para `acli jira workitem watcher remove`; no inferirlo desde TEAM, nombre, email, assignee o requester.

Si MCP no expone identidad actual o ticket no devuelve assignee final verificable, la acción principal puede conservarse pero watcher cleanup queda `partial-error`. Nunca remover watcher con identidad ambigua.

## Uso de `commentVisibility` (nota interna)

> ⚠️ **OBLIGATORIO**: el parámetro `commentVisibility` con valor `{"type": "role", "value": "Service Desk Team"}` es lo que hace que el comentario sea una **nota interna** (solo visible para agentes, no para el reporter en el portal). Sin este parámetro, `addCommentToJiraIssue` crea un comentario **público** que el reporter puede ver; esto expone información interna de diagnóstico y runbooks al cliente. Nunca omitir `commentVisibility`.

```json
"commentVisibility": {"type": "role", "value": "Service Desk Team"}
```
