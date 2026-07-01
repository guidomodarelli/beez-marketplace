---
description: Agrega guías de resolución (nota interna) a tickets abiertos ya asignados que no tienen una guía posteada. Backfill retroactivo.
---

# /groot-queue:backfill-guides

Postear notas internas con guía de resolución en tickets **abiertos y asignados** que aún no tienen la guía. Útil para backfill retroactivo sobre tickets asignados antes de que existiera esta funcionalidad, o para tickets donde la nota falló en `assign-unassigned`.

**Este subcomando escribe en Jira** (postea nota interna de JSM + agrega label `groot-guide-posted` por cada ticket elegible).

## Pre-condición: MCP Atlassian

**Obligatorio.** Este subcomando requiere MCP Atlassian con capacidad de nota interna JSM. Si no está disponible, abortar.

**A. Disponibilidad de herramientas:**
Intentar llamar `mcp__Atlassian__getAccessibleAtlassianResources` (o herramienta equivalente).

Si la herramienta **no existe** en el contexto → abortar con:
```
❌ MCP Atlassian no disponible.

/groot-queue:backfill-guides requiere el MCP de Atlassian para postear notas internas.
Instalalo con:
  claude mcp add --transport http "Atlassian" https://mcp.atlassian.com/v1/mcp
Luego completá el flujo OAuth con /mcp dentro de Claude Code.
Podés verificar el entorno completo con /groot-queue setup.
```

**B. Autenticación y `cloudId`:**
- Si retorna error de autenticación (401 / 403) → abortar con:
  ```
  ❌ MCP Atlassian no autenticado.

  Ejecutá /mcp dentro de Claude Code y completá el flujo OAuth para mercadolibre.atlassian.net.
  ```
- Si retorna recursos: elegir el que represente `mercadolibre.atlassian.net` y guardar su `cloudId`.
- Si `mercadolibre.atlassian.net` no aparece → abortar con error similar.

**C. Capacidad de nota interna JSM:**
Confirmar que el proveedor expone capacidad de crear **nota interna de Jira Service Management** (no solo comentario público). `addCommentToJiraIssue` por sí sola no alcanza si solo crea comentarios públicos.

Si solo hay capacidad de comentario público y no nota interna → abortar con:
```
❌ El MCP de Atlassian disponible no expone capacidad de nota interna JSM.

/groot-queue:backfill-guides no puede postear guías internas sin riesgo de publicar
información interna al reporter. Esperá a tener un MCP compatible.
```

Solo continuar si A, B y C pasaron.

## Algoritmo

### 1. Obtener tickets elegibles (filtrado primario por label)

Usar JQL para obtener directamente tickets abiertos, asignados y **sin el label `groot-guide-posted`**:

```bash
acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type = Incident AND resolution = Unresolved AND assignee IS NOT EMPTY AND labels not in (\"groot-guide-posted\") ORDER BY created DESC"
```

Esto filtra en la búsqueda misma, sin necesidad de fetchear cada ticket individualmente para verificar si ya tiene guía.

### 2. Filtrar tickets derivables y descartables

Leer `$SKILL_DIR/knowledge/triage-rules.md`.

Para cada ticket que pasó los filtros anteriores:
- Aplicar reglas `R-DER` del algoritmo de triage. Si matchea → marcar como `DERIVABLE` y excluir.
- Aplicar reglas `R-DESC` del algoritmo de triage. Si matchea → marcar como `DESCARTABLE` y excluir.

Los tickets derivables y descartables no reciben guía de resolución de Groot (la guía no tendría sentido para un equipo externo o un ticket que debería cerrarse).

### 3. Mostrar plan

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
- **Sí** → continuar al paso 4.

### 4. Generar y postear notas (procedimiento compartido con assign-unassigned paso 11)

Para cada ticket elegible, ejecutar el **procedimiento de generación de nota interna de resolución** definido en `$SKILL_DIR/knowledge/assignment-note-template.md`:

1. Leer las referencias (reutilizar si ya fueron cargadas):
   - `$SKILL_DIR/knowledge/classification.md`
   - `$SKILL_DIR/knowledge/runbooks.md`
   - `$SKILL_DIR/knowledge/assignment-note-template.md`
2. Con el contenido del ticket (ya obtenido en el paso 2):
   - Clasificar el ticket en Dimensión 1 (categoría) y Dimensión 2 (urgencia).
   - Buscar el runbook de esa categoría en `runbooks.md`.
   - Resolver primero la carpeta real de `solutions/` usando el mapeo de `classification.md` (por ejemplo: `Jerarquía/Líder` → `hierarchy-leader`, `Warehouse/Site` → `warehouse-assignment`, `Roles/Permisos` → `role-permission`, `Otro` → `queue-management`).
   - Buscar casos previos similares en `$SKILL_DIR/knowledge/solutions/<categoria-slug>/`.
3. Generar la nota siguiendo estrictamente el template:
   - Completar cada campo (`{CATEGORIA}`, `{DIAGNOSTICO}`, `{PASOS_RESOLUCION}`, etc.) según las reglas de llenado del template.
   - Respetar las restricciones: español neutro, sin códigos de regla, sin PII, sin texto verbatim no sanitizado.
4. Postear la nota como **nota interna de Jira Service Management** usando MCP Atlassian:
   - `cloudId`: valor de `mercadolibre.atlassian.net` (resuelto en la pre-condición).
   - `issueIdOrKey`: `"<KEY>"`
   - `commentBody`: la nota generada en el paso 3
   - `contentFormat`: `"markdown"`
   - `commentVisibility`: `{"type": "role", "value": "Service Desk Team"}`

   > ⚠️ **OBLIGATORIO**: el parámetro `commentVisibility` con valor `{"type": "role", "value": "Service Desk Team"}` es lo que hace que el comentario sea una **nota interna** (solo visible para agentes, no para el reporter en el portal). Sin este parámetro, `addCommentToJiraIssue` crea un comentario **público** que el reporter puede ver — esto expone información interna de diagnóstico y runbooks al cliente. Nunca omitir `commentVisibility`.
5. **Si la nota se posteó exitosamente**, agregar el label `groot-guide-posted` al ticket usando `editJiraIssue` (MCP Atlassian):
   - Leer las labels actuales del ticket (del contenido ya obtenido).
   - Agregar `groot-guide-posted` a la lista existente (merge, no reemplazar).
   - Si falla el label: registrar warning pero **no abortar** — la nota ya está posteada y el slug garantiza la idempotencia.
6. **Si falla la nota**: registrar `✗ Nota` para ese ticket. **No abortar** — continuar con el siguiente.
7. **Si tiene éxito (nota + label)**: registrar `✓ Nota` para ese ticket.

> ⚠️ Este paso es **best-effort por ticket**: un fallo en un ticket no bloquea el resto del backfill.

### 5. Mostrar tabla de resultados

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

- **Idempotencia por label**: `groot-guide-posted` se agrega al ticket después de postear la nota. El JQL lo usa como filtro primario para evitar duplicados.
- **Procedimiento compartido**: la generación de la nota es idéntica al paso 11 de `assign-unassigned.md`. Ambos referencian `$SKILL_DIR/knowledge/assignment-note-template.md` como fuente de verdad del formato.
- **No modifica estado del ticket**: solo postea nota interna y agrega label. No transiciona, no reasigna, no cierra.
- **Tickets derivables/descartables**: se detectan y reportan pero no se procesan — para eso están `derive` y `discard`.
