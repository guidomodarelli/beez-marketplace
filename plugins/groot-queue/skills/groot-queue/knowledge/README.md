# Knowledge Base — groot-queue

Base de conocimiento **única** del equipo de soporte Groot. La skill `groot-queue` (`$SKILL_DIR/SKILL.md`) lee desde acá: reglas de triage, runbooks por categoría, soluciones concretas y (a futuro) documentación de APIs.

La idea es que todo el conocimiento del día a día del equipo crezca en este directorio, sin tocar la skill.

## Estructura

```
triage-rules.md      Reglas transversales R-DESC-XX / R-DER-XX / R-FIX-XX.
                     Algoritmo de triage para los veredictos (DESCARTAR,
                     DERIVAR, FIX_APLICADO, VALIDO_GROOT, REVISAR_MANUAL).
                     Se consulta en /groot-queue list y /groot-queue classify.

runbooks.md          Runbook procedural por categoría de problema
                     (Jerarquía, Warehouse, Roles, Atributos, CAD/Perfil, etc.)
                     Se consulta en /groot-queue solve.

assignment-note-template.md
                     Template estándar para la nota interna de resolución que
                     se postea en cada ticket al asignarlo con
                     /groot-queue assign-unassigned. Define estructura,
                     reglas de llenado y restricciones.

solutions/           Casos concretos resueltos, agrupados por categoría:
  hierarchy-leader/        ← Jerarquía/Líder
  warehouse-assignment/    ← Warehouse/Site
  role-permission/         ← Roles/Permisos
  user-visibility/         ← Visibilidad Usuario
  attribute-modification/  ← Atributos
  labor-share/             ← Labour Share
  cad-profile/             ← CAD/Perfil
  groot-ui-error/          ← Error UI Groot
  link-unlink-account/     ← Vincular/Desvincular
  queue-management/        ← Descartes, derivaciones incorrectas y gestión de cola.

audit-log-<YYYY>.jsonl  Log de auditoría append-only (una línea JSON por evento),
                     **un archivo por año** (audit-log-2026.jsonl,
                     audit-log-2027.jsonl, ...) para que no crezca
                     indefinidamente. Registra cada derivación y descarte
                     ejecutados por /groot-queue derive y /groot-queue discard,
                     distinguiendo source "auto-assign" (disparado por
                     /groot-queue assign-unassigned) de "manual". Estado
                     per-usuario, ignorado por git.
```

## Auditar derivaciones/descartes automáticos

Los archivos `audit-log-<YYYY>.jsonl` (uno por año) dejan un evento por cada ticket
derivado o descartado, tanto en el flujo automático de `/groot-queue assign-unassigned`
como en los `/groot-queue derive` / `/groot-queue discard` manuales. Cada línea tiene
la forma:

```json
{"ts":"2026-06-01T14:30:00Z","action":"derive","key":"SSHP-123","rule":"R-DER-10","source":"auto-assign","destination":"IAM Soporte","result":"ok"}
{"ts":"2026-06-01T14:31:10Z","action":"discard","key":"SSHP-456","rule":"R-DESC-04","source":"auto-assign","result":"partial-error"}
```

Campos: `ts` (ISO8601 UTC), `action` (`derive`/`discard`), `key`, `rule`,
`source` (`auto-assign`/`manual`), `destination` (solo derive), `result`
(`ok`/`partial-error`/`failed`/`manual`).

Ejemplos de consulta para auditoría:

```bash
KB="$SKILL_DIR/knowledge"

# Auditar un año puntual
grep '"source":"auto-assign"' "$KB"/audit-log-2026.jsonl | jq .

# Auditar todos los años a la vez
cat "$KB"/audit-log-*.jsonl | grep '"result":"partial-error"' | jq .   # los que fallaron a medias

# Conteo por regla (todos los años)
jq -r '.rule' "$KB"/audit-log-*.jsonl | sort | uniq -c
```

## Aliases de campos Jira

Los subcomandos deben usar aliases descriptivos cuando referencian campos internos
de Jira. El field id real se mantiene acá para que la lógica de la skill sea
legible y haya un único lugar donde consultar qué representa cada campo.

| Alias | Field id real | Representa | Uso |
|-------|---------------|------------|-----|
| `DERIVATION_DESTINATION_SQUAD_FIELD` | `customfield_13781` | Squad/equipo destino seleccionado en la transición "Derivar a otro equipo" de SSHP. | `/groot-queue derive`, al completar `fields` para la transición `121`. |

Al construir el payload final para Jira/MCP, expandir el alias al field id real.
No enviar el alias literal como nombre de campo.

## Cómo agregar una solución concreta

1. Ejecutar `/groot-queue save SSHP-XXXXX` (la skill genera el archivo automáticamente), o
2. Crear manualmente un `.md` en la carpeta de categoría correspondiente siguiendo este formato:

```markdown
---
ticket: SSHP-XXXXXX
category: hierarchy-leader
summary: Descripción breve
date: YYYY-MM-DD
effectiveness: confirmed | unconfirmed
---

## Problema
## Causa Raíz
## Solución Aplicada
## Señales para identificar este patrón  (opcional)
## API Calls Involucrados              (opcional)
## Tags
```

## Cómo agregar una regla de triage transversal

Editar `triage-rules.md`. Nueva numeración según corresponda:
- `R-DESC-XX` para descartes
- `R-DER-XX` para derivaciones a otro equipo
- `R-FIX-XX` para casos con fix ya aplicado en producción

Incluir siempre: señales, razón, acción, comentario sugerido y **fuente** (autor + ticket + fecha + link a `solutions/`).

Luego, actualizar el bloque **Algoritmo de triage** de ese mismo archivo para que la regla nueva se evalúe en el orden correcto.

## Cómo agregar/modificar un runbook

Editar `runbooks.md`. Si aparece una categoría nueva, agregar su sección. Si hay un paso nuevo conocido (ej. una validación previa), insertarlo respetando el orden.

Cuando un runbook tenga un shortcut por regla de triage (como `R-DESC-03` en CAD/Perfil), referenciar explícitamente `triage-rules.md` para mantener la trazabilidad.

## Cómo buscar soluciones

```
/groot-queue search <término>
```

Busca por keyword o tag en todos los archivos de `solutions/`.
