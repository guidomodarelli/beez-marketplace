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
   - `$SKILL_DIR/knowledge/config/labor-share-data.md`
   - `$SKILL_DIR/knowledge/rules/triage-rules.md`
   - `$SKILL_DIR/knowledge/rules/runbooks.md`
2. Obtener el ticket: `acli jira workitem view SSHP-XXXXXX` y aplicar `$SKILL_DIR/knowledge/config/untrusted-content.md`.
3. Aplicar primero `triage-rules.md` § **Política transversal — configuración de usuarios**. Solicitudes para comparar personas, determinar configuración objetivo o modificar/aplicar roles, permisos o atributos se resuelven por texto sin consultar Kraken. En demás casos, aplicar `ticket-evidence.md` y verificar solo facts mínimos que cambien ownership o diagnóstico sistémico sin elegir configuración. Para Labour Share, extraer candidatos después de aislar contenido Jira: un único `labor_share_id` explícito para `execution` o un único `facility_type` permitido para `processes`; cero/múltiples candidatos no disparan red. Conservar evidencia sanitizada para sugerencia y delegación.
4. Aplicar triage canónico con esa evidencia. Si Jira contradice fuente autorizada, reevaluar conclusión. Si verificación decisiva queda indeterminada, usar `REVISAR_MANUAL` y no presentar inferencias como hechos ni afirmar configuración correcta/incorrecta. Assignments `SUCCESS`/`FAIL` no representan estado global y `return_date` solo representa retorno programado.
5. Clasificar en Dimensión 1 (tipo) y Dimensión 2 (urgencia); datos Kraken no modifican urgencia.
6. Buscar runbook de categoría en `runbooks.md`. Al aplicar lógica de `solve`, pasar política transversal y evidencia Kraken/Labour Share ya obtenida, no repetir consultas y filtrar cualquier recomendación de comparar, determinar o aplicar configuración.

## Presentación

1. **Info del ticket**: key, summary, status, priority, assignee, URL (`https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`)
2. **Veredicto de triage**: aplicar el algoritmo y citar la regla matcheada si corresponde
3. **Clasificación**: categoría asignada con justificación
4. **Urgencia**: score con desglose de factores
5. **Descripción**: texto completo
6. **Sugerencia de solución**: aplicar la lógica de `/groot-queue:solve`
