---
ticket: SSHP-1410837
category: hierarchy-leader
summary: Usuarios externos quedaron con el manager incorrecto luego de ser creados por Rostering, que envió un groot_leader erróneo.
date: 2026-04-16
effectiveness: confirmed
derived_to: Rostering
verdict: VALIDO_GROOT
---

## Problema
Usuarios creados mediante el proceso de Rostering quedaron asignados con un lider incorrecto como groot_leader primario. El equipo solicitante reportó que el manager principal no estaba alineado con lo esperado.

## Causa Raiz
El proceso de Rostering envió un valor incorrecto en el campo groot_leader al momento de crear los usuarios. Este campo determina el lider jerárquico principal en Groot, y al estar mal configurado desde el origen, los usuarios quedaron con un manager que no correspondía.

## Solucion Aplicada
El ticket fue resuelto mediante el flujo normal de cambio de líder disponible en Groot. Se orientó al solicitante a realizar el cambio de líder a través del proceso estándar del sistema, sin necesidad de intervención directa del equipo de soporte.

## Tags
rostering, groot-leader, manager-primario, desalineacion
