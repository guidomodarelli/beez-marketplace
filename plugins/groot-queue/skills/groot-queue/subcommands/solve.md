---
description: Sugiere solución para un ticket SSHP basada en runbooks, casos previos y análisis del contexto.
argument-hint: SSHP-XXXXXX
---

# /groot-queue:solve

Analizar un ticket y sugerir una solución. Argumento: la key del ticket (`SSHP-XXXXXX`).

## Procedimiento

1. Leer las referencias:
   - `$SKILL_DIR/knowledge/classification.md`
   - `$SKILL_DIR/knowledge/triage-rules.md`
   - `$SKILL_DIR/knowledge/runbooks.md`
2. Obtener el ticket: `acli jira workitem view SSHP-XXXXXX`
3. Identificar la categoría del problema (Dimensión 1).
4. Buscar el runbook de esa categoría en `runbooks.md`.
5. Leer `$SKILL_DIR/knowledge/solutions/<categoria>/*.md` (ver mapeo de carpetas en `classification.md`) en busca de casos previos con señales similares.
6. Complementar con análisis propio basado en el contexto del ticket.

## Presentación

- **Diagnóstico probable**: qué está pasando
- **Pasos de resolución**: ordenados, concretos, con URLs si aplica
- **Casos similares**: links a archivos de `solutions/` si se encontraron
- **Escalación**: a quién escalar si no se resuelve
- **Confianza**: baja/media/alta

Siempre incluir link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`.
