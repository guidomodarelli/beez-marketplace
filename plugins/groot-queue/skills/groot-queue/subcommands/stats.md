---
description: Muestra estadísticas agregadas de la cola de soporte (totales, sin asignar, riesgo SLA, edad, por categoría/urgencia/veredicto).
---

# /groot-queue:stats

Mostrar estadísticas agregadas de la cola.

## Procedimiento

1. Leer referencias:
   - `$SKILL_DIR/knowledge/config/classification.md`
   - `$SKILL_DIR/knowledge/config/ticket-evidence.md`
   - `$SKILL_DIR/knowledge/config/kraken-user-data.md`
   - `$SKILL_DIR/knowledge/rules/triage-rules.md`
2. Obtener todos los tickets abiertos (JQL base).
3. Para cada ticket, aplicar gate de `ticket-evidence.md` y verificar autónomamente facts decisivos mínimos mediante `kraken-user-data.md`. Reutilizar evidencia por sujeto y respetar presupuesto de usuarios.
4. Clasificar cada ticket (categoría + urgencia + triage). Si veredicto depende de evidencia indeterminada o presupuesto agotado, contar como `REVISAR_MANUAL`; no convertir reporte Jira en veredicto confirmado.

## Presentación

- Total de tickets abiertos
- Cantidad sin asignar
- Cantidad con riesgo SLA (urgencia >= 4)
- Edad promedio
- Tabla: tickets por categoría (con barra visual)
- Tabla: tickets por score de urgencia
- Tabla: tickets por veredicto de triage (DESCARTAR / DERIVAR / FIX_APLICADO / VALIDO_GROOT / REVISAR_MANUAL)
