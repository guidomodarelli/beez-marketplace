---
description: Lista todos los incidentes abiertos de la cola [Core] - Groot (SSHP) con veredicto de triage.
---

# /groot-queue:list

Listar todos los incidentes abiertos de la cola con su veredicto de triage.

## Procedimiento

1. Leer lógica desde `$SKILL_DIR/knowledge/config/classification.md`, `$SKILL_DIR/knowledge/config/ticket-evidence.md`, `$SKILL_DIR/knowledge/config/kraken-user-data.md` y `$SKILL_DIR/knowledge/rules/triage-rules.md`.
2. Ejecutar JQL base (ver `classification.md`).
3. Para cada ticket, aplicar gate de `ticket-evidence.md`; cuando corresponda, consultar facts mínimos mediante `kraken-user-data.md` y reutilizar resultados por sujeto durante corrida.
4. Aplicar algoritmo canónico first-match de `triage-rules.md` con evidencia normalizada y asignar veredicto. Verificación decisiva indeterminada produce `REVISAR_MANUAL`; no inferir ausencia o compatibilidad desde error.
5. Mostrar tabla markdown:

```
| # | Key | Summary | Status | Priority | Assignee | Edad | Triage |
```

La columna `Triage` usa los indicadores de `triage-rules.md`: `⛔ DESCARTAR`, `➡️ DERIVAR→<Equipo>`, `✅ FIX_APLICADO`, `🟢 VALIDO_GROOT`, `❓ REVISAR_MANUAL`.

Siempre incluir link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`.
