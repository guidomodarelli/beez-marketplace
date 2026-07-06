---
ticket: SSHP-1407998
category: hierarchy-leader
summary: Un usuario externo aparecía como subordinado de sí mismo debido a una referencia circular en su lider directo configurado en Groot.
date: 2026-04-14
effectiveness: confirmed
verdict: VALIDO_GROOT
---

## Problema
Un usuario externo (`ext_*`) aparecía por debajo de sí mismo en la jerarquía de Groot, creando un ciclo infinito en la vista del árbol de equipo. El reporte indicaba que al consultar la estructura del equipo, el mismo usuario figuraba como su propio subordinado.

## Causa Raiz
Existía una referencia circular en el campo de lider directo del usuario: el sistema tenía configurado al propio usuario como lider de sí mismo. Esto generó una inconsistencia en la jerarquía que impedía la correcta representación del árbol de equipo.

## Solucion Aplicada
Se identificó y corrigió manualmente la inconsistencia en el campo de lider directo del usuario en Groot, asignando el lider correcto y rompiendo el ciclo de referencia circular.

## Tags
referencia-circular, jerarquia, lider-directo, groot
