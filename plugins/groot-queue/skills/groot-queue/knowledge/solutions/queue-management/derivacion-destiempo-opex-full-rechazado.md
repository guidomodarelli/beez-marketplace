---
ticket: SSHP-generico
category: queue-management
summary: Tickets derivados a destiempo desde Opex Full / SMO con más de 15 días de aging al llegar a la cola Groot (post 28-oct-2025). Se descartan porque llegaron fuera de la ventana de soporte.
date: 2025-11-03
effectiveness: confirmed
rule: R-DESC-01
verdict: DESCARTAR
---

## Problema
A partir del 28 de octubre de 2025, Opex Full dejó de funcionar como primer nivel de revisión. Como consecuencia, más de 40 tickets fueron redirigidos a la cola Groot con agings superiores a 15–20 días, fuera de toda ventana de soporte viable.

## Causa Raiz
El desarme de los agentes de Opex Full generó que SMO redirigiera tickets acumulados con aging elevado, sin que Groot pudiera actuar sobre ellos de forma útil.

## Solucion Aplicada
Los tickets se descartaron como `Won't Do` / `Cancelled`.

**Comentario sugerido al reportero:**
> "Hola lamentamos el tiempo de respuesta de este ticket sin embargo el mismo fue derivado a nuestra cola a destiempo (28 de oct) en caso de seguir necesitando soporte volver a abrir el ticket con las evidencias del caso."

## Señales para identificar este patrón
- El ticket proviene de Opex Full o SMO y fue derivado a Groot.
- El aging original es > 15 días al momento de la derivación.
- La fecha de derivación es posterior al 28 de octubre de 2025.

## Tags
opex-full, smo, destiempo, aging, descartar, derivacion-incorrecta, won't-do, primer-nivel
