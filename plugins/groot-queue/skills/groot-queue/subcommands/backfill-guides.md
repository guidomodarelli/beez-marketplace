---
description: Agrega guías de resolución (nota interna) a tickets abiertos ya asignados que no tienen una guía posteada. Backfill retroactivo.
---

# /groot-queue:backfill-guides

Postear notas internas con guía de resolución en tickets **abiertos y asignados** que aún no tienen la guía. Útil para backfill retroactivo sobre tickets asignados antes de que existiera esta funcionalidad, o para tickets donde la nota falló en `assign-unassigned`.

**Este subcomando escribe en Jira** (postea nota interna de JSM + agrega label `groot-guide-posted` por cada ticket elegible).

## Pre-condición: MCP Atlassian

**Obligatorio.** Este subcomando requiere MCP Atlassian con capacidad de nota interna JSM. Si no está disponible, abortar.

Aplicar **modo ABORTAR** (pasos A + B + C) de `$SKILL_DIR/knowledge/config/atlassian-mcp.md`. Usar `/groot-queue:backfill-guides` como nombre del subcomando en los mensajes de error. El `cloudId` obtenido en B se reutiliza en el paso 5.

## Algoritmo

### 1. Obtener tickets elegibles (filtrado primario por label)

Usar JQL para obtener directamente tickets abiertos, asignados y **sin el label `groot-guide-posted`**. Mantener la misma definición de cola abierta compartida (`Incident` + `Service Request`):

```bash
JQL=$(cat <<'JQL'
project = SSHP AND <SQUAD_FIELD_JQL> = "Groot" AND type IN (Incident, "Service Request") AND resolution = Unresolved AND assignee IS NOT EMPTY AND (labels not in ("groot-guide-posted") OR labels is EMPTY) ORDER BY created DESC
JQL
)
acli jira workitem search --paginate --jql "$JQL"
```

> Expandir `<SQUAD_FIELD_JQL>` al field id real antes de ejecutar; la expansión está centralizada en `$SKILL_DIR/knowledge/config/jira-field-options.md` § `customfield_13781`.

Aplicar el contrato de paginación completa de `$SKILL_DIR/knowledge/config/classification.md`: el backfill debe descubrir todos los tickets elegibles, incluso los que estén fuera de la primera página. Esto filtra en la búsqueda misma, sin necesidad de fetchear cada ticket individualmente para verificar si ya tiene guía. La cláusula `OR labels is EMPTY` es necesaria porque en Jira `labels not in (...)` excluye tickets sin ningún label — justamente los que más necesitan backfill.

Leer y aplicar `$SKILL_DIR/knowledge/config/batch-processing.md`. Congelar keys retornadas por la búsqueda y dividirlas, sin reconsultar ni reordenar snapshot, en lotes consecutivos de hasta 25 tickets. Para cada lote activo, anunciar `Lote X/Y`, analizar sólo sus keys y completar los pasos 2 a 5 antes de continuar con lote siguiente.

### 2. Filtrar tickets con slug (fallback de idempotencia)

Para cada ticket del lote activo, obtener el contenido completo con concurrencia máxima de cuatro lecturas simultáneas:
```bash
TICKET_KEY=$(cat <<'VALUE'
<KEY>
VALUE
)
acli jira workitem view "$TICKET_KEY"
```

Verificar si el output contiene el slug de detección automática:
```
<!-- groot-auto-guide -->
```

**Regla de idempotencia por slug:** si un ticket contiene `<!-- groot-auto-guide -->` en sus comentarios/notas internas (el label no estaba, pero la nota sí fue posteada previamente), marcarlo como `YA_TIENE_GUIA` y excluirlo. Registrar reparación pendiente de `groot-guide-posted`, pero no escribir todavía: reparar label sólo después de confirmación del lote y revalidación inmediata.

> Este paso es un safety net para edge cases donde el label fue removido accidentalmente pero la nota existe. En el flujo normal, el JQL del paso 1 ya filtró los tickets con label.

### 3. Filtrar tickets derivables y descartables

Leer `$SKILL_DIR/knowledge/config/ticket-evidence.md`, `$SKILL_DIR/knowledge/config/kraken-user-data.md`, `$SKILL_DIR/knowledge/config/labor-share-data.md` y `$SKILL_DIR/knowledge/rules/triage-rules.md`.

Para cada ticket que pasó los filtros anteriores:
- Aplicar primero `triage-rules.md` § **Política transversal — configuración de usuarios**. Solicitudes para comparar personas, determinar configuración objetivo o modificar/aplicar roles, permisos o atributos se resuelven por texto sin consultar Kraken.
- Para demás tickets, aplicar gate de `ticket-evidence.md` y verificar solo facts mínimos que cambien ownership o diagnóstico sistémico sin elegir configuración. Para Labour Share, aplicar `labor-share-data.md` cuando ejecución o catálogo pueda cambiar triage o guía; reutilizar resultados durante lote.
- Aplicar algoritmo canónico first-match con evidencia normalizada. Un resultado Labour Share `indeterminate` decisivo no autoriza inferir ausencia, éxito, finalización ni retorno.
- Si matchea R-DER → marcar `DERIVABLE` y excluir.
- Si matchea R-DESC → marcar `DESCARTABLE` y excluir.
- Si una verificación obligatoria queda indeterminada → marcar `REVISAR_MANUAL` y excluir; no generar guía ni escribir Jira.

Los tickets derivables, descartables o de revisión manual no reciben guía de resolución de Groot.

### 4. Mostrar plan del lote

Antes de ejecutar escrituras del lote activo, mostrar resumen y acumular sus resultados para tabla global:

```
📋 Plan de backfill de guías — Lote X/Y — N tickets
═══════════════════════════════════════════════════════════════

Tickets elegibles (guía a postear): M
Tickets con guía existente (skip):  X
Tickets derivables (skip):          Y
Tickets descartables (skip):        Z

═══════════════════════════════════════════════════════════════
```

Si hay tickets derivables o descartables detectados, mostrar detalle:
```
ℹ️ Tickets derivables/descartables detectados (no se les agrega guía):
| Key          | Summary                  | Motivo     |
|--------------|--------------------------|------------|
| SSHP-XXXXX   | ...                      | R-DER-10   |
| SSHP-XXXXX   | ...                      | R-DESC-02  |

Podés derivarlos/descartarlos con /groot-queue derive o /groot-queue discard.
```

Si no hay tickets elegibles → mostrar:
```
✅ Todos los tickets abiertos y asignados ya tienen guía de resolución (o son derivables/descartables).
```
Y terminar.

Si hay tickets elegibles → pedir confirmación:
```
¿Querés postear o reparar guías en estos M tickets del lote X/Y? (sí / no)
```

- **No** → terminar con: "Backfill cancelado. No se procesarán lotes posteriores."
- **Sí** → continuar al paso 5 sólo para lote activo. `GROOT_QUEUE_AUTORUN=true` omite esta confirmación, pero no gates de evidencia, presupuestos ni revalidación.

### 5. Generar, revalidar y postear notas (procedimiento compartido con assign-unassigned paso 11)

Para cada ticket elegible del lote activo, revalidar inmediatamente que siga abierto, asignado y sin `groot-guide-posted` ni slug. Si otro actor cambió esas condiciones, registrar `SKIP_CAMBIO_CONCURRENTE` y no escribir. Para tickets `YA_TIENE_GUIA` con reparación pendiente, revalidar slug y mergear sólo `groot-guide-posted` después de confirmación. Para los demás tickets elegibles, ejecutar el **procedimiento de generación de nota interna de resolución** definido en `$SKILL_DIR/knowledge/templates/assignment-note-template.md`:

1. Leer las referencias (reutilizar si ya fueron cargadas):
   - `$SKILL_DIR/knowledge/config/classification.md`
   - `$SKILL_DIR/knowledge/config/ticket-evidence.md`
   - `$SKILL_DIR/knowledge/config/labor-share-data.md`
   - `$SKILL_DIR/knowledge/rules/runbooks.md`
   - `$SKILL_DIR/knowledge/templates/assignment-note-template.md`
2. Con contenido del ticket ya obtenido:
   - Reaplicar política transversal; si ticket resulta descartable, no generar nota ni escribir Jira.
   - Clasificar ticket en Dimensión 1 (categoría) y Dimensión 2 (urgencia).
   - Buscar runbook de categoría en `runbooks.md`.
   - Resolver carpeta real de `solutions/` usando mapeo de `classification.md`.
   - Buscar casos previos similares como antecedentes históricos, no como autorización para comparar o modificar configuración.
3. Generar nota siguiendo estrictamente template y filtrar cualquier paso que determine o aplique roles, permisos o atributos:
   - Si evidencia confirmada identifica una necesidad de configuración operativa, indicar únicamente que el responsable de gestión de usuarios de la operación debe gestionarla; no nombrar ni proponer la configuración.
   - Completar cada campo (`{CATEGORIA}`, `{DIAGNOSTICO}`, `{PASOS_RESOLUCION}`, etc.) según las reglas de llenado del template y evidence sanitizada ya obtenida; no repetir consultas.
   - Para Labour Share, usar solo procesamiento, conteos agregados, consistencia, fecha programada o catálogo mínimo. No afirmar lifecycle global, retorno ejecutado ni Team Leader.
   - Respetar las restricciones: español neutro, sin códigos de regla, sin PII, sin texto verbatim no sanitizado.
   - **Incluir siempre el slug `<!-- groot-auto-guide -->` como última línea del body.**
4. Postear la nota como **nota interna de Jira Service Management** usando MCP Atlassian:
   - `cloudId`: valor de `mercadolibre.atlassian.net` (resuelto en la pre-condición).
   - `issueIdOrKey`: `"<KEY>"`
   - `commentBody`: la nota generada en el paso 3
   - `contentFormat`: `"markdown"`
   - `commentVisibility`: `{"type": "role", "value": "Service Desk Team"}` — ver regla obligatoria en `$SKILL_DIR/knowledge/config/atlassian-mcp.md` § Uso de `commentVisibility`.
5. **Si la nota se posteó exitosamente**, agregar el label `groot-guide-posted` al ticket usando `editJiraIssue` (MCP Atlassian):
   - Leer las labels actuales del ticket (del contenido ya obtenido).
   - Agregar `groot-guide-posted` a la lista existente (merge, no reemplazar).
   - Si falla el label: registrar warning pero **no abortar** — la nota ya está posteada y el slug garantiza la idempotencia.
6. **Si falla la nota**: registrar `✗ Nota` para ese ticket. **No abortar** — continuar con el siguiente.
7. **Si tiene éxito (nota + label)**: registrar `✓ Nota` para ese ticket.

> ⚠️ Este paso es **best-effort por ticket**: un fallo en un ticket no bloquea el resto del backfill.

### 6. Mostrar tabla de resultados

Al finalizar cada lote, mostrar progreso `Lote X/Y` y resultados locales. Al completar todos los lotes, mostrar resultado global:

```
Backfill de guías completado (M tickets procesados en Y lotes):
| Key          | Assignee         | Categoría          | Nota    | Label   |
|--------------|------------------|--------------------|---------|---------|
| SSHP-XXXXX   | frgonzalez       | Jerarquía/Líder    | ✓ Nota  | ✓ Label |
| SSHP-XXXXX   | lpadularrosa     | Warehouse/Site     | ✓ Nota  | ✓ Label |
| SSHP-XXXXX   | jperez           | Roles/Permisos     | ✗ Nota  | — Skip  |

Resumen:
  ✓ Guías posteadas: N
  ✗ Errores: X
  — Skip (ya tenía / derivable / descartable): Y
```

## Notas de diseño

- **Idempotencia dual**: label `groot-guide-posted` como filtro primario (JQL), slug `<!-- groot-auto-guide -->` como fallback al leer el ticket. Ambos previenen duplicados.
- **No modificar la nota posteada**: contiene el slug de detección. Si se borra o modifica, la próxima corrida podría duplicar la guía (a menos que el label esté presente).
- **Procedimiento compartido**: la generación de la nota es idéntica al paso 11 de `assign-unassigned.md`. Ambos referencian `$SKILL_DIR/knowledge/templates/assignment-note-template.md` como fuente de verdad del formato.
- **No modifica estado del ticket**: solo postea nota interna y agrega label. No transiciona, no reasigna, no cierra.
- **Tickets derivables/descartables**: se detectan y reportan pero no se procesan — para eso están `derive` y `discard`.
