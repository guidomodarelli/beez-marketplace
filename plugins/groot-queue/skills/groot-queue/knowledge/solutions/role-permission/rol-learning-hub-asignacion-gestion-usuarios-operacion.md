---
ticket: SSHP-1412472
category: role-permission
summary: Usuario completó Learning Hub pero no ve el rol esperado — la asignación post-learning la hace el gestor de usuarios de la operación, no Groot
date: 2026-04-21
effectiveness: confirmed
verdict: DESCARTAR
rule: R-DESC-08
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

Un usuario de la operación reporta que completó el learning requerido pero **no** ve el rol esperado. Pide corrección de rol/permisos en Groot.

## Causa Raíz

La asignación de roles post-Learning Hub / Training Hub **no** se hace automáticamente desde Groot. La correspondencia "learning completado → rol asignado" es competencia del **gestor de usuarios de la operación** del site. Groot Soporte no opera esa asignación.

## Solución Aplicada

1. Se verificó que el usuario tiene el learning completado y está correctamente ubicado en MCJC02.
2. Se confirmó que no hay error técnico en Groot (el rol Outbound sí está aplicado, lo que muestra que el sistema no está roto).
3. Se cerró el ticket como descartado derivando al gestor de la operación.

**Respuesta al cliente (copy validado por Gocho):**
> Hola, las solicitudes de roles a partir de asistencia en Learning Hub / Training Hub son atendidas por el equipo de gestión de usuarios de la operación. Desde aquí no damos soporte a este tipo de solicitudes.

## Señales para identificar este patrón

- Summary o description menciona: "completó learning", "learning hub", "training hub", "asistió al entrenamiento", "terminó capacitación".
- Usuario pide asignación de un rol específico post-capacitación.
- En Groot no hay error técnico (el sistema funciona).

## Verificación previa antes de descartar

Confirmar que no hay error sistémico: editar el usuario en Groot admin y validar que el rol solicitado existe y podría asignarse. Si hay un error técnico real al asignar → **no aplica** R-DESC-08, reclasificar como `VALIDO_GROOT`.

## Tags

`learning-hub` `training-hub` `asignacion-rol` `gestion-usuarios-operacion` `descarte` `R-DESC-08`
