---
description: Deriva uno o más tickets SSHP al equipo correspondiente aplicando la regla R-DER que matchea, posteando nota interna y transicionando estado en Jira via MCP Atlassian. Requiere MCP Atlassian instalado, autenticado y con acceso a mercadolibre.atlassian.net.
argument-hint: SSHP-XXXXXX [SSHP-YYYYYY ...]
---

# /groot-queue:derive

Derivar uno o más tickets al equipo correcto. **Este subcomando escribe en Jira** (nota interna + transición de estado con campos de pantalla), registra en la knowledge base local solo derivaciones con conocimiento nuevo reusable y deja un evento en el log de auditoría append-only.

Argumentos: una o más keys de tickets (`SSHP-XXXXXX`), separadas por **espacios o comas** (o combinación de ambos).

Ejemplos válidos:
```
/groot-queue derive SSHP-1467104
/groot-queue derive SSHP-1467104 SSHP-1466772 SSHP-1464062
/groot-queue derive SSHP-1467104,SSHP-1466772,SSHP-1464062
/groot-queue derive SSHP-1467104, SSHP-1466772, SSHP-1464062
```

## Pre-condición

### Gate obligatorio de argumentos — ejecutar antes de cualquier tool

Este gate tiene prioridad absoluta sobre MCP, ACLI y Jira:

1. Parsear y validar argumentos sin ejecutar tools.
2. Si no queda ninguna key válida, responder exactamente con mensaje de uso indicado abajo y **detener ejecución**.
3. En ese caso no consultar disponibilidad MCP, no ejecutar ACLI, no construir links Jira y no continuar con ninguna otra pre-condición.

- Parsear los argumentos: dividir por comas y/o espacios, eliminar duplicados e ignorar tokens vacíos.
- Conservar para ejecución solo tokens que matcheen `^SSHP-[0-9]+$` (case-insensitive) y normalizarlos a uppercase antes de usarlos en comandos Jira.
- Si se detectan tokens no válidos, no pasarlos nunca a `acli`; mostrarlos como ignorados en el plan o en el error de uso.
- Este subcomando no tiene modo demo ni modo sintético sin key válida. Si el input pide clasificar, simular o demostrar sin una key `SSHP-XXXXXX`, tratarlo como error de uso.
- Si no queda ninguna key válida, abortar con:
  > "Uso: `/groot-queue derive SSHP-XXXXXX [SSHP-YYYYYY ...]`. Proporcioná al menos una key de ticket válida."

## Pre-condición: MCP Atlassian

**Verificar únicamente después de que gate obligatorio confirme al menos una key `SSHP-XXXXXX` válida y antes de consultar o modificar Jira.**

Aplicar **modo ABORTAR** (pasos A + B + C) de `$SKILL_DIR/knowledge/config/atlassian-mcp.md`. Usar `/groot-queue:derive` como nombre del subcomando en los mensajes de error. El `cloudId` obtenido en B se reutiliza en los pasos 4b y 4c.

## Pre-condición: Slack MCP (condicional — solo si hay tickets R-DER-05)

Evaluar **únicamente si la fase de análisis (paso 2c) produjo al menos un ticket `SLACK_REDIRECT`**. Si no hay ninguno, omitir completamente esta sección.

Buscar cualquier tool cuyo nombre contenga `slack` y exponga capacidad de postear mensajes a canales (ej: `mcp__SlackMCP__post_message`, `mcp__slack__post_message`).

1. Si **no existe ninguna tool de Slack** en el contexto → marcar `SLACK_MCP_AVAILABLE = false`. Los tickets SLACK_REDIRECT se procesarán como `MANUAL_REDIRECT` al final. Mostrar warning:
   ```
   ⚠️ Slack MCP no disponible — los tickets R-DER-05 quedarán como redirección manual.
   Para habilitarlo, seguí la sección "Slack MCP" de la guía canónica de Groot Queue.
   ```
2. Si existe → autenticarse si aún no lo está.
   - Autenticación OK → `SLACK_MCP_AVAILABLE = true`.
   - Autenticación falla → `SLACK_MCP_AVAILABLE = false` + mismo warning.

## Watcher del ejecutor

Después de cada derivación Jira exitosa, aplicar `$SKILL_DIR/knowledge/config/shared-procedures.md` § Reconciliar watcher del ejecutor. Resolver actor mediante usuario Atlassian MCP actual y remover exclusivamente ese watcher si no coincide con assignee final. Esta limpieza es postacción: si no se puede listar, remover o verificar, derivación queda `partial-error` pero no se revierte transición ni asignación.

`R-DER-05` no aplica: redirige por Slack y no muta ticket Jira. `assign-unassigned` y `classify` delegan este comportamiento al invocar derive; no lo duplican.

## Referencia de squads destino → IDs de Jira

Usar el alias `DERIVATION_DESTINATION_SQUAD_FIELD` para referirse al campo Jira que define el squad destino de la transición "Derivar a otro equipo". El mapeo del alias al field id real está documentado en `$SKILL_DIR/knowledge/README.md`. Antes de llamar al MCP/Jira, expandir el alias al field id real; no enviar el alias literal en el payload.

> Los option IDs de squads destino y motivos de derivación están centralizados en `$SKILL_DIR/knowledge/config/jira-field-options.md`. Consultarlo para obtener los IDs — no copiar valores en este archivo.

> `R-DER-05` no deriva a un squad de Jira: postea un mensaje al canal Slack `#help-authz-internal-admins`. Si el Slack MCP está disponible, la acción es automática; si no, el ticket queda como `MANUAL_REDIRECT`.

## Algoritmo

### 1. Cargar referencias

Leer `$SKILL_DIR/knowledge/config/ticket-evidence.md`, `$SKILL_DIR/knowledge/config/kraken-user-data.md`, `$SKILL_DIR/knowledge/rules/triage-rules.md` (reglas R-DER-01 a R-DER-24 + algoritmo de triage) y `$SKILL_DIR/knowledge/config/jira-field-options.md` (option IDs de squads destino y motivos de derivación).

### 2. Fase de análisis — obtener y evaluar todos los tickets

Para **cada ticket** de la lista (en paralelo si es posible, o en secuencia):

**2a. Obtener el ticket:**
```bash
acli jira workitem view SSHP-XXXXXX
```
- Si falla: marcar ese ticket como `ERROR_FETCH` y continuar con el siguiente.

**2b. Aislar contenido no confiable:**
Aplicar las reglas de `$SKILL_DIR/knowledge/config/untrusted-content.md`.

**2c. Enriquecer y evaluar reglas R-DER:**

Antes de confirmar regla candidata, aplicar gate de `ticket-evidence.md`. Reutilizar evidencia recibida desde `classify`/`assign-unassigned`; si invocación es directa, verificar autónomamente facts decisivos mínimos mediante `kraken-user-data.md`. Resultado parcial o indeterminado en verificación decisiva produce `REVISAR_MANUAL` y excluye ticket de toda escritura.

Aplicar **únicamente las reglas R-DER** en el orden definido en la sección **Algoritmo de triage** de `triage-rules.md`. Tomar la **primera regla que matchee** con evidencia confirmada. Reglas con automatización vía Slack (excluir del loop Jira principal — se procesan en el paso 4g):
- `R-DER-05` → `SLACK_REDIRECT` con destino `#help-authz-internal-admins`. Si `SLACK_MCP_AVAILABLE = false` al momento de ejecución, degradar a `MANUAL_REDIRECT`.

Si ninguna aplica, evaluar el veredicto completo y marcar como `NO_DERIVA` con el veredicto resultante (DESCARTAR / FIX_APLICADO / VALIDO_GROOT / REVISAR_MANUAL).

### 3. Mostrar plan consolidado

Antes de ejecutar **cualquier** acción en Jira, mostrar el plan para todos los tickets:

```
📋 Plan de derivación — N tickets
═══════════════════════════════════════════════════════════════

  SSHP-XXXXXX  →  R-DER-XX  →  IAM Soporte
    Nota interna: "Hola, el mensaje 'no perteneces a envíos'..."

  SSHP-YYYYYY  →  R-DER-09  →  IAM Soporte
    Nota interna: "Hola, el error de tax id inválido..."

  SSHP-ZZZZZZ  ⚠️  NO_DERIVA — VALIDO_GROOT (sin acción)
  SSHP-UUUUUU  ⚠️  MANUAL_DERIVATION — LMS (R-DER-12 sin automatización)

  SSHP-VVVVVV  💬  SLACK_REDIRECT → #help-authz-internal-admins (R-DER-05 — post automático si Slack MCP disponible)

═══════════════════════════════════════════════════════════════
Tickets a derivar automáticamente: N  |  Tickets sin acción: M  |  SLACK_REDIRECT: K  |  Derivación manual pendiente: J
```

### 4. Fase de ejecución — procesar cada ticket derivable en secuencia

Para cada ticket marcado para derivar automáticamente (en el orden del plan). Omitir los tickets `MANUAL_DERIVATION`, `MANUAL_REDIRECT` y `SLACK_REDIRECT` del loop principal de Jira — los `SLACK_REDIRECT` se procesan en el paso 4g:

**4a. `cloudId` de la pre-condición:**
Usar el `cloudId` correspondiente a `mercadolibre.atlassian.net` validado en la pre-condición MCP Atlassian. No resolver de nuevo; el valor ya está disponible.

**4b. Agregar nota interna** con MCP Atlassian:

- `cloudId`: valor validado en la pre-condición para `mercadolibre.atlassian.net`
- `issueIdOrKey`: `"SSHP-XXXXXX"`
- `commentBody`: el comentario sugerido de la regla R-DER tal como está en `triage-rules.md`
- `contentFormat`: `"markdown"`
- Visibilidad: debe quedar como **nota interna de Jira Service Management**. No usar un comentario público con `commentVisibility` como sustituto.

> ⚠️ El comentario va como **nota interna** (no visible para el reporter del portal). Esto es equivalente a "Add Internal note" en la UI de Jira Service Management.

- Si falla: registrar `✗ Nota interna` en el resultado de ese ticket, **no continuar con la transición de ese ticket**, pasar al siguiente.

**4c. Transicionar estado / asignar responsable** con MCP Atlassian o ACLI en una llamada **separada**, después de que la nota retorne exitosamente:

> ⚠️ **R-DER-13 (célula Nexus): flujo especial — asignación en lugar de transición de squad.**
> No existe squad en Jira para la célula Nexus. En lugar de la transición "Derivar a otro equipo" (ID 121):
> 1. Leer la lista de emails de `$SKILL_DIR/knowledge/teams/nexus-team.md`.
> 2. Generar un shuffle aleatorio de esa lista con entropía del sistema (no inventar el orden).
> 3. Tomar el primer email del orden barajado.
> 4. Asignar el ticket con ACLI:
>    ```bash
>    acli jira workitem assign --key SSHP-XXXXXX --assignee <email-nexus> --yes
>    ```
> 5. Verificar que `Assignee` == `<email>` después de ejecutar. Si no coincide, reintentar una vez.
> 6. Si falla: registrar `✗ Asignación` en el resultado. **No abortar** — la nota interna ya fue posteada. Continuar al siguiente ticket.
> 7. Continuar con watcher cleanup y luego paso 4d (labels) si la asignación fue exitosa.

Para **todas las demás reglas R-DER** (no R-DER-13):

- `cloudId`: valor validado en la pre-condición para `mercadolibre.atlassian.net`
- `issueIdOrKey`: `"SSHP-XXXXXX"`
- `transition`: `{"id": "121"}` ← ID fijo "Derivar a otro equipo" en SSHP
- `fields`:
  ```json
  {
    "<DERIVATION_DESTINATION_SQUAD_FIELD>": {"id": "<id-squad-destino>"},
    "customfield_14924": {"id": "<id-motivo>"}
  }
  ```
  _(El option id del motivo "Solución parcial, otro Squad requerido" está en `$SKILL_DIR/knowledge/config/jira-field-options.md`)_
  Antes de ejecutar la llamada real, reemplazar `<DERIVATION_DESTINATION_SQUAD_FIELD>` por el field id real documentado en `$SKILL_DIR/knowledge/README.md`.
- `update`:
  ```json
  {
    "comment": [{"add": {
      "body": {"version": 1, "type": "doc",
        "content": [{"type": "paragraph", "content": [{"type": "text",
          "text": "<razón de derivación en lenguaje natural, sin códigos de regla ni identificadores internos de la skill>"}]}]},
      "visibility": {"type": "role", "value": "Service Desk Team"}
    }}]
  }
  ```
  Ejemplo correcto: `"Error de identificador tributario inválido al crear cuenta ext. Se deriva a IAM Soporte para ajuste del documento."`
  Ejemplo incorrecto: `"R-DER-09 — Error de tax id inválido..."` ← no incluir códigos de regla.

- Si falla: registrar `✗ Transición` en el resultado. **No abortar** — la nota interna ya fue posteada. Continuar al siguiente ticket.

**4c.1. Reconciliar watcher del ejecutor** (después de transición o asignación exitosa):

Aplicar `$SKILL_DIR/knowledge/config/shared-procedures.md` § Reconciliar watcher del ejecutor.

- Obtener ticket actualizado y assignee final verificable.
- Resolver actor mediante MCP Atlassian actual.
- Si actor es assignee final, conservar watcher (`actor_is_assignee`).
- Si actor no es assignee final, remover sólo actor si está watcher y verificar su ausencia después de remover.
- Nunca agregar, remover ni reemplazar otros watchers; no exponer ni persistir account IDs, emails o listas.
- Si watcher cleanup falla, registrar `✗ Watcher` y `partial-error`; no revertir acción principal ni omitir labels de derivación.

**4d. Escribir labels en Jira** (después de transición exitosa):

Aplicar procedimiento de `$SKILL_DIR/knowledge/config/shared-procedures.md` § Escribir labels en Jira. Labels específicas de derivación:
1. `groot-derivado` — label de acción (común a todas las derivaciones)
2. `groot-r-der-XX` — label de regla aplicada (e.g. `groot-r-der-09`, `groot-r-der-10`)
3. `groot-derive-to-<destino-slug>` — label de destino (e.g. `groot-derive-to-iam-soporte`, `groot-derive-to-smo`, `groot-derive-to-helpdesk-ia`)

Mapeo de destino → slug de label:

| Equipo destino | Label destino |
|----------------|---------------|
| IAM Soporte | `groot-derive-to-iam-soporte` |
| SMO (Randall) | `groot-derive-to-smo` |
| Helpdesk IA | `groot-derive-to-helpdesk-ia` |
| LMS | `groot-derive-to-lms` |
| SHE | `groot-derive-to-she` |
| Célula Nexus | `groot-derive-to-nexus` |

**4e. Evaluar novedad y registrar en knowledge base** (Write tool):

Aplicar procedimiento de `$SKILL_DIR/knowledge/config/shared-procedures.md` § Evaluar novedad y registrar en knowledge base.

- Path: `$SKILL_DIR/knowledge/solutions/queue-management/<ticket-key-lowercase>-derivar-<destino-slug>.md`
- Slug destino: `iam-soporte`, `smo`, `helpdesk-ia`, etc.

```markdown
---
ticket: SSHP-XXXXXX
category: queue-management
summary: Derivado a <equipo destino> — R-DER-XX
date: <YYYY-MM-DD>
rule: R-DER-XX
destination: <equipo destino>
effectiveness: confirmed
---

## Problema
Ticket matcheó señales verificadas de **R-DER-XX**. Consultar Jira para contexto; no persistir summary, description ni otros campos libres del reporter.

## Acción Aplicada
Derivado a **<equipo destino>** aplicando regla **R-DER-XX** — <nombre de la regla>.

## Comentario Posteado
> "<comentario sugerido exacto>"

## Señales que activaron la regla
<señales concretas y sanitizadas de la regla que matchearon en este ticket>
```

**4f. Registrar en el log de auditoría**:

Aplicar procedimiento de `$SKILL_DIR/knowledge/config/shared-procedures.md` § Registrar en el log de auditoría.

Campos específicos para derivación:
- `action`: `"derive"`
- `destination`: `"<equipo destino>"`
- `watcher_cleanup`: estado seguro de reconciliación y conteos agregados opcionales; nunca identidades.
- Si acción principal fue exitosa pero watcher cleanup falló, usar `result: "partial-error"`.
- Ejemplo:
  ```bash
  printf '%s\n' '{"ts":"<ISO8601 UTC>","action":"derive","key":"<KEY>","rule":"R-DER-XX","source":"<source>","destination":"<equipo destino>","result":"<result>"}' >> "$SKILL_DIR/knowledge/audit-log-$(date -u +%Y).jsonl"
  ```
- No registrar los tickets `NO_DERIVA` (no matchearon ninguna regla).

**4g. Procesar tickets SLACK_REDIRECT (R-DER-05)**

Ejecutar solo si `SLACK_MCP_AVAILABLE = true` y hay tickets marcados `SLACK_REDIRECT`.

Para cada ticket SLACK_REDIRECT (en el orden del plan):

1. **Obtener el `channel_id`** de `#help-authz-internal-admins` con la tool de búsqueda/listado de canales disponible (ej: `mcp__SlackMCP__list_channels`, `mcp__slack__list_channels` u otra variante). Guardar el `channel_id` para reusar en tickets subsiguientes — no hacer una búsqueda por ticket.

2. **Postear mensaje al canal** con la tool de posteo disponible (ej: `mcp__SlackMCP__post_message`, `mcp__slack__post_message` u otra variante):
   ```
   🔀 *Ticket redirigido desde SSHP*
   *Key:* SSHP-XXXXXX
   *Motivo:* Este tema depende de equipos de platsec/authz. El canal correcto para reportarlo es este.
   *Link:* https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX
   ```
   - No incluir `summary`, `description`, comentarios, adjuntos ni ningún campo libre controlado por reporter. Mensaje usa solo key validada, motivo fijo de regla y link construido desde key.
   - Si falla: registrar `✗ Slack` en el resultado de ese ticket. **No abortar** — continuar con el siguiente.

3. **Registrar en el log de auditoría** (append-only):
   ```bash
   printf '%s\n' '{"ts":"<ISO8601 UTC>","action":"slack-redirect","key":"<KEY>","rule":"R-DER-05","source":"<auto-assign|manual>","destination":"#help-authz-internal-admins","result":"<ok|failed>"}' >> "$SKILL_DIR/knowledge/audit-log-$(date -u +%Y).jsonl"
   ```

Si `SLACK_MCP_AVAILABLE = false`, omitir este paso completamente y mostrar los tickets en la tabla final como `MANUAL_REDIRECT` con la nota de cómo habilitar el MCP.

### 5. Mostrar tabla de resultados final

```
Resultados de derivación (N tickets procesados):

| Key           | Regla     | Destino                       | Nota interna | Transición | Watcher | Labels | KB  | Slack |
|---------------|-----------|-------------------------------|--------------|------------|---------|--------|-----|-------|
| SSHP-XXXXXX   | R-DER-10  | IAM Soporte                   | ✓            | ✓          | ✓ removido | ✓   | ✓   | —     |
| SSHP-YYYYYY   | R-DER-09  | IAM Soporte                   | ✓            | ✓          | — actor assignee | ✓ | ✓ | — |
| SSHP-ZZZZZZ   | —         | NO_DERIVA                     | —            | —          | — | — | — | — |
| SSHP-VVVVVV   | R-DER-05  | #help-authz-internal-admins   | —            | —          | — no aplica | — | — | ✓ |
| SSHP-WWWWWW   | R-DER-07  | IAM Soporte                   | ✓            | ✗ Bad Req  | — | — | — | — |

Resumen: N derivados ✓  |  M sin acción  |  S Slack enviados ✓  |  K manuales pendiente  |  E con errores parciales
```

Links de Jira al final para cada ticket derivado:
```
https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX
https://mercadolibre.atlassian.net/browse/SSHP-YYYYYY
```
