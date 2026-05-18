---
ticket: SSHP-1406774
category: labor-share
summary: El rep juvelazquez quedó asignado permanentemente a ARBA02 sin poder volver a ARBA01 debido a una etiqueta de labour share activa que no se eliminó al finalizar el periodo.
date: 2026-04-13
effectiveness: confirmed
---

## Problema
El representante juvelazquez quedó asignado al warehouse ARBA02 y no podía regresar a su warehouse de origen ARBA01. El sistema lo mantenía en ARBA02 como si el Labour Share siguiera activo, a pesar de que el período debería haber finalizado.

## Causa Raiz
Existía una etiqueta (label) de Labour Share activa y persistente en el perfil del usuario que no se eliminó automáticamente al vencer el periodo de Labour Share. Esta etiqueta es la que determina el warehouse de asignación durante un Labour Share; al no removerse, el usuario quedó "atrapado" en el warehouse incorrecto.

## Solucion Aplicada
Se eliminó manualmente la etiqueta de Labour Share del perfil del usuario juvelazquez en Groot. Una vez removida la etiqueta, el sistema reconoció que el Labour Share había concluido y el usuario pudo ser reasignado correctamente a su warehouse de origen ARBA01.

## API Calls Involucrados
- Consulta y modificación del perfil del usuario en: `envios.adminml.com/tools/auth/users/shared/`
- Eliminación de etiqueta de labour share via API interna de Groot

## Tags
labour-share, etiqueta, label, warehouse-incorrecto, arba01, arba02, juvelazquez, stuck-user
