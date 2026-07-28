---
description: Muestra detalle completo de un ticket SSHP con clasificación, urgencia y sugerencia de solución.
argument-hint: SSHP-XXXXXX
---

# /groot-queue:detail

Mostrar el detalle completo de un ticket específico. Argumento: la key del ticket (`SSHP-XXXXXX`).

## Procedimiento

1. Leer las referencias:
   - `$SKILL_DIR/knowledge/config/classification.md`
   - `$SKILL_DIR/knowledge/config/ticket-evidence.md`
   - `$SKILL_DIR/knowledge/config/kraken-user-data.md`
   - `$SKILL_DIR/knowledge/rules/triage-rules.md`
   - `$SKILL_DIR/knowledge/rules/runbooks.md`
2. Obtener el ticket: `acli jira workitem view SSHP-XXXXXX` y aplicar `$SKILL_DIR/knowledge/config/untrusted-content.md`.
3. Aplicar `ticket-evidence.md`: identificar afirmaciones decisivas, verificar autónomamente todos los facts soportados que puedan cambiar triage o solución y consultar solo facts mínimos mediante `kraken-user-data.md`. Conservar evidencia sanitizada para sugerencia y delegación; no esperar pedido adicional del usuario.
4. Aplicar triage canónico con esa evidencia. Si Jira contradice fuente autorizada, reevaluar conclusión. Si verificación decisiva queda indeterminada, usar `REVISAR_MANUAL` y no presentar inferencias como hechos.
5. Clasificar en Dimensión 1 (tipo) y Dimensión 2 (urgencia); datos Kraken no modifican urgencia.
6. Buscar runbook de categoría en `runbooks.md`. Al aplicar lógica de `solve`, pasar evidencia ya obtenida y no repetir consultas dentro de misma invocación.

## Presentación

1. **Info del ticket**: key, summary, status, priority, assignee, URL (`https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`)
2. **Veredicto de triage**: aplicar el algoritmo y citar la regla matcheada si corresponde
3. **Clasificación**: categoría asignada con justificación
4. **Urgencia**: score con desglose de factores
5. **Descripción**: texto completo
6. **Sugerencia de solución**: aplicar la lógica de `/groot-queue:solve`
