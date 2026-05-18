---
ticket: SSHP-1401302
category: cad-profile
summary: Be a Rep aprobado pero la "bolha" (burbuja/notificación en el sistema) no subió. Mismo bug del deploy 30/03 en el componente snapshot.
date: 2026-04-04
effectiveness: confirmed
---

## Problema
Un usuario tenía una solicitud de "Be a Rep" (CAD) aprobada, pero la "bolha" (elemento visual o notificación en el sistema que confirma la activación) no subió, indicando que el proceso no se completó correctamente a pesar de la aprobación.

## Causa Raiz
Mismo bug del deploy 30/03 que afectó el componente snapshot. Al no ejecutarse correctamente el snapshot, los cambios aprobados no se persistían en el sistema, lo que impedía que la "bolha" apareciera como confirmación de la activación.

## Solucion Aplicada
Se aplicó el fix en el componente snapshot, resolviendo el bug. Tras la corrección, la bolha subió correctamente y el "Be a Rep" quedó activo para el usuario afectado.

## Tags
be-a-rep, cad, bolha, snapshot, deploy-bug, aprobacion
