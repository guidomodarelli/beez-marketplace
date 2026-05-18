---
ticket: SSHP-1409554
category: user-visibility
summary: Reps en BRRJ02 no visualizan la bolha de inventario al login — usuarios ya están en el facility correcto
date: 2026-04-21
effectiveness: confirmed
verdict: DESCARTAR
rule: R-DESC-07
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

Reps sin acceso a la bolha de inventario en el warehouse BRRJ02. El problema aparece al login — la bolha de inventario no se muestra. Usuarios afectados: `bvianna`, `ndecsantos`. El reporte pide ajuste de acceso/permisos para visualizar y acceder a la bolha.

## Causa Raíz

No es un problema sistémico de Groot. Los usuarios están correctamente ubicados en el facility mencionado. La asignación de acceso a una función específica del site es responsabilidad del **equipo de gestión de usuarios de la operación** de ese warehouse, no de Groot Soporte.

## Solución Aplicada

1. Se verificó en Groot admin que los usuarios están vinculados al facility BRRJ02.
2. Como el warehouse está correcto, el tema sale del scope de Groot.
3. Se cerró el ticket como descartado con la derivación al gestor de usuarios de la operación.

**Respuesta al cliente (copy validado por Gocho):**
> Hola, los usuarios están ubicados en el facility mencionado. En caso de no tener acceso a alguna función, esto debe ser revisado con el equipo de gestión de usuarios de su operación.

## Señales para identificar este patrón

- Summary o description menciona: "reps no ven bolha", "nao visualizam a bolha", "não aparece no login", falta una funcionalidad específica.
- Verificación en Groot: el usuario **está** correctamente ubicado en el facility reportado.
- No hay error técnico en edición / guardado del usuario.

## Verificación previa antes de descartar

Confirmar en Groot admin que los usuarios reportados **están** en el warehouse/facility mencionado en el ticket. Si **no** lo están → reclasificar como `VALIDO_GROOT` (runbook Warehouse/Site) y corregir.

## Tags

`visibilidad` `bolha` `inventario` `warehouse` `gestion-usuarios-operacion` `descarte` `R-DESC-07`
