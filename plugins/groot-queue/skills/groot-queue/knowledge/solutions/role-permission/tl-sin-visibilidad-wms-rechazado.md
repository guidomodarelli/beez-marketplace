---
ticket: SSHP-1411424
category: role-permission
summary: TL sin visibilidad en WMS (error NO AUTORIZADO). Rechazado: le falta algún rol que debe gestionarse con el equipo de gestión de usuarios.
date: 2026-04-13
effectiveness: confirmed
---

## Problema
Un Team Leader (TL) reportó que al acceder a WMS (Warehouse Management System) recibía el error "NO AUTORIZADO". El usuario no podía visualizar ni gestionar su equipo o tareas en el sistema WMS.

## Causa Raiz
El error "NO AUTORIZADO" en WMS indica que al usuario le falta uno o más roles necesarios para acceder al sistema. La gestión y asignación de estos roles no está dentro del alcance del soporte de Groot/Kraken.

## Solucion Aplicada
El ticket fue rechazado. Se orientó al solicitante a gestionar la asignación del rol faltante con el equipo de gestión de usuarios de su operación o utilizando la herramienta Kraken. El soporte de Groot/Kraken no realiza asignaciones de roles.

## API Calls Involucrados
- WMS: `wms.adminml.com`

## Tags
wms, no-autorizado, rol, tl, rechazado, gestion-usuarios, kraken
