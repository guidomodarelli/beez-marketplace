---
description: Lista todos los incidentes abiertos de la cola [Core] - Groot (SSHP) con veredicto de triage.
---

# /groot-queue:list

Listar todos los incidentes abiertos de la cola con su veredicto de triage.

## Procedimiento

1. Leer la lógica de clasificación y triage desde `$SKILL_DIR/knowledge/classification.md` y `$SKILL_DIR/knowledge/triage-rules.md`.
2. Ejecutar el JQL base (ver `classification.md`).
3. Para cada ticket, aplicar el algoritmo de triage de `triage-rules.md` y asignar veredicto.
4. Mostrar tabla markdown:

```
| # | Key | Summary | Status | Priority | Assignee | Edad | Triage |
```

La columna `Triage` usa los indicadores de `triage-rules.md`: `⛔ DESCARTAR`, `➡️ DERIVAR→<Equipo>`, `✅ FIX_APLICADO`, `🟢 VALIDO_GROOT`, `❓ REVISAR_MANUAL`.

Siempre incluir link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`.
