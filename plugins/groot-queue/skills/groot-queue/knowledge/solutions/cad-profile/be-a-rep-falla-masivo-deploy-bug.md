---
ticket: SSHP-1401334
category: cad-profile
summary: Proceso "Be a Rep" fallaba para múltiples usuarios. Causa: un deploy del 30/03 afectó el proceso de agendado por aproximadamente 4 horas. El fix fue desplegado el mismo día.
date: 2026-04-04
effectiveness: confirmed
---

## Problema
Múltiples usuarios reportaron que el proceso de "Be a Rep" (CAD) fallaba al intentar agendarse. El error afectaba de forma masiva a usuarios en distintos sites, impidiendo que los complementos de turno pudieran procesarse.

## Causa Raiz
Un deploy realizado el 30/03 introdujo un defecto en el proceso de agendado de "Be a Rep". El bug afectó el flujo durante aproximadamente 4 horas, período en el cual todas las solicitudes de agendado retornaban error.

## Solucion Aplicada
El equipo de desarrollo identificó el bug introducido por el deploy y desplegó una corrección el mismo día. Una vez aplicado el fix, el proceso de agendado de "Be a Rep" volvió a funcionar correctamente para todos los usuarios afectados.

## Tags
be-a-rep, cad, agendado, deploy-bug, masivo, snapshot, fix-mismo-dia
