---
description: Guarda la solución aplicada a un ticket SSHP en la knowledge base para mejorar futuros diagnósticos.
argument-hint: SSHP-XXXXXX <descripción>
---

# /groot-queue:save

Guardar la resolución real de un ticket en la knowledge base. Argumentos: la key del ticket (`SSHP-XXXXXX`) seguida de una descripción de la solución aplicada.

## Algoritmo

1. Leer la referencia de clasificación: `~/.claude/skills/groot-queue/knowledge/classification.md` (especialmente Dimensión 1 y mapeo de carpetas).
2. Obtener info del ticket:
   ```bash
   acli jira workitem view SSHP-XXXXXX
   ```
3. Detectar categoría usando la lógica de Dimensión 1.
4. Generar slug del archivo: `<ticket-key>-<primeras-3-palabras-del-summary>.md` (minúsculas, guiones)
   - Ejemplo: `SSHP-1407882-referencia-circular-lider.md`
5. Buscar si ya existe un archivo para ese ticket en `~/.claude/skills/groot-queue/knowledge/solutions/<categoria>/`:
   - Leer los frontmatter `ticket:` de cada archivo `.md` de esa carpeta.
   - Si ya existe: mostrar `⚠️ Ya existe una solución para SSHP-XXXXXX en <path>. ¿Querés sobrescribir? (sí/no)`.
   - Si el usuario dice no: abortar.
6. Crear el archivo markdown en `~/.claude/skills/groot-queue/knowledge/solutions/<categoria>/`:

```markdown
---
ticket: SSHP-XXXXXX
category: <categoria-slug>
summary: <descripción provista por el usuario>
date: <fecha-actual-YYYY-MM-DD>
effectiveness: confirmed
---

## Problema
<summary del ticket en Jira>

## Solución Aplicada
<descripción provista por el usuario>

## Señales para identificar este patrón
<inferir del summary y descripción del ticket — 2-4 señales concretas>

## Tags
<keywords relevantes del ticket, separados por coma>
```

7. Mostrar confirmación:
```
✅ Solución guardada en:
   ~/.claude/skills/groot-queue/knowledge/solutions/<categoria>/<slug>.md

Categoría: <Nombre de categoría>
Fecha: <YYYY-MM-DD>
```

El mapeo de categorías a carpetas vive en `classification.md`.
