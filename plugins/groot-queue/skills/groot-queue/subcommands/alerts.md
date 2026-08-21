---
description: Detecta tickets vencidos y por vencer de SLA, agrupa por responsable y envía un resumen por Slack DM a cada miembro del TEAM.
---

# /groot-queue:alerts

Detectar tickets **vencidos** y **por vencer** de SLA, agruparlos por responsable (assignee) y enviar **un único mensaje resumen** por Slack DM a cada miembro afectado del TEAM.

## Opciones

| Flag | Efecto |
|------|--------|
| `--dry-run` | Muestra en consola lo que se enviaría sin ejecutar Slack. No envía ningún mensaje. |

---

## Pre-condición: TEAM

Leer el `TEAM` desde `$SKILL_DIR/SKILL.md`. Si está vacío, abortar con:
> "Configurá la sección TEAM del SKILL.md antes de usar este comando."

Construir un mapa `email → name` para resolver cada assignee a su nombre humano.

---

## Pre-condición: `acli` autenticado (fuente primaria de VENCIDOS)

Los **VENCIDOS** se detectan con la función JQL de SLA `breached()` vía `acli` (paso 1, Fetch B), que evalúa la columna **Time to resolution** del ticket — la misma que se ve en el dashboard de Jira. `acli` usa su propia autenticación, **independiente del MCP Atlassian**.

Verificar con `acli jira auth status`. Si `acli` no está autenticado, abortar con:
```
❌ acli no autenticado. Ejecutá `acli auth login` (site mercadolibre.atlassian.net) antes de usar este comando.
```

## Pre-condición: MCP Atlassian (solo para precisión de POR VENCER)

El MCP Atlassian se usa **únicamente** para (a) enriquecer la **edad** (`created`) y (b) calcular las **horas de calendario hasta el vencimiento** (`customfield_12400.breachTime.jira`) de los candidatos a POR VENCER. **No** se necesita para los VENCIDOS. Aplicar **modo DEGRADAR** (pasos A + B) de `$SKILL_DIR/knowledge/config/atlassian-mcp.md`. Omitir el paso C (este subcomando no postea notas internas). Usar `ATLASSIAN_MCP_AVAILABLE` como nombre de la variable de estado. El warning de degradación debe aclarar: "Los VENCIDOS se detectan igual vía `acli breached()`. Sin MCP solo se degrada la precisión de POR VENCER (se cae a la heurística de `Esperando por Soporte`)."

---

## Pre-condición: Slack MCP (solo si NO es `--dry-run`)

El nombre de las herramientas Slack varía según el proveedor y la configuración del MCP. Buscar cualquier tool que contenga `slack` en su nombre (ej: `mcp__plugin_slack_slack__authenticate`, `mcp__slack__authenticate`, u otra variante).

1. Verificar si existe **alguna** tool de Slack disponible en el contexto (buscar tools que contengan `slack` y expongan capacidad de enviar DM).
   - Si **no existe ninguna** → abortar con:
     ```
     ⚠️ Slack MCP no disponible.
     Seguí la sección "Slack MCP" de la guía canónica de Groot Queue
     o usá --dry-run para ver el reporte sin enviar mensajes.
     ```
2. Si existe → autenticarse usando la tool de autenticación de Slack disponible (si no lo está ya).

---

## Procedimiento

### 1. Obtener tickets abiertos asignados (conjunto COMPLETO, sin truncar)

Leer referencias:
- `$SKILL_DIR/knowledge/config/batch-processing.md`
- `$SKILL_DIR/knowledge/config/classification.md` (JQL base)
- `$SKILL_DIR/knowledge/config/ticket-evidence.md`
- `$SKILL_DIR/knowledge/config/kraken-user-data.md`
- `$SKILL_DIR/knowledge/rules/triage-rules.md`

Partir del **JQL base** de `classification.md` y agregar `assignee IS NOT EMPTY` (los tickets sin assignee no se pueden notificar; para esos usar `/groot-queue:assign-unassigned` primero).

> ⚠️ **SIEMPRE usar `--paginate`.** Sin `--paginate`, `acli jira workitem search` devuelve solo la **primera página (~30 resultados)**. La cola Groot suele tener 100+ tickets abiertos y el orden `created DESC` deja los **más viejos —que son los más vencidos— fuera de esa página**, por lo que se pierden exactamente los tickets que este comando debe detectar. La inclusión de un ticket **nunca** puede depender del orden ni de un corte de página.

Ejecutar **tres** búsquedas, todas con `--paginate`. El nombre del SLA se referencia entre comillas simples dentro del `--jql` de comillas dobles: `'Time to resolution' = breached()` (funciones JQL nativas de Jira Service Management).

**Fetch B — VENCIDOS autoritativos por SLA "Time to resolution" (`breached()`):**
```bash
acli jira workitem search \
  --jql "project = SSHP AND cf[13781] = \"Groot\" AND resolution = Unresolved AND assignee IS NOT EMPTY AND 'Time to resolution' = breached() ORDER BY created ASC" \
  --paginate --fields "key,assignee,status,priority,summary" --csv
```
**Cada key devuelta por Fetch B está VENCIDA** según la columna "Time to resolution" — lo calcula Jira, en tiempo calendario, y **no depende del MCP**. Guardar como `vencidas`.

**Fetch C — candidatos a POR VENCER (SLA corriendo, aún no vencido):**
```bash
acli jira workitem search \
  --jql "project = SSHP AND cf[13781] = \"Groot\" AND resolution = Unresolved AND assignee IS NOT EMPTY AND 'Time to resolution' = running() AND 'Time to resolution' != breached() ORDER BY created ASC" \
  --paginate --fields "key,assignee,status,priority,summary" --csv
```
Guardar como `por_vencer_candidatas`. Solo sobre este subconjunto se calcula el umbral "≤48h calendario" en el paso 3 (nunca sobre las ya vencidas).

**Fetch A — universo completo de alertables (solo se usa en el fallback 3.3):**
```bash
acli jira workitem search \
  --jql "project = SSHP AND cf[13781] = \"Groot\" AND resolution = Unresolved AND assignee IS NOT EMPTY ORDER BY created ASC" \
  --paginate --fields "key,assignee,status,priority,summary" --csv
```

Unir, deduplicar y congelar keys de `vencidas ∪ por_vencer_candidatas` (o `alertables` en fallback) sin reconsultar ni reordenar snapshot. Según `$SKILL_DIR/knowledge/config/batch-processing.md`, procesar triage, hidratación SLA MCP y fallbacks en lotes consecutivos de hasta 25 keys; anunciar `Lote X/Y` y acumular resultados globales. No enviar Slack durante un lote.

En la salida, el campo `assignee` viene como **email** (ej. `francisco.gonzalez@mercadolibre.com`); usarlo directamente para el mapa `email → name` del TEAM. `acli` **no** expone `created` ni el breach time (esos vienen del MCP en el paso 3).

### 2. Clasificar y aplicar triage

El triage se aplica sobre cada lote activo del conjunto en riesgo `vencidas ∪ por_vencer_candidatas` (en el fallback 3.3, sobre `alertables`). Para cada ticket:
1. Aplicar gate de `ticket-evidence.md` y verificar autónomamente facts decisivos mínimos mediante `kraken-user-data.md` antes de confirmar triage.
2. Aplicar **triage de veredicto** de `triage-rules.md` con evidencia normalizada.
3. **Excluir** solo tickets con veredicto `DESCARTAR` o `DERIVAR` confirmado. Si condición decisiva queda indeterminada, conservar ticket para análisis SLA como `REVISAR_MANUAL`; no excluirlo silenciosamente.
4. Clasificar en Dimensión 1 (categoría) según `classification.md` (se usa en mensaje del paso 5). Facts de usuario no intervienen en cálculo SLA.

### 3. Determinar estado de SLA

El estado de SLA se basa en la columna **Time to resolution** (SLA nativo de Jira Service Management), la misma que se ve en el dashboard.

#### 3.1 VENCIDOS — autoritativo vía `acli` (Fetch B)

Todas las keys de **Fetch B** (`'Time to resolution' = breached()`) son **VENCIDO**. No requieren MCP ni parseo adicional: Jira ya evaluó el breach en tiempo calendario contra la columna "Time to resolution". Marcar cada `vencidas[k]` como `VENCIDO`.

> Esto reemplaza el viejo enfoque de traer `customfield_12400` de cada ticket para leer el flag `breached`. Es más confiable: no se trunca, no depende del MCP y usa exactamente la columna que se ve en el dashboard.

#### 3.2 POR VENCER — cálculo calendario sobre `por_vencer_candidatas` (Fetch C)

Solo los tickets de **Fetch C** pueden ser POR VENCER. Para decidir hace falta la **hora exacta de vencimiento** (`breachTime.jira`), que `acli` no expone y requiere MCP Atlassian.

**Si `ATLASSIAN_MCP_AVAILABLE = true`:**

Traer `customfield_12400` y `created` por **lotes** con `searchJiraIssuesUsingJql`. Incluir en el lote **también** las keys de `vencidas` (para obtener su `created` y calcular la edad). Dividir `vencidas ∪ por_vencer_candidatas` en lotes de hasta 25 keys y recorrer **todos** los lotes hasta agotar la lista:

```
searchJiraIssuesUsingJql(
  cloudId: "<cloudId de mercadolibre.atlassian.net>",
  jql: "issuekey in (SSHP-1234567, SSHP-1234568, ...) ORDER BY created ASC",
  fields: ["customfield_12400", "status", "assignee", "summary", "created"],
  maxResults: 25
)
```

> ⚠️ **Usar `maxResults`, no `limit`** (`limit` no es soportado por esta tool y puede hacer fallar la búsqueda). ⚠️ **Nunca `fields: ["*all"]`** (respuestas de ~300K chars que saturan el contexto). `maxResults: 25` es **por lote**, no global: si hay 90 keys se hacen 4 búsquedas (25 + 25 + 25 + 15). Verificar cobertura y recuperar cualquier `missing_key` con `getJiraIssue(cloudId, issueIdOrKey, fields: [...])`.

Para cada key de `por_vencer_candidatas`, con su `customfield_12400.ongoingCycle`:
- `horas_restantes = breachTime.jira - ahora` (en horas de **calendario**, misma timezone).
- Si `horas_restantes` ≤ 48h → **POR VENCER**. Si > 48h → no alertar.

> ⚠️ **NO usar `remainingTime.millis` ni la función JQL `remaining("48h")`**: ambas cuentan solo **horas hábiles** (working time), no calendario. En esta instancia `'Time to resolution' < remaining('48h')` devuelve ~78 tickets (casi toda la cola), por eso no sirve como umbral. Comparar siempre `breachTime.jira` contra `ahora`.

La **edad** de cada ticket (VENCIDO o POR VENCER) se calcula `ahora - created` con el `created` traído en este batch.

**Si `ATLASSIAN_MCP_AVAILABLE = false` (degradado):**
- Los **VENCIDOS ya están cubiertos** por Fetch B — no se pierden.
- Para **POR VENCER**, aplicar la heurística `WAITING_FOR_SUPPORT` de `$SKILL_DIR/knowledge/config/jira-field-options.md` sobre `por_vencer_candidatas`: estado reconocido, sin respuesta del equipo entre 24h y 48h → POR VENCER. Estado no reconocido no se promueve por esta heurística.
- La **edad** se obtiene best-effort con `acli jira workitem view <key>` para las pocas keys en riesgo; si no se puede, omitir el `Edad:` de ese ticket.
- Mostrar el warning de degradación de la pre-condición MCP.

#### 3.3 Fallback si `acli` no soporta la función SLA `breached()`

Si **Fetch B/C fallan** porque el entorno rechaza `'Time to resolution' = breached()` (error de JQL), degradar así:
1. Usar el **universo completo** `alertables` de **Fetch A** (paginado).
2. Con MCP disponible, traer `customfield_12400` por lotes de hasta 25 sobre **todo** `alertables` y clasificar con la estructura de abajo (`ongoingCycle.breached == true` → VENCIDO; `breachTime.jira - ahora ≤ 48h` → POR VENCER).
3. Sin MCP, último recurso: evaluar solo `WAITING_FOR_SUPPORT` según `$SKILL_DIR/knowledge/config/jira-field-options.md` y avisar que los VENCIDOS pueden estar **subestimados**. Estado no reconocido no se considera evidencia de espera.

**Estructura del campo `customfield_12400`** (usada por 3.2 y por el fallback 3.3):

```json
{
  "id": "203",
  "name": "Time to resolution",
  "_links": { "self": "https://mercadolibre.atlassian.net/rest/servicedeskapi/request/<id>/sla/203" },
  "ongoingCycle": {
    "breached": true,
    "breachTime": {
      "jira": "2026-06-30T12:00:00.000-0300",
      "friendly": "30/Jun/26 12:00 PM"
    },
    "remainingTime": { "millis": -345600000, "friendly": "-96h" },
    "goalDuration": { ... },
    "elapsedTime": { ... }
  },
  "completedCycles": []
}
```

- `ongoingCycle.breached == true` → **VENCIDO** directamente.
- `ongoingCycle.breached == false` → `horas_restantes = breachTime.jira - ahora` (calendario); ≤ 48h → **POR VENCER**; > 48h → no alertar.
- `ongoingCycle` null con `completedCycles` → SLA completado (resuelto), no alertar.

**Reglas de clasificación:**

| Estado | Condición | Indicador |
|--------|-----------|-----------|
| **VENCIDO** | key en Fetch B (`'Time to resolution' = breached()`) **O** (fallback 3.3) `ongoingCycle.breached == true` **O** (último recurso) `WAITING_FOR_SUPPORT` reconocido sin respuesta del equipo > 48h | 🔴 |
| **POR VENCER** | candidato de Fetch C con `breachTime.jira - ahora` ≤ 48h calendario **O** (degradado) `WAITING_FOR_SUPPORT` reconocido sin respuesta del equipo entre 24h y 48h | 🟡 |

- Un ticket VENCIDO **no** se evalúa además como POR VENCER (no se duplica).
- Si un ticket no califica como VENCIDO ni POR VENCER, descartarlo del reporte.
- "Sin respuesta del equipo" = no hay comentario interno posterior al último comentario del reporter o a la transición a un estado `WAITING_FOR_SUPPORT` reconocido.

### 4. Agrupar por responsable

Después de agotar todos los lotes y sólo entonces, crear un mapa global `assignee_email → { vencidos: [...], por_vencer: [...] }`. Ningún lote envía DMs parciales.

Solo incluir assignees que **pertenecen al TEAM** (match por email). Si un ticket está asignado a alguien fuera del TEAM, listarlo en una sección separada "Tickets con assignee externo" en consola pero **no enviar DM**.

### 5. Generar mensaje por persona

Para cada miembro del TEAM con tickets en riesgo, componer UN único mensaje con este formato:

```
⚠️ *Resumen de SLA — Groot Soporte*
Fecha: <DD/MM/YYYY HH:mm> (America/Argentina/Buenos_Aires)

Hola <nombre>, tenés tickets que requieren atención:

🔴 *Vencidos (<N>):*
• SSHP-XXXXXX — <summary> | <categoría> | <status> | Edad: <X>h
  → https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX
• SSHP-YYYYYY — <summary> | <categoría> | <status> | Edad: <X>h
  → https://mercadolibre.atlassian.net/browse/SSHP-YYYYYY

🟡 *Por vencer en <48h (<M>):*
• SSHP-ZZZZZZ — <summary> | <categoría> | <status> | Edad: <X>h
  → https://mercadolibre.atlassian.net/browse/SSHP-ZZZZZZ

Total: <N+M> tickets en riesgo.
```

- Si la persona no tiene tickets en alguna categoría (ej: no tiene vencidos), omitir esa sección del mensaje.
- Ordenar tickets dentro de cada sección por edad descendente (más viejo primero).

### 6a. Modo `--dry-run`: mostrar en consola

Si el usuario pasó `--dry-run`, mostrar el reporte completo en consola **sin enviar nada por Slack**:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔔 ALERTS — Dry Run (no se envían mensajes)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Fecha: <DD/MM/YYYY HH:mm>

📨 Mensaje para <nombre> (<email>):
────────────────────────────────────
<contenido del mensaje tal como se enviaría>
────────────────────────────────────

📨 Mensaje para <nombre> (<email>):
────────────────────────────────────
<contenido del mensaje tal como se enviaría>
────────────────────────────────────

Resumen:
  Personas a notificar: <X>
  Tickets vencidos: <N>
  Tickets por vencer: <M>
  Total tickets en riesgo: <N+M>

ℹ️  Ejecutá sin --dry-run para enviar los mensajes por Slack.
```

### 6b. Modo normal: enviar por Slack

Para cada miembro con tickets en riesgo:
1. Buscar al usuario en Slack por email usando la tool de búsqueda de usuarios disponible (ej: `mcp__plugin_slack_slack__search_users`, `mcp__slack__search_users`, u otra variante que acepte email).
2. Si se encuentra el usuario, enviar DM con la tool de envío de mensaje directo disponible (ej: `mcp__plugin_slack_slack__send_dm`, `mcp__slack__send_dm`, u otra variante) con el mensaje compuesto en el paso 5.
3. Si no se encuentra el usuario en Slack, registrar warning y continuar con el siguiente.

### 7. Resumen final en consola

Siempre mostrar (tanto en dry-run como en modo normal):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Resumen de Alertas
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
| Miembro         | 🔴 Vencidos | 🟡 Por vencer | Notificado |
|-----------------|-------------|---------------|------------|
| <nombre>        | 2           | 1             | ✓ / ✗ / 🏜️ dry-run |
| <nombre>        | 0           | 3             | ✓ / ✗ / 🏜️ dry-run |

Totales: <N> vencidos, <M> por vencer, <X> personas notificadas.
```

- `✓` = mensaje enviado con éxito
- `✗` = falló el envío (usuario no encontrado en Slack u otro error)
- `🏜️ dry-run` = no se envió (modo dry-run)

Si no hay ningún ticket en riesgo, mostrar:
> "✅ No hay tickets vencidos ni por vencer. La cola está al día."

---

## Tickets con assignee externo

Si hay tickets en riesgo asignados a personas **fuera del TEAM**, mostrar al final:

```
⚠️ Tickets en riesgo con assignee externo (no se envió DM):
| Key          | Summary         | Assignee         | Estado  | Edad  |
|--------------|-----------------|------------------|---------|-------|
| SSHP-XXXXXX  | ...             | external@meli.com | 🔴 Vencido | 96h |
```
