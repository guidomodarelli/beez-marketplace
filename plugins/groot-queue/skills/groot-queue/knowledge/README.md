# Knowledge Base — groot-queue

Base de conocimiento **única** del equipo de soporte Groot. La skill `groot-queue` (`~/.claude/skills/groot-queue/SKILL.md`) lee desde acá: reglas de triage, runbooks por categoría, soluciones concretas y (a futuro) documentación de APIs.

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

solutions/           Casos concretos resueltos, agrupados por categoría:
  hierarchy-leader/
  warehouse-assignment/
  role-permission/
  user-visibility/
  attribute-modification/
  labor-share/
  cad-profile/
  groot-ui-error/
  link-unlink-account/
  queue-management/   Casos de derivación incorrecta, descartes y gestión de cola.

apis/                Documentación de endpoints del ecosistema Groot.
                     (Todavía vacío — completar con specs cuando aparezca
                     necesidad.)
```

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
