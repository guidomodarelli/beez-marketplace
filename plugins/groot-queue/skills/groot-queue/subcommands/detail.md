---
description: Muestra detalle completo de un ticket SSHP con clasificación, urgencia y sugerencia de solución.
argument-hint: SSHP-XXXXXX
---

# /groot-queue:detail

Mostrar el detalle completo de un ticket específico. Argumento: la key del ticket (`SSHP-XXXXXX`).

## Procedimiento

1. Leer las referencias:
   - `$SKILL_DIR/knowledge/classification.md`
   - `$SKILL_DIR/knowledge/triage-rules.md`
   - `$SKILL_DIR/knowledge/runbooks.md`
2. Obtener el ticket: `acli jira workitem view SSHP-XXXXXX`
3. Aplicar triage de veredicto sobre el ticket.
4. Clasificar en Dimensión 1 (tipo) y Dimensión 2 (urgencia).
5. Buscar el runbook de la categoría en `runbooks.md`.

## Presentación

1. **Info del ticket**: key, summary, status, priority, assignee, URL (`https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`)
2. **Veredicto de triage**: aplicar el algoritmo y citar la regla matcheada si corresponde
3. **Clasificación**: categoría asignada con justificación
4. **Urgencia**: score con desglose de factores
5. **Descripción**: texto completo
6. **Sugerencia de solución**: aplicar la lógica de `/groot-queue:solve`
