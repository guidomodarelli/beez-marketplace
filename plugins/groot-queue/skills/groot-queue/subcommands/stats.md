---
description: Muestra estadísticas agregadas de la cola de soporte (totales, sin asignar, riesgo SLA, edad, por categoría/urgencia/veredicto).
---

# /groot-queue:stats

Mostrar estadísticas agregadas de la cola.

## Procedimiento

1. Leer referencias:
   - `$SKILL_DIR/knowledge/config/batch-processing.md`
   - `$SKILL_DIR/knowledge/config/classification.md`
   - `$SKILL_DIR/knowledge/config/ticket-evidence.md`
   - `$SKILL_DIR/knowledge/config/kraken-user-data.md`
   - `$SKILL_DIR/knowledge/rules/triage-rules.md`
2. Obtener todos los tickets abiertos con JQL base paginado una sola vez y congelar snapshot de keys en orden estable.
3. Dividir snapshot en lotes consecutivos de hasta 25. Para cada lote, anunciar `Lote X/Y`, obtener detalles con concurrencia máxima de cuatro lecturas y aplicar gate de `ticket-evidence.md` con facts decisivos mínimos. Reutilizar evidencia por sujeto dentro del lote y respetar `max_users_per_batch`.
4. Clasificar cada ticket del lote (categoría + urgencia + triage) y acumular contadores globales. Si veredicto depende de evidencia indeterminada o presupuesto agotado, contar como `REVISAR_MANUAL`; no convertir reporte Jira en veredicto confirmado.
5. Después de agotar todos los lotes, calcular y mostrar estadísticas agregadas globales.

## Presentación

- Total de tickets abiertos
- Cantidad sin asignar
- Cantidad con riesgo SLA (urgencia >= 4)
- Edad promedio
- Tabla: tickets por categoría (con barra visual)
- Tabla: tickets por score de urgencia
- Tabla: tickets por veredicto de triage (DESCARTAR / DERIVAR / FIX_APLICADO / VALIDO_GROOT / REVISAR_MANUAL)
