---
ticket: SSHP-1417376
category: labor-share
summary: Error al crear Labour Share en MXTR10 para todos los usuarios del TL vespinosa. La causa fue que el usuario tiene posición "analyst", que no tiene permiso para crear Labour Share.
date: 2026-04-17
effectiveness: confirmed
verdict: DESCARTAR
---

## Problema
El usuario vespinosa reportó que no podía crear Labour Share para ninguno de sus colaboradores en el site MXTR10. El error afectaba a todas las operaciones de Labour Share que intentaba realizar.

## Causa Raiz
El usuario vespinosa tiene configurada la posición "analyst" en su perfil. Solo los usuarios con posición team_lead o supervisor tienen permisos para crear Labour Share. Al tener una posición diferente, el sistema rechaza la operación.

## Solucion Aplicada
El ticket fue rechazado dado que el error es por diseño del sistema: los usuarios con posición "analyst" no tienen habilitada la funcionalidad de crear Labour Share. Se orientó al solicitante sobre los requisitos de posición necesarios para usar esta funcionalidad.

## Tags
labour-share, posicion, analyst, team-lead, supervisor, permisos, mxtr10, vespinosa, rechazado
