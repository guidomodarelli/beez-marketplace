---
description: Muestra estadísticas agregadas de la cola de soporte (totales, sin asignar, riesgo SLA, edad, por categoría/urgencia/veredicto).
---

# /groot-queue:stats

Mostrar estadísticas agregadas de la cola.

## Procedimiento

1. Leer las referencias:
   - `$SKILL_DIR/knowledge/classification.md`
   - `$SKILL_DIR/knowledge/triage-rules.md`
2. Obtener todos los tickets abiertos (JQL base).
3. Clasificar cada uno (categoría + urgencia + triage).

## Presentación

- Total de tickets abiertos
- Cantidad sin asignar
- Cantidad con riesgo SLA (urgencia >= 4)
- Edad promedio
- Tabla: tickets por categoría (con barra visual)
- Tabla: tickets por score de urgencia
- Tabla: tickets por veredicto de triage (DESCARTAR / DERIVAR / FIX_APLICADO / VALIDO_GROOT / REVISAR_MANUAL)
