---
description: Clasifica y agrupa los tickets abiertos por tipo de problema y urgencia.
---

# /groot-queue:classify

Clasificar tickets abiertos por categoría + urgencia y mostrar acciones de triage recomendadas.

## Procedimiento

1. Leer la lógica de clasificación y triage desde `~/.claude/skills/groot-queue/knowledge/classification.md` y `~/.claude/skills/groot-queue/knowledge/triage-rules.md`.
2. Ejecutar el JQL base (ver `classification.md`).
3. Para cada ticket, aplicar el triage de veredicto y luego clasificar en las dos dimensiones (tipo de problema + urgencia).

## Presentación

### 1. Sección "🚨 Acciones de triage recomendadas"

Listar los matches de `triage-rules.md` con el formato definido en ese archivo (regla matcheada, ticket, acción sugerida).

### 2. Tickets agrupados por categoría

Mostrar tickets agrupados por categoría, ordenados por urgencia descendente dentro de cada grupo:

```
### Jerarquía/Líder (5 tickets)
| Key | Summary | Urgencia | Edad | Assignee |

### Warehouse/Site (3 tickets)
| Key | Summary | Urgencia | Edad | Assignee |
...
```

Indicadores de urgencia:
- 1-2: `🟢`
- 3: `🟡`
- 4-5: `🔴`

Siempre incluir link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`.
