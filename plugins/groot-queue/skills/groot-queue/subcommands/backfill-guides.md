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
acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type IN (Incident, \"Service Request\") AND resolution = Unresolved AND assignee IS NOT EMPTY AND (labels not in (\"groot-guide-posted\") OR labels is EMPTY) ORDER BY created DESC"
```

Esto filtra en la búsqueda misma, sin necesidad de fetchear cada ticket individualmente para verificar si ya tiene guía. La cláusula `OR labels is EMPTY` es necesaria porque en Jira `labels not in (...)` excluye tickets sin ningún label — justamente los que más necesitan backfill.

### 2. Filtrar tickets con slug (fallback de idempotencia)

Para cada ticket del paso 1, obtener el contenido completo:
```bash
acli jira workitem view <KEY>
```

Verificar si el output contiene el slug de detección automática:
```
<!-- groot-auto-guide -->
```

**Regla de idempotencia por slug:** si un ticket contiene `<!-- groot-auto-guide -->` en sus comentarios/notas internas (el label no estaba, pero la nota sí fue posteada previamente), marcarlo como `YA_TIENE_GUIA` y excluirlo. En este caso, **agregar el label `groot-guide-posted`** para corregir la inconsistencia (el label debería haber estado).

> Este paso es un safety net para edge cases donde el label fue removido accidentalmente pero la nota existe. En el flujo normal, el JQL del paso 1 ya filtró los tickets con label.

### 3. Filtrar tickets derivables y descartables

Leer `$SKILL_DIR/knowledge/rules/triage-rules.md`.

Para cada ticket que pasó los filtros anteriores:
- Aplicar reglas `R-DER` del algoritmo de triage. Si matchea → marcar como `DERIVABLE` y excluir.
- Aplicar reglas `R-DESC` del algoritmo de triage. Si matchea → marcar como `DESCARTABLE` y excluir.

Los tickets derivables y descartables no reciben guía de resolución de Groot (la guía no tendría sentido para un equipo externo o un ticket que debería cerrarse).

### 4. Mostrar plan

Antes de ejecutar, mostrar resumen:

```
📋 Plan de backfill de guías — N tickets
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
¿Querés postear la guía de resolución en estos M tickets? (sí / no)
```

- **No** → terminar con: "Backfill cancelado."
- **Sí** → continuar al paso 5.

### 5. Generar y postear notas (procedimiento compartido con assign-unassigned paso 11)

Para cada ticket elegible, ejecutar el **procedimiento de generación de nota interna de resolución** definido en `$SKILL_DIR/knowledge/templates/assignment-note-template.md`:

1. Leer las referencias (reutilizar si ya fueron cargadas):
   - `$SKILL_DIR/knowledge/config/classification.md`
   - `$SKILL_DIR/knowledge/rules/runbooks.md`
   - `$SKILL_DIR/knowledge/templates/assignment-note-template.md`
2. Con el contenido del ticket (ya obtenido en el paso 2):
   - Clasificar el ticket en Dimensión 1 (categoría) y Dimensión 2 (urgencia).
   - Buscar el runbook de esa categoría en `runbooks.md`.
   - Resolver primero la carpeta real de `solutions/` usando el mapeo de `classification.md` (por ejemplo: `Jerarquía/Líder` → `hierarchy-leader`, `Warehouse/Site` → `warehouse-assignment`, `Roles/Permisos` → `role-permission`, `Otro` → `queue-management`).
   - Buscar casos previos similares en `$SKILL_DIR/knowledge/solutions/<categoria-slug>/`.
3. Generar la nota siguiendo estrictamente el template:
   - Completar cada campo (`{CATEGORIA}`, `{DIAGNOSTICO}`, `{PASOS_RESOLUCION}`, etc.) según las reglas de llenado del template.
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

```
Backfill de guías completado (M tickets procesados):
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
