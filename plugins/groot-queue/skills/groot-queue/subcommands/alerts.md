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

## Pre-condición: MCP Atlassian (para SLA "Time to resolution")

El paso 3 necesita consultar `customfield_12400` de cada ticket vía MCP Atlassian. Aplicar **modo DEGRADAR** (pasos A + B) de `$SKILL_DIR/knowledge/config/atlassian-mcp.md`. Omitir el paso C (este subcomando no postea notas internas). Usar `ATLASSIAN_MCP_AVAILABLE` como nombre de la variable de estado. El warning de degradación debe aclarar: "SLA `Time to resolution` no se puede verificar — solo se evaluará la condición de `Esperando por Soporte` para determinar alertas."

---

## Pre-condición: Slack MCP (solo si NO es `--dry-run`)

El nombre de las herramientas Slack varía según el proveedor y la configuración del MCP. Buscar cualquier tool que contenga `slack` en su nombre (ej: `mcp__plugin_slack_slack__authenticate`, `mcp__slack__authenticate`, u otra variante).

1. Verificar si existe **alguna** tool de Slack disponible en el contexto (buscar tools que contengan `slack` y expongan capacidad de enviar DM).
   - Si **no existe ninguna** → abortar con:
     ```
     ⚠️ Slack MCP no disponible.
     Para Claude Code: claude mcp add slack
     Para Codex: configurar el MCP de Slack en .codex/mcp.json
     O usá --dry-run para ver el reporte sin enviar mensajes.
     ```
2. Si existe → autenticarse usando la tool de autenticación de Slack disponible (si no lo está ya).

---

## Procedimiento

### 1. Obtener tickets abiertos asignados

Leer las referencias:
- `$SKILL_DIR/knowledge/classification.md`
- `$SKILL_DIR/knowledge/triage-rules.md`

Ejecutar el JQL base:
```bash
acli jira workitem search --jql "project = SSHP AND Squad = Groot AND resolution = Unresolved ORDER BY created DESC"
```

Filtrar **solo tickets que tienen assignee** (sin assignee → no se puede notificar; para esos, usar `/groot-queue:assign-unassigned` primero).

### 2. Clasificar y aplicar triage

Para cada ticket:
1. Aplicar el **triage de veredicto** de `triage-rules.md`.
2. **Excluir** tickets con veredicto `DESCARTAR` o `DERIVAR` (no tiene sentido alertar sobre tickets que no corresponden a Groot).
3. Clasificar en Dimensión 1 (categoría) según `classification.md` (se usa en el mensaje del paso 5).

### 3. Determinar estado de SLA

Para cada ticket restante, determinar su estado de SLA basándose en el campo **Time to resolution** del ticket (SLA nativo de Jira Service Management).

**Obtener el campo "Time to resolution" — `customfield_12400`:**

El campo **NO aparece** en el output de `acli jira workitem view`. Requiere MCP Atlassian.

**Método principal: búsquedas batch por lote de keys (sin perder tickets 51+):**

Después del paso 2, construir `ticket_keys_alertables` con **todos** los tickets restantes (los que tienen assignee y no fueron excluidos por triage). No usar una única búsqueda global limitada a 50, porque deja tickets fuera del fetch de SLA.

Dividir `ticket_keys_alertables` en lotes de hasta `50` keys y consultar **todos los lotes, uno por uno, hasta agotar la lista completa** con `searchJiraIssuesUsingJql`, pidiendo **solo los campos necesarios**:

```
searchJiraIssuesUsingJql(
  cloudId: "<cloudId de mercadolibre.atlassian.net>",
  jql: "issuekey in (SSHP-1234567, SSHP-1234568, ..., SSHP-1234616) ORDER BY created DESC",
  fields: ["customfield_12400", "status", "assignee", "summary", "created"],
  maxResults: 50
)
```

Ese `maxResults: 50` es **por lote**, no global. Si hay 137 tickets alertables, se hacen 3 búsquedas (50 + 50 + 37). **No cortar después del primer batch**.

> ⚠️ **Usar `maxResults`, no `limit`**. En el MCP Atlassian de `searchJiraIssuesUsingJql`, `limit` no es un argumento soportado para esta tool y puede hacer fallar la búsqueda antes de devolver `customfield_12400`.

> ⚠️ **Nunca usar `fields: ["*all"]`** — genera respuestas de ~300K chars que saturan el contexto. Siempre pedir solo los campos listados arriba.

> ⚠️ **No hacer llamadas individuales `getJiraIssue` por ticket como camino principal** — con 25+ tickets son 25+ llamadas. El camino principal debe ser batch por lotes.

Al terminar los lotes:

1. Construir un mapa `issue_key -> customfield_12400/status/assignee/summary/created`.
2. Verificar cobertura completa: `missing_keys = ticket_keys_alertables - fetched_issue_keys`.
3. Si `missing_keys` no está vacío, hacer `getJiraIssue` **solo para esas keys faltantes** (en paralelo) con:
   ```
   getJiraIssue(
     cloudId: "<cloudId>",
     issueIdOrKey: "<KEY faltante>",
     fields: ["customfield_12400", "status", "assignee", "summary", "created"]
   )
   ```

> ⚠️ **Nunca degradar silenciosamente un ticket a "SLA desconocido" solo porque quedó fuera de un batch**. Si una key no volvió en `searchJiraIssuesUsingJql`, recuperarla explícitamente antes de clasificarla.

**Fallback si `searchJiraIssuesUsingJql` no retorna `customfield_12400`:**
Algunos entornos no exponen campos SLA vía search. Si `customfield_12400` viene `null` para **todos** los tickets recuperados por batch, hacer una **única** llamada `getJiraIssue` de prueba con un ticket para confirmar:
```
getJiraIssue(
  cloudId: "<cloudId>",
  issueIdOrKey: "<primer KEY>",
  fields: ["customfield_12400"]
)
```
Si el campo sí viene en `getJiraIssue` pero no en search, entonces usar `getJiraIssue` en paralelo para todos los tickets que sigan sin `customfield_12400`. Este es el fallback de compatibilidad cuando search no expone el SLA; la recuperación de `missing_keys` anterior cubre el caso distinto en el que faltan keys porque un batch no devolvió todo el conjunto solicitado.

**Estructura del campo `customfield_12400`:**

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

**Parseo — usar siempre `breachTime.jira` (tiempo calendario):**

> ⚠️ **NO usar `remainingTime.millis`** para calcular horas restantes. Ese campo cuenta solo **horas hábiles** (working time), no calendario. Un `remainingTime` de 25h working puede significar 70h de calendario. Siempre comparar `breachTime.jira` contra `ahora` para obtener las horas reales de calendario.

- `ongoingCycle.breached == true` → **VENCIDO** directamente (no hace falta comparar fechas)
- `ongoingCycle.breached == false` → calcular: `horas_restantes = breachTime.jira - ahora` (en horas de calendario, misma timezone)
  - Si `horas_restantes` ≤ 48h → **POR VENCER**
  - Si `horas_restantes` > 48h → no alertar
- Si `ongoingCycle` es null y hay `completedCycles` → el SLA ya se completó (ticket resuelto), no alertar.

**Fallback si MCP Atlassian no está disponible:**
Si MCP no está disponible (verificación de pre-condición), evaluar **solo** por la condición de "Esperando por Soporte" (ver abajo). Mostrar warning:
```
⚠️ MCP Atlassian no disponible — SLA "Time to resolution" no se puede verificar.
Solo se evaluará la condición de "Esperando por Soporte".
```

**Reglas de clasificación:**

| Estado | Condición | Indicador |
|--------|-----------|-----------|
| **VENCIDO** | `ongoingCycle.breached == true` **O** (status = "Esperando por Soporte" sin respuesta del equipo > 48h) | 🔴 |
| **POR VENCER** | `breachTime.jira - ahora` ≤ 48h calendario **O** (status = "Esperando por Soporte" sin respuesta del equipo entre 24h y 48h) | 🟡 |

- Si un ticket no califica como VENCIDO ni POR VENCER, descartarlo del reporte.
- Si un ticket no tiene el campo `customfield_12400` (null o vacío), evaluarlo solo por la condición de "Esperando por Soporte". Si tampoco aplica, descartarlo.
- "Sin respuesta del equipo" significa que no hay comentario interno posterior al último comentario del reporter o a la transición a "Esperando por Soporte".
- Un ticket que matchee ambas condiciones (SLA breached + "Esperando por Soporte" >48h) se clasifica una sola vez como VENCIDO (no se duplica).

### 4. Agrupar por responsable

Crear un mapa `assignee_email → { vencidos: [...], por_vencer: [...] }`.

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
