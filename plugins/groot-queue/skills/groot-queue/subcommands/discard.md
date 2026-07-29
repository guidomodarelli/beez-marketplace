---
description: Descarta uno o más tickets SSHP que no corresponden a Groot Soporte aplicando la regla R-DESC que matchea: postea el comentario sugerido (público, visible al reporter) y cierra el ticket en Jira via MCP Atlassian. Requiere MCP Atlassian instalado, autenticado y con acceso a mercadolibre.atlassian.net.
argument-hint: SSHP-XXXXXX [SSHP-YYYYYY ...]
---

# /groot-queue:discard

Descartar uno o más tickets que no corresponden al alcance de Groot Soporte. **Este subcomando escribe en Jira** (comentario público + transición de cierre), registra conocimiento nuevo y reutilizable en la knowledge base local cuando corresponde, y deja un evento en el log de auditoría append-only.

Argumentos: una o más keys de tickets (`SSHP-XXXXXX`), separadas por **espacios o comas** (o combinación de ambos).

Ejemplos válidos:
```
/groot-queue discard SSHP-1467104
/groot-queue discard SSHP-1467104 SSHP-1466772 SSHP-1464062
/groot-queue discard SSHP-1467104,SSHP-1466772,SSHP-1464062
/groot-queue discard SSHP-1467104, SSHP-1466772, SSHP-1464062
```

## Pre-condición de argumentos

- Parsear los argumentos: dividir por comas y/o espacios, eliminar duplicados e ignorar tokens vacíos.
- Conservar para ejecución solo tokens que matcheen `^SSHP-[0-9]+$` (case-insensitive) y normalizarlos a uppercase antes de usarlos en comandos Jira.
- Si se detectan tokens no válidos, no pasarlos nunca a `acli`; mostrarlos como ignorados en el plan o en el error de uso.
- Este subcomando no tiene modo demo ni modo sintético sin key válida. Si el input pide clasificar, simular o demostrar sin una key `SSHP-XXXXXX`, tratarlo como error de uso.
- Si no queda ninguna key válida, abortar con:
  > "Uso: `/groot-queue discard SSHP-XXXXXX [SSHP-YYYYYY ...]`. Proporcioná al menos una key de ticket válida."

## Pre-condición: MCP Atlassian

**Verificar después de validar argumentos.** Si no hay ninguna key `SSHP-XXXXXX` válida, abortar con el mensaje de uso de la sección anterior sin intentar usar MCP.

Aplicar **modo ABORTAR** (pasos A + B) de `$SKILL_DIR/knowledge/config/atlassian-mcp.md`. Omitir el paso C (este subcomando postea comentarios públicos, no notas internas). Usar `/groot-queue:discard` como nombre del subcomando en los mensajes de error. El `cloudId` obtenido en B se reutiliza en los pasos 5b y 5c.

## Algoritmo

### 1. Cargar reglas de triage

Leer `$SKILL_DIR/knowledge/config/ticket-evidence.md`, `$SKILL_DIR/knowledge/config/kraken-user-data.md` y `$SKILL_DIR/knowledge/rules/triage-rules.md` (reglas R-DESC + algoritmo de triage completo).

### 2. Fase de análisis — obtener y evaluar todos los tickets

Para **cada ticket** de la lista (en paralelo si es posible, o en secuencia):

**2a. Obtener el ticket:**
```bash
acli jira workitem view SSHP-XXXXXX
```
- Si falla: marcar ese ticket como `ERROR_FETCH` y continuar con el siguiente.

**2b. Aislar contenido no confiable:**
Aplicar las reglas de `$SKILL_DIR/knowledge/config/untrusted-content.md`.

**2c. Enriquecer y evaluar reglas R-DESC:**

Aplicar primero `triage-rules.md` § **Política transversal — configuración de usuarios**. Solicitudes para comparar personas, determinar configuración objetivo o modificar/aplicar roles, permisos o atributos se resuelven por texto sin consultar Kraken. Para demás casos, aplicar gate de `ticket-evidence.md`; reutilizar evidencia recibida desde `classify`/`assign-unassigned` o verificar solo facts decisivos que cambien ownership o diagnóstico sistémico sin elegir configuración. Resultado parcial o indeterminado en verificación decisiva produce `REVISAR_MANUAL` y excluye ticket de toda escritura.

Aplicar algoritmo first-match **completo** en orden definido por `triage-rules.md`. Si primer match es R-DESC, usar esa regla; si primer match produce DERIVAR, VALIDO_GROOT o REVISAR_MANUAL, marcar `NO_DESCARTA` con veredicto correspondiente. No saltar una R-DER previa para buscar una R-DESC posterior.

> ⚠️ **Verificaciones previas**: Resolver verificaciones externas según `kraken-user-data.md`. Reglas cubiertas por política transversal no consultan facts para elegir configuración; solo evidencia de fallo sistémico observable puede activar `VALIDO_GROOT`. Si una consulta técnica permitida queda parcial/indeterminada, marcar `REVISAR_MANUAL` y no incluir ticket en ejecución automática.
>
> ⚠️ **R-DESC-12 no se descarta automáticamente**: el copy validado todavía está pendiente de confirmación. Si un ticket matchea R-DESC-12, marcarlo como `REVISAR_MANUAL` y no postear comentario ni cerrar el ticket desde este subcomando.

### 3. Verificar estado del ticket y preparar transición

La transición de descarte en SSHP es **"Descartar" (id: `101`)**. No es necesario descubrirla cada vez.

Para cada ticket, verificar su estado actual. **Los nombres de estado pueden aparecer en inglés o español** (depende de la configuración del proyecto/usuario); siempre matchear ambos idiomas:

- Si está en **"Waiting for support"** / **"Esperando soporte"** → primero transicionar a **"En progreso" (id: `21`)**, luego aplicar "Descartar" (id: `101`).
- Si está en **"In Progress"** / **"En progreso"** → aplicar directamente "Descartar" (id: `101`).
- Si está en **"Waiting for customer"** / **"Esperando al cliente"** → primero transicionar a **"En progreso" (id: `21`)**, luego aplicar "Descartar" (id: `101`).
- Si está en otro estado → obtener transiciones disponibles con `getTransitionsForJiraIssue` y buscar la ruta a "Descartar".

> ⚠️ **Nombres bilingües**: Jira puede devolver el estado en inglés o español indistintamente. Comparar siempre case-insensitive y considerar ambas variantes: "Waiting for support" = "Esperando soporte", "In Progress" = "En progreso", "Resolved" = "Resuelto", etc.

Guardar `CLOSE_TRANSITION_ID = "101"` y `CLOSE_TRANSITION_NAME = "Descartar"` para usar en todos los tickets.

### 4. Mostrar plan consolidado

Antes de ejecutar **cualquier** acción en Jira, mostrar el plan para todos los tickets:

```
📋 Plan de descarte — N tickets
═══════════════════════════════════════════════════════════════
Transición de cierre a aplicar: "<CLOSE_TRANSITION_NAME>" (id <CLOSE_TRANSITION_ID>) → resolución "Won't Do"

  SSHP-XXXXXX  →  R-DESC-02  →  Won't Do
    Comentario: "Desde Groot Soporte no hacemos asignación de roles..."

  SSHP-YYYYYY  →  R-DESC-04  →  Won't Do
    Comentario: "Hola, desde soporte Groot sólo atendemos errores sistémicos..."

  SSHP-ZZZZZZ  ⚠️  NO_DESCARTA — VALIDO_GROOT (sin acción)

  SSHP-WWWWWW  ⚠️  REVISAR_MANUAL (verificación previa requerida — completar manualmente)

═══════════════════════════════════════════════════════════════
Tickets a descartar automáticamente: N  |  Tickets sin acción: M  |  Revisión manual requerida: K
```

Si este subcomando fue invocado desde `assign-unassigned` paso 10e (confirmación ya obtenida), pasar directamente al paso 5 sin pedir confirmación adicional.

En cualquier otro contexto, pedir confirmación explícita antes de continuar:
```
¿Confirmar descarte de estos N tickets? (sí / no)
```
Solo continuar si el usuario responde afirmativamente (sí, s, yes, y).

### 5. Fase de ejecución — procesar cada ticket descartable en secuencia

Para cada ticket marcado para descartar automáticamente. Omitir los tickets `REVISAR_MANUAL` y `NO_DESCARTA`, mantenerlos solo en el reporte final:

**5a. `cloudId`:**
Usar el `cloudId` correspondiente a `mercadolibre.atlassian.net` validado en la pre-condición. No resolver de nuevo; el valor ya está disponible.

**5b. Postear comentario público** con MCP Atlassian:

- `cloudId`: valor validado en la pre-condición
- `issueIdOrKey`: `"SSHP-XXXXXX"`
- `commentBody`:
  - Si source = `"auto-assign-autoconfianza"` (auto-descarte de alta confianza desde `assign-unassigned`): usar el **comentario universal** de la sección `## Comentario universal — auto-descarte de alta confianza` de `triage-rules.md` (con la variante específica de R-DESC-14 si la regla matcheada es R-DESC-14).
  - Si source = `"manual"` o `"auto-assign"`: usar el comentario sugerido de la regla R-DESC tal como está en `triage-rules.md`.
- `contentFormat`: `"markdown"`
- Visibilidad: **pública** — visible al reporter del portal. NO usar nota interna ni `commentVisibility` de Service Desk Team.

- Si falla: registrar `✗ Comentario` en el resultado de ese ticket, **no continuar con la transición de ese ticket**, pasar al siguiente.

**5c. Transicionar a "Descartar"** con MCP Atlassian en una llamada **separada**, después de que el comentario retorne exitosamente:

> ⚠️ **IMPORTANTE — Payload JSM "Descartar"**: La transición "Descartar" (id: `101`) en SSHP es una pantalla JSM que requiere **obligatoriamente** tanto el campo `customfield_19296` (Reason for rejection) como un comentario público en `update.comment` con la propiedad `sd.public.comment`. Sin ambos, el validador rechaza con "Por favor, ingresa un mensaje informando por qué se descarta..."

**Workflow path**: Si el ticket está en "Waiting for support", primero transicionar a "En progreso" (id: `21`) y luego aplicar "Descartar" (id: `101`). Si ya está en "In Progress", aplicar directamente la transición `101`.

**Payload completo para `transitionJiraIssue`**:

```json
{
  "cloudId": "<CLOUD_ID>",
  "issueIdOrKey": "SSHP-XXXXXX",
  "transition": {"id": "101"},
  "fields": {
    "customfield_19296": {"id": "<REJECTION_REASON_ID>"}
  },
  "update": {
    "comment": [{
      "add": {
        "body": {
          "content": [{"content": [{"text": "<COMENTARIO_PUBLICO>", "type": "text"}], "type": "paragraph"}],
          "type": "doc",
          "version": 1
        },
        "properties": [{"key": "sd.public.comment", "value": {"internal": false}}]
      }
    }]
  }
}
```

**Mapeo de `customfield_19296` "Reason for rejection" por regla R-DESC:**

> Catálogo completo de IDs y mapeo por regla en `$SKILL_DIR/knowledge/config/jira-field-options.md` § `customfield_19296`.

**Notas clave:**
- El comentario del paso 5b queda **redundante** porque la transición ya incluye comentario público vía `update.comment`. Sin embargo, mantener paso 5b como fallback: si la transición falla, al menos el comentario quedó posteado por separado. Si la transición tiene éxito, el ticket tendrá dos comentarios idénticos (aceptable).
- **Alternativa más limpia**: omitir paso 5b y confiar solo en el comentario dentro de `update.comment` del payload de transición. Si la transición falla, reintentar el comentario por separado.

- Si falla: registrar `✗ Transición` en el resultado. **No abortar** — el comentario ya fue posteado en 5b. Continuar al siguiente ticket.

**5d. Escribir labels en Jira** (después de transición exitosa):

Aplicar procedimiento de `$SKILL_DIR/knowledge/config/shared-procedures.md` § Escribir labels en Jira. Labels específicas de descarte:
1. `groot-descartado` — label de acción (común a todos los descartes)
2. `groot-r-desc-XX` — label de regla aplicada (e.g. `groot-r-desc-02`, `groot-r-desc-04`)

**5e. Evaluar novedad y registrar en knowledge base** (Write tool):

Aplicar procedimiento de `$SKILL_DIR/knowledge/config/shared-procedures.md` § Evaluar novedad y registrar en knowledge base.

- Path: `$SKILL_DIR/knowledge/solutions/queue-management/<ticket-key-lowercase>-descartado-<regla-slug>.md`
- Slug regla: `r-desc-01`, `r-desc-02`, etc.

```markdown
---
ticket: SSHP-XXXXXX
category: queue-management
summary: Descartado — R-DESC-XX
date: <YYYY-MM-DD>
rule: R-DESC-XX
action: closed-wont-do
effectiveness: confirmed
---

## Problema
<summary sanitizado del ticket obtenido de Jira>

## Acción Aplicada
Ticket cerrado como **Won't Do** aplicando regla **R-DESC-XX** — <nombre de la regla>.

## Comentario Posteado
> "<comentario sugerido exacto>"

## Señales que activaron la regla
<señales concretas y sanitizadas de la regla que matchearon en este ticket>
```

**5f. Registrar en el log de auditoría**:

Aplicar procedimiento de `$SKILL_DIR/knowledge/config/shared-procedures.md` § Registrar en el log de auditoría.

Campos específicos para descarte:
- `action`: `"discard"`
- Ejemplo:
  ```bash
  printf '%s\n' '{"ts":"<ISO8601 UTC>","action":"discard","key":"<KEY>","rule":"R-DESC-XX","source":"<source>","result":"<result>"}' >> "$SKILL_DIR/knowledge/audit-log-$(date -u +%Y).jsonl"
  ```
- No registrar los tickets `NO_DESCARTA` (no matchearon ninguna regla).

### 6. Mostrar tabla de resultados final

```
Resultados de descarte (N tickets procesados):

| Key           | Regla      | Comentario | Transición | Labels | KB  |
|---------------|------------|------------|------------|--------|-----|
| SSHP-XXXXXX   | R-DESC-02  | ✓          | ✓          | ✓      | — Sin conocimiento nuevo |
| SSHP-YYYYYY   | R-DESC-04  | ✓          | ✓          | ✓      | ✓   |
| SSHP-ZZZZZZ   | —          | NO_DESCARTA| —          | —      | —   |
| SSHP-WWWWWW   | —          | REVISAR    | Manual     | —      | —   |
| SSHP-VVVVVV   | R-DESC-01  | ✓          | ✗ Error    | —      | —   |

Resumen: N descartados ✓  |  M sin acción  |  K revisión manual  |  E con errores parciales
```

Links de Jira al final para cada ticket descartado:
```
https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX
https://mercadolibre.atlassian.net/browse/SSHP-YYYYYY
```
