---
ticket: SSHP-1410431
category: groot-ui-error
summary: Error "Opss...ocorreu um erro ao editar usuario" al intentar editar un usuario externo. Causa: jerarquía en null bloqueaba la edición. Se corrigió la inconsistencia.
date: 2026-04-14
effectiveness: confirmed
verdict: VALIDO_GROOT
---

## Problema
Al intentar editar el perfil de un usuario externo (`ext_*`) en la interfaz de Groot, el sistema mostraba el error: "Opss...ocorreu um erro ao editar usuario". El error impedía cualquier modificación al perfil del usuario.

## Causa Raiz
El campo de jerarquía del usuario estaba configurado con valor null. Este estado inconsistente bloqueaba el proceso de edición, ya que el sistema no podía completar la operación al encontrar una jerarquía inválida.

## Solucion Aplicada
El equipo de soporte identificó y corrigió la inconsistencia en el campo de jerarquía del usuario en Groot, estableciendo los valores correctos y eliminando el null. Una vez corregida la inconsistencia, la edición del usuario pudo realizarse correctamente.

## API Calls Involucrados
- Consulta y modificación del perfil del usuario en: `envios.adminml.com/tools/auth/users/shared/`

## Tags
groot-ui, error-edicion, jerarquia-null, inconsistencia, opss-error
