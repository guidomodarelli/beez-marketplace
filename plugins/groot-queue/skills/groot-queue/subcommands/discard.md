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

### 3. Verificar estado, assignee y preparar transición

La transición de descarte en SSHP es **"Descartar" (id: `101`)**. No es necesario descubrirla cada vez.

Para cada ticket, resolver estado mediante `$SKILL_DIR/knowledge/config/jira-field-options.md` § **Semántica de workflow Jira SSHP**:

- Si pertenece a `WAITING_FOR_SUPPORT` o `WAITING_FOR_CUSTOMER`, resolver una única transición cuyo destino sea `IN_PROGRESS`, ejecutarla y verificar estado final antes de continuar.
- Si pertenece a `IN_PROGRESS`, aplicar directamente "Descartar" (id: `101`).
- Si el estado no pertenece a un grupo reconocido, la transición hacia `IN_PROGRESS` no es única o la verificación falla, registrar `SKIP_ESTADO_NO_RECONOCIDO` y no asignar, comentar ni descartar.

> ⚠️ **Nombres bilingües**: usar solo aliases exactos normalizados de la fuente canónica. Jira puede devolver `Waiting for support`, `Esperando por Soporte`, `In Progress`, `En progreso` o `En curso`; no inferir traducciones nuevas.

Guardar `CLOSE_TRANSITION_ID = "101"` y `CLOSE_TRANSITION_NAME = "Descartar"` para usar en todos los tickets.

Antes de la primera transición, congelar `discardAssignee`:
- Si ticket ya tiene assignee, conservar su email como `discardAssignee`.
- Si ticket no tiene assignee y flujo es directo, resolver email de `currentUser()` con `acli jira auth status` y usarlo como `discardAssignee`.
- Si `assign-unassigned` delega descarte, recibir email preseleccionado del siguiente miembro `$QUEUE` como `discardAssignee`; no reconstruir ni rebarajar TEAM.
- Si no se puede resolver `discardAssignee`, no descartar ticket: registrar `✗ Asignación previa` y continuar.

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

**5b. Transicionar, asignar y verificar antes de descartar**:

1. Revalidar estado con `$SKILL_DIR/knowledge/config/jira-field-options.md` § **Resolver y transicionar de forma segura**. Si pertenece a un estado de espera, resolver y ejecutar transición única hacia `IN_PROGRESS` y verificarla en llamada separada; si ya pertenece a `IN_PROGRESS`, continuar. Estado desconocido, ambiguo o no verificable termina en `SKIP_ESTADO_NO_RECONOCIDO` sin mutaciones.
2. En una llamada ACLI separada, asignar `discardAssignee`:
   ```bash
   acli jira workitem assign --key SSHP-XXXXXX --assignee <discardAssignee> --yes
   ```
3. Verificar assignee mediante `acli jira workitem view`. Si no coincide, reintentar assign una sola vez. Si sigue sin coincidir, registrar `✗ Asignación previa` y no descartar.
4. Si ticket ya pertenecía a `IN_PROGRESS` según el catálogo, asignar y verificar de la misma forma antes de continuar.

El assignee final recibe novedades de comentarios posteriores al descarte. Esta asignación conserva assignee existente en descarte directo o usa `currentUser()` cuando no había uno; desde `assign-unassigned` usa el miembro preseleccionado del TEAM.

**5c. Postear comentario público** con MCP Atlassian:

- `cloudId`: valor validado en la pre-condición
- `issueIdOrKey`: `"SSHP-XXXXXX"`
- `commentBody`:
  - Si source = `"auto-assign-autoconfianza"` (auto-descarte de alta confianza desde `assign-unassigned`): usar el **comentario universal** de la sección `## Comentario universal — auto-descarte de alta confianza` de `triage-rules.md` (con la variante específica de R-DESC-14 si la regla matcheada es R-DESC-14).
  - Si source = `"manual"` o `"auto-assign"`: usar el comentario sugerido de la regla R-DESC tal como está en `triage-rules.md`.
- `contentFormat`: `"markdown"`
- Visibilidad: **pública** — visible al reporter del portal. NO usar nota interna ni `commentVisibility` de Service Desk Team.

- Si falla: registrar `✗ Comentario` en el resultado de ese ticket, **no continuar con la transición de ese ticket**, pasar al siguiente.

**5d. Transicionar a "Descartar"** con MCP Atlassian en una llamada **separada**, después de que el comentario retorne exitosamente:

> ⚠️ **IMPORTANTE — Payload JSM "Descartar"**: La transición "Descartar" (id: `101`) en SSHP es una pantalla JSM que requiere **obligatoriamente** tanto el campo `customfield_19296` (Reason for rejection) como un comentario público en `update.comment` con la propiedad `sd.public.comment`. Sin ambos, el validador rechaza con "Por favor, ingresa un mensaje informando por qué se descarta..."

**Workflow path**: Resolver primero el estado mediante `$SKILL_DIR/knowledge/config/jira-field-options.md` § **Semántica de workflow Jira SSHP**. Desde `WAITING_FOR_SUPPORT` o `WAITING_FOR_CUSTOMER`, transicionar y verificar `IN_PROGRESS` antes de aplicar "Descartar" (id `101`). Desde `IN_PROGRESS`, aplicar directamente transición `101`. Estado no reconocido, ambiguo o no verificable: no publicar comentario ni ejecutar transición `101`.

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

**5e. Revalidar assignee y reconciliar watcher del ejecutor** (después de descarte exitoso):

1. Releer ticket y verificar que `discardAssignee` siga como assignee. Si transición de descarte lo pisó, reintentar assign una vez y verificar.
2. Aplicar `$SKILL_DIR/knowledge/config/shared-procedures.md` § Reconciliar watcher del ejecutor.
3. Si assignee es actor (`currentUser()`), conservar watcher actor. Si es otra persona, remover exclusivamente watcher actor.
4. Fallo de assignee final o watcher cleanup deja `partial-error`, no revierte descarte ni remueve otros watchers.

**5f. Escribir labels en Jira** (después de transición exitosa):

Aplicar procedimiento de `$SKILL_DIR/knowledge/config/shared-procedures.md` § Escribir labels en Jira. Labels específicas de descarte:
1. `groot-descartado` — label de acción (común a todos los descartes)
2. `groot-r-desc-XX` — label de regla aplicada (e.g. `groot-r-desc-02`, `groot-r-desc-04`)

**5g. Evaluar novedad y registrar en knowledge base** (Write tool):

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

**5h. Registrar en el log de auditoría**:

Aplicar procedimiento de `$SKILL_DIR/knowledge/config/shared-procedures.md` § Registrar en el log de auditoría.

Campos específicos para descarte:
- `action`: `"discard"`
- `watcher_cleanup`: estado seguro de reconciliación y conteos agregados opcionales; nunca identidades.
- Si descarte fue exitoso pero assignee final o watcher cleanup falló, usar `result: "partial-error"`.
- Ejemplo:
  ```bash
  printf '%s\n' '{"ts":"<ISO8601 UTC>","action":"discard","key":"<KEY>","rule":"R-DESC-XX","source":"<source>","result":"<result>"}' >> "$SKILL_DIR/knowledge/audit-log-$(date -u +%Y).jsonl"
  ```
- No registrar los tickets `NO_DESCARTA` (no matchearon ninguna regla).

### 6. Mostrar tabla de resultados final

```
Resultados de descarte (N tickets procesados):

| Key           | Regla      | Assignee final | Comentario | Transición | Watcher | Labels | KB  |
|---------------|------------|----------------|------------|------------|---------|--------|-----|
| SSHP-XXXXXX   | R-DESC-02  | ✓ verificado   | ✓          | ✓          | ✓ removido | ✓ | — Sin conocimiento nuevo |
| SSHP-YYYYYY   | R-DESC-04  | ✓ verificado   | ✓          | ✓          | — actor assignee | ✓ | ✓ |
| SSHP-ZZZZZZ   | —          | —              | NO_DESCARTA| —          | — | — | — |
| SSHP-WWWWWW   | —          | —              | REVISAR    | Manual     | — | — | — |
| SSHP-VVVVVV   | R-DESC-01  | ✗ Error        | ✓          | ✗ Error    | — | — | — |

Resumen: N descartados ✓  |  M sin acción  |  K revisión manual  |  E con errores parciales
```

Links de Jira al final para cada ticket descartado:
```
https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX
https://mercadolibre.atlassian.net/browse/SSHP-YYYYYY
```
