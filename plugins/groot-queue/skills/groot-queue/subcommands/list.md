---
description: Lista todos los incidentes abiertos de la cola [Core] - Groot (SSHP) con veredicto de triage.
---

# /groot-queue:list

Listar todos los incidentes abiertos de la cola con su veredicto de triage.

## Procedimiento

1. Leer lógica desde `$SKILL_DIR/knowledge/config/batch-processing.md`, `$SKILL_DIR/knowledge/config/classification.md`, `$SKILL_DIR/knowledge/config/ticket-evidence.md`, `$SKILL_DIR/knowledge/config/kraken-user-data.md` y `$SKILL_DIR/knowledge/rules/triage-rules.md`.
2. Ejecutar JQL base paginado (ver `classification.md`) una sola vez y congelar snapshot completo de keys en orden estable.
3. Dividir snapshot en lotes consecutivos de hasta 25 tickets según `batch-processing.md`. Anunciar `Lote X/Y`; obtener detalles con concurrencia máxima de cuatro lecturas simultáneas.
4. Para cada ticket del lote activo, aplicar gate de `ticket-evidence.md`; cuando corresponda, consultar facts mínimos mediante `kraken-user-data.md` y reutilizar resultados por sujeto dentro del lote.
5. Aplicar algoritmo canónico first-match de `triage-rules.md` con evidencia normalizada y acumular veredicto. Verificación decisiva indeterminada produce `REVISAR_MANUAL`; no inferir ausencia o compatibilidad desde error.
6. Después de agotar todos los lotes, mostrar tabla markdown global:

```
| # | Key | Summary | Status | Priority | Assignee | Edad | Triage |
```

La columna `Triage` usa los indicadores de `triage-rules.md`: `⛔ DESCARTAR`, `➡️ DERIVAR→<Equipo>`, `✅ FIX_APLICADO`, `🟢 VALIDO_GROOT`, `❓ REVISAR_MANUAL`.

Siempre incluir link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`.
