---
ticket: SSHP-1404662
category: hierarchy-leader
summary: 8 usuarios del WMS en el site MXCD09 quedaron con ellos mismos como líder directo. Se corrigieron sus líderes alineándolos con SSFF.
date: 2026-04-04
effectiveness: confirmed
verdict: VALIDO_GROOT
---

## Problema
8 usuarios del sistema WMS en el site MXCD09 presentaban una inconsistencia crítica: cada uno de ellos figuraba como su propio lider directo en Groot. Esto impedía la correcta visualización de jerarquías y el funcionamiento de flujos que dependen de la relación lider-subordinado.

## Causa Raiz
No se identificó la causa raíz exacta del problema. Se presume que un proceso de carga o sincronización asignó erróneamente el campo de lider directo con el mismo LDAP del usuario afectado.

## Solucion Aplicada
Se corrigieron manualmente los líderes de los 8 usuarios afectados en Groot, alineándolos con sus líderes correspondientes según la información registrada en SSFF (SuccessFactors), que es la fuente de verdad para la jerarquía organizacional.

## Señales para identificar este patron

- ES: "usuario aparece como su propio líder", "líder directo es él mismo", "usuarios WMS con self-leader", "se ven como supervisores de sí mismos", "ciclo en lider directo".
- PT: "usuário aparece como seu próprio líder", "líder direto é ele mesmo", "usuários WMS com self-leader", "aparecem como supervisores de si mesmos", "ciclo no líder direto".
- EN: "user appears as their own leader", "direct leader is themselves", "WMS users with self-leader", "showing as supervisor of themselves", "cycle in direct leader".
- Patrón bulk: múltiples usuarios del mismo site o warehouse afectados simultáneamente.
- La corrección requiere alinear con SSFF (SuccessFactors) como fuente de verdad.

## Tags
self-leader, wms, mxcd09, correccion-masiva, ssff, jerarquia, 8-usuarios
