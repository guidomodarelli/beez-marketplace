# Atlassian MCP — Pre-condición y uso

Referencia centralizada para todos los subcommands que usan el MCP de Atlassian.

Documentación oficial: [Getting started with the Atlassian Remote MCP Server](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/)

---

## Instalación

Después de instalar con cualquiera de las opciones siguientes, completar el flujo OAuth autorizando acceso a `mercadolibre.atlassian.net`.

**Claude Code — UI (recomendado):**
Settings → Integrations → Browse extensions → Plugins → buscar Atlassian → Install.
Claude solicitará autenticación con la cuenta de Atlassian Cloud en el browser.

**Claude Code — plugin (CLI):**
Desde una sesión activa de Claude Code:
```
/plugin install atlassian@claude-plugins-official
```
O desde la línea de comandos:
```bash
claude plugin install atlassian@claude-plugins-official
```
Luego autenticar con `/mcp` si Claude Code lo solicita.

**Codex** — agregar en `~/.codex/config.toml`:
```toml
[mcp_servers.AtlassianMCP]
command = "npx"
args = ["-y", "mcp-remote", "https://mcp.atlassian.com/v1/mcp"]
```
Reiniciar Codex y completar el flujo OAuth con `/mcp`.

**GitHub Copilot CLI** — agregar en `~/.copilot/mcp-config.json`:
```json
{
  "mcpServers": {
    "AtlassianMCP": {
      "type": "http",
      "url": "https://mcp.atlassian.com/v1/mcp"
    }
  }
}
```
Reiniciar Copilot CLI y completar el flujo OAuth.

---

## Pre-condición modo ABORTAR

Usar en subcommands donde el MCP es **obligatorio** y sin él no se puede continuar (`derive`, `discard`, `backfill-guides`).

**A. Disponibilidad de herramientas:**
Intentar llamar `mcp__Atlassian__getAccessibleAtlassianResources` (o herramienta equivalente si el proveedor usa un prefijo distinto).

Si la herramienta **no existe** en el contexto → abortar con:
```
❌ MCP Atlassian no disponible.

/groot-queue:<subcomando> requiere el MCP de Atlassian para ejecutar esta acción.
Instalalo según tu proveedor (ver knowledge/config/atlassian-mcp.md § Instalación) y
completá el flujo OAuth con /mcp.
Podés verificar el entorno completo con /groot-queue setup.
```

**B. Autenticación y `cloudId`:**
Usar el resultado de la llamada anterior:
- Si retorna error de autenticación (401 / 403 o equivalente) → abortar con:
  ```
  ❌ MCP Atlassian no autenticado.

  Ejecutá /mcp y completá el flujo OAuth para mercadolibre.atlassian.net.
  Ver knowledge/config/atlassian-mcp.md § Instalación para instrucciones por proveedor.
  ```
- Si retorna recursos: elegir el que represente `mercadolibre.atlassian.net` y guardar su `cloudId`.
- Si `mercadolibre.atlassian.net` **no aparece** en los recursos → abortar con:
  ```
  ❌ No se encontró mercadolibre.atlassian.net en los recursos del MCP de Atlassian.

  Verificá que hayas autorizado acceso a ese workspace durante el flujo OAuth.
  Ejecutá /groot-queue setup para diagnóstico completo.
  ```

**C. Capacidad de nota interna JSM** *(solo para subcommands que postean notas internas)*:
Confirmar que el proveedor expone capacidad de crear **nota interna de Jira Service Management** (no solo comentario público). `addCommentToJiraIssue` por sí sola no alcanza si solo crea comentarios públicos.

Si solo hay capacidad de comentario público y no nota interna → abortar con:
```
❌ El MCP de Atlassian disponible no expone capacidad de nota interna JSM.

/groot-queue:<subcomando> no puede ejecutar esta acción sin riesgo de publicar
información interna al reporter. Completá la acción manualmente en Jira.
```

Solo continuar al algoritmo si todos los puntos aplicables pasaron. El `cloudId` obtenido en B se reutiliza en todos los pasos siguientes — no resolver de nuevo.

---

## Pre-condición modo DEGRADAR

Usar en subcommands donde el MCP es **opcional** y su ausencia degrada (pero no bloquea) el flujo (`assign-unassigned`, `alerts`).

**A. Disponibilidad de herramientas:**
Intentar llamar `mcp__Atlassian__getAccessibleAtlassianResources` (o herramienta equivalente).

- Si la herramienta **no existe** → marcar `MCP_AVAILABLE = false` y mostrar warning específico del subcomando. El warning debe incluir: "Para habilitarlo, ver `knowledge/config/atlassian-mcp.md § Instalación`."
- Si existe → continuar con B.

**B. Autenticación y `cloudId`:**
- Si retorna error de autenticación → marcar `MCP_AVAILABLE = false` y mostrar warning.
- Si retorna recursos: elegir el que represente `mercadolibre.atlassian.net`, guardar `cloudId`, marcar `MCP_AVAILABLE = true`.
- Si `mercadolibre.atlassian.net` no aparece → marcar `MCP_AVAILABLE = false` con warning.

**C. Capacidad de nota interna JSM** *(si el subcomando la usa)*:
- Si solo hay comentario público → marcar `MCP_AVAILABLE = false` y mostrar warning.
- Solo marcar `MCP_AVAILABLE = true` cuando pasaron A, B y esta verificación.

Cuando `MCP_AVAILABLE = false`: omitir todos los pasos que requieran el MCP y reflejar el estado en la tabla final.

---

## Uso de `commentVisibility` (nota interna)

> ⚠️ **OBLIGATORIO**: el parámetro `commentVisibility` con valor `{"type": "role", "value": "Service Desk Team"}` es lo que hace que el comentario sea una **nota interna** (solo visible para agentes, no para el reporter en el portal). Sin este parámetro, `addCommentToJiraIssue` crea un comentario **público** que el reporter puede ver — esto expone información interna de diagnóstico y runbooks al cliente. Nunca omitir `commentVisibility`.

```json
"commentVisibility": {"type": "role", "value": "Service Desk Team"}
```
