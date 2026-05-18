---
ticket: SSHP-1418490
category: queue-management
summary: Solicitud de remover un rol a un operario — Groot no hace asignaciones ni remociones de roles
date: 2026-04-21
effectiveness: confirmed
verdict: DESCARTAR
rule: R-DESC-09
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

Usuario solicita **remover** el rol "Problem Solver Polivalente" del operario LDAP `ddelafuenter` (id 523713). Link de referencia: `https://envios.adminml.com/tools/auth/users/shared/523713`.

## Causa Raíz

Groot Soporte no es la cola para asignación ni remoción de roles a operarios. Esas operaciones las realiza el **gestor de usuarios de la operación** del site correspondiente — desde la propia herramienta de usuarios Groot (envíos admin).

## Solución Aplicada

1. Se verificó que el rol existe y está asignado al usuario.
2. Se confirmó que no hay error técnico (remoción manual funcionaría).
3. Se cerró el ticket como descartado derivando al gestor de usuarios.

**Respuesta al cliente (copy validado por Gocho):**
> Esta solicitud debe ser enviada al equipo de gestión de usuario de su operación. Desde soporte Groot/Kraken no hacemos este tipo de asignaciones o remociones.

## Señales para identificar este patrón

- Summary o description menciona: "remover rol", "quitar rol", "desasignar rol", "asignar rol", "agregar rol".
- No hay error técnico reportado (la tool funciona, sólo piden que **nosotros** ejecutemos el cambio).
- El requester no es un gestor de usuarios de operación.

## Verificación previa antes de descartar

Si el usuario reporta que **intentó** remover el rol y el sistema dio error → **no aplica** R-DESC-09; reclasificar como `VALIDO_GROOT` (runbook Roles/Permisos).

Relación con otras reglas:
- Complementa a `R-DESC-02` (asignación de roles).
- Juntas cubren asignar + remover sin error técnico.

## Tags

`remover-rol` `asignar-rol` `gestion-usuarios-operacion` `descarte` `R-DESC-09`
