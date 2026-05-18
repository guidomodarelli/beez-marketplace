---
ticket: SSHP-1396486
category: labor-share
summary: Las horas configuradas en Labour Share no persistían y volvían a su valor original al día siguiente debido a un bug en el proceso de snapshot.
date: 2026-04-14
effectiveness: confirmed
---

## Problema
Al configurar horas mediante Labour Share, los cambios no persistían correctamente. Al día siguiente de la configuración, las horas volvían automáticamente al valor previo, sin respetar la configuración establecida por el operador.

## Causa Raiz
Se identificó un bug en el proceso de snapshot de Labour Share. Este componente es el responsable de persistir los cambios de configuración de usuarios en Groot; al fallar, las modificaciones no se guardaban correctamente y eran revertidas por el proceso nocturno.

## Solucion Aplicada
Se implementaron mejoras en el proceso de snapshot de Labour Share para corregir el bug identificado. El fix fue desplegado y validado, confirmando que los cambios de horas persisten correctamente tras la corrección.

## Tags
labour-share, snapshot, persistencia, bug, horas, reversion-automatica
