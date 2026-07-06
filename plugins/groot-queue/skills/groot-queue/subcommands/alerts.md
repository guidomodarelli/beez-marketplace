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
acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type = Incident AND resolution = Unresolved ORDER BY created DESC"
```

Filtrar **solo tickets que tienen assignee** (sin assignee → no se puede notificar; para esos, usar `/groot-queue:assign-unassigned` primero).

### 2. Clasificar y aplicar triage

Para cada ticket:
1. Aplicar el **triage de veredicto** de `triage-rules.md`.
2. **Excluir** tickets con veredicto `DESCARTAR` o `DERIVAR` (no tiene sentido alertar sobre tickets que no corresponden a Groot).
3. Clasificar en Dimensión 1 (categoría) y Dimensión 2 (urgencia) según `classification.md`.

### 3. Determinar estado de SLA

Para cada ticket restante, determinar su estado de SLA basándose en la **edad del ticket** (horas desde su creación hasta ahora):

| Estado | Condición | Indicador |
|--------|-----------|-----------|
| **VENCIDO** | Edad > 72h **O** (status = "Esperando por Soporte" sin respuesta del equipo > 48h) | 🔴 |
| **POR VENCER** | Edad entre 24h y 72h **Y** urgencia ≥ 4 **O** (status = "Esperando por Soporte" sin respuesta del equipo entre 24h y 48h) | 🟡 |

- Si un ticket no califica como VENCIDO ni POR VENCER, descartarlo del reporte.
- "Sin respuesta del equipo" significa que no hay comentario interno posterior al último comentario del reporter o a la transición a "Esperando por Soporte".

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
