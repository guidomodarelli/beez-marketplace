---
ticket: SSHP-1416994
category: role-permission
summary: Usuario con "nao autorizado" en un módulo específico de Logistics — Groot no determina qué rol habilita cada funcionalidad
date: 2026-04-21
effectiveness: confirmed
verdict: DESCARTAR
rule: R-DESC-05
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

Colaborador `arcossilsilv` logra loguearse pero al acceder a `https://envios.adminml.com/logistics/monitoring-distribution/detail/366180690?site=MLB` recibe error **"no autorizado"**. Afecta sólo a este usuario. Nunca tuvo acceso al módulo. Facility: BRSSP5. Se pide ajuste de permiso/rol/atributo para acceder al módulo monitoring-distribution.

## Causa Raíz

No es un problema técnico de Groot. El usuario logra autenticarse — lo que no tiene es el **rol/permiso específico** que habilita el módulo `monitoring-distribution`. Saber **cuál** es el rol que habilita cada funcionalidad no es competencia de Groot/Kraken Soporte: eso lo determina el equipo de gestión de usuarios de la operación según el mapa de permisos del site.

## Solución Aplicada

1. Se confirmó que el usuario se loguea (auth funciona).
2. Se validó que no hay error técnico (el "no autorizado" es comportamiento esperado sin el rol correspondiente).
3. Se cerró el ticket derivando al gestor de usuarios de la operación para que determine el rol faltante.

**Respuesta al cliente (copy validado por Gocho):**
> Hola, desde soporte Groot/Kraken no somos responsables de saber cuál es el permiso/rol que habilita una funcionalidad. Esto debe ser dirigido a los equipos de gestión de usuarios de su operación para que determinen si hay un rol faltante o si requiere ajustes en los roles actuales.

## Señales para identificar este patrón

- Error **"no autorizado"** / **"não autorizado"** / **"not authorized"** en una URL/módulo específico.
- El usuario **sí** logra loguearse (auth OK).
- El requester pregunta "qué rol necesita" o "qué permiso falta".
- Afecta sólo a un usuario (o pocos) sin patrón general.

## Verificación previa antes de descartar

Consultar en Groot que el usuario tenga los roles base de su función (Rep, TL, etc.). Si falta un rol **base** conocido (ej: rol PS que ya tenía) → reclasificar como `VALIDO_GROOT`. Si es un módulo nuevo o específico del que Groot no tiene mapeo → descartar con R-DESC-05.

## Tags

`no-autorizado` `not-authorized` `logistics` `monitoring-distribution` `rol-especifico` `gestion-usuarios-operacion` `descarte` `R-DESC-05`
