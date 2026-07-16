# Subcomando: start

**Propósito**: Mostrar un banner de bienvenida con la versión actual del plugin, un health-check del entorno, un resumen express de la cola, y un catálogo interactivo de todos los comandos disponibles agrupados por intención con hints user-friendly.

---

## Instrucciones

Al ejecutar este subcomando, realizar los siguientes pasos **en orden**:

### Paso 1: Resolver datos dinámicos

Ejecutar **en paralelo** (para minimizar latencia):

1. **Versión**: Leer `plugin.json` del plugin. Buscar en este orden:
   - `$SKILL_DIR/../../.claude-plugin/plugin.json`
   - `$SKILL_DIR/../../.codex-plugin/plugin.json`
   - Si no se encuentra, usar `(unknown)`.

2. **Nombre del usuario**: Ejecutar `git config user.name`. Si falla, usar `"developer"`.

3. **Health-check del entorno** (cada check es independiente):
   - **ACLI**: Ejecutar `which acli`. Si retorna 0 → `✅ ACLI`. Si falla → `❌ ACLI`.
   - **MCP Atlassian**: Verificar si existe MCP Atlassian configurado (buscar en la config del agente o con `claude mcp list 2>/dev/null | grep -i atlassian`). Si existe → `✅ Atlassian MCP`. Si no → `❌ Atlassian MCP`.
   - **MCP Slack**: Verificar si existe MCP Slack configurado (`claude mcp list 2>/dev/null | grep -i slack`). Si existe → `✅ Slack MCP`. Si no → `❌ Slack MCP`.
   - Si algún check falla por error de permisos o tool no disponible, marcar como `⚠️ <nombre> (no verificable)`.

4. **Conteo express de tickets** (best-effort — no bloquear el banner por esto): dejar que el JQL calcule los conteos en el servidor en vez de parsear fechas client-side. Usar la misma definición de cola abierta compartida (`Incident` + `Service Request`). Ejecutar en paralelo:
   ```bash
   # Total abiertos
   acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type IN (Incident, \"Service Request\") AND resolution = Unresolved" --output json 2>/dev/null
   # Sin asignar
   acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type IN (Incident, \"Service Request\") AND resolution = Unresolved AND assignee IS EMPTY" --output json 2>/dev/null
   # En riesgo SLA (alta prioridad + más de 24h de antigüedad, calculado por Jira)
   acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type IN (Incident, \"Service Request\") AND resolution = Unresolved AND priority IN (Highest, High) AND created <= -24h" --output json 2>/dev/null
   ```
   Tomar el conteo de resultados de cada query (`Total abiertos`, `Sin asignar`, `En riesgo SLA`).

   Si ACLI falla o no está disponible, omitir esta sección completamente (no mostrar conteo con errores). No reintentar ni esperar: el banner debe salir rápido.

### Paso 2: Mostrar el output

Renderizar el siguiente bloque, reemplazando los placeholders:
- `{{VERSION}}` → versión del plugin
- `{{USER_NAME}}` → primer nombre del usuario (primer token de git config user.name)
- `{{HEALTH_LINE}}` → línea de health-checks separados por ` | `
- `{{TICKET_LINE}}` → línea de conteo (o vacío si no disponible)

```
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   ██████╗ ██████╗  ██████╗  ██████╗ ████████╗                    ║
║  ██╔════╝ ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝                    ║
║  ██║  ███╗██████╔╝██║   ██║██║   ██║   ██║                       ║
║  ██║   ██║██╔══██╗██║   ██║██║   ██║   ██║                       ║
║  ╚██████╔╝██║  ██║╚██████╔╝╚██████╔╝   ██║                       ║
║   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝    ╚═╝                       ║
║                                                                  ║
║                                             QUEUE  v{{VERSION}}  ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

 👋 Hola, {{USER_NAME}}!

 ┌─ Entorno ────────────────────────────────────────────────────────┐
 │ {{HEALTH_LINE}}                                                  │
 └──────────────────────────────────────────────────────────────────┘
```

Si hay conteo de tickets disponible, agregar inmediatamente después:

```
 ┌─ Cola ahora ─────────────────────────────────────────────────────┐
 │ 📬 {{TOTAL}} | 👤 {{UNASSIGNED}} | 🔥 {{SLA_RISK}} en riesgo SLA │
 └──────────────────────────────────────────────────────────────────┘
```

Si algún valor de riesgo SLA es > 0, agregar debajo:
```
 ⚠️  Hay tickets en riesgo — considerá correr /groot-queue alerts
```

Luego, usar el **Bash tool** para ejecutar `$SKILL_DIR/scripts/render-catalog.sh` exactamente como está. Tratar stdout completo como artefacto opaco y agregarlo byte por byte después del banner: no abreviar, omitir, reindentar, reformatear ni recrear contenido. Esto incluye espacios no separables (`U+00A0`), marcadores, negritas y código inline.

Si script no puede ejecutarse, informar error y detener salida; nunca sintetizar catálogo manualmente como fallback.

Antes de responder, verificar que stdout copiado contiene tanto `🟢 **/groot-queue** \`setup\`` como línea final de `analyze-history` con seis `U+00A0` antes de `→`. Si falta cualquiera, volver a usar stdout original sin transformaciones.

3. **Después del output**, preguntar al usuario:

> ¿Qué comando querés correr? Podés escribirlo directamente o decirme qué necesitás y te guío.

4. **No ejecutar ningún otro subcomando automáticamente**. Solo mostrar el banner y esperar input.

---

## Reglas

- Si ACLI no está disponible, **no fallar** — simplemente omitir la sección de conteo y marcar ACLI como ❌ en el health-check.
- Si `claude mcp list` no está disponible (ej: Codex), marcar MCP checks como `⚠️ (no verificable)`.
- Si el usuario responde con un comando válido después del prompt, dispatchar al subcomando correspondiente.
- El script bash del catálogo debe ejecutarse **verbatim** vía Bash tool — no resumir, no omitir líneas, no generar output de memoria ni reemplazarlo por una versión equivalente.
- Preservar Markdown y bytes emitidos por script; no convertirlos a ANSI, envolver catálogo en bloque de código ni normalizar whitespace.
- El output debe renderizarse tal cual, respetando los caracteres Unicode box-drawing y los emojis.
- Mantener la latencia al mínimo: ejecutar los checks en paralelo siempre que sea posible.
