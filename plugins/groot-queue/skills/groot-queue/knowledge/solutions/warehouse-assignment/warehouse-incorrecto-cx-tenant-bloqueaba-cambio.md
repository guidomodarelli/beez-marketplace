---
ticket: SSHP-1494734
category: warehouse-assignment
summary: Warehouse default incorrecto tras migración de site — ajustar atributo CX Tenant para poder guardar cambios
date: 2026-07-01
effectiveness: confirmed
---

## Problema
Colaborador migrado de MXCD07 a MXCD09 seguía figurando con warehouse default MXCD07 en Groot. Ya se habían hecho ajustes de cambio de líder en WMS y PMO pero el warehouse no se actualizaba.

## Solución Aplicada
Se adecuó el usuario: el atributo CX Tenant no tenía valor asignado, lo cual impedía guardar los cambios. Se le colocó un valor al atributo CX Tenant y luego se pudo actualizar el warehouse correctamente.

## Señales para identificar este patrón
- "warehouse default incorrecto tras migración" / "warehouse default incorreto após migração" / "incorrect default warehouse after migration"
- Usuario migrado de un site a otro pero warehouse no se actualiza
- Error al guardar cambios en el perfil del usuario (atributo CX Tenant vacío)
- "no puede guardar" / "não consegue salvar" / "cannot save" al modificar warehouse

## Tags
warehouse, migración, CX Tenant, atributo vacío, no guarda, site incorrecto
