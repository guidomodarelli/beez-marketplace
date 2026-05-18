---
ticket: SSHP-1415474
category: hierarchy-leader
summary: Cambio de supervisor directo para reps — Groot sólo atiende errores sistémicos; el líder puede hacerlo desde la tool de autogestión
date: 2026-04-21
effectiveness: confirmed
verdict: DESCARTAR
rule: R-DESC-04
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

User pide cambio de supervisor directo en Groot para reps de SRM2. Nuevo supervisor directo: LDAP `NRETAMALES`. Reps a mover: `iolguinyanez`, `jllanquechoq`, `ldiazmunoz`, `prodriguezlo`, `ext_tivergar`, `ext_accamilo`, `ext_isfabres`, `ext_jemmoral`. **No reporta error técnico, es una solicitud operativa.**

## Causa Raíz

No es un incidente. Groot Soporte se encarga sólo de **errores sistémicos**. El cambio de líder/supervisor directo es una operación que el líder actual puede resolver por sí mismo desde la herramienta de autogestión de Groot admin.

## Solución Aplicada

1. Se verificó que no hay error técnico (la tool de cambio de líder funciona).
2. Se cerró el ticket indicándole al requester el link directo para hacer el cambio.

**Respuesta al cliente (copy validado por Gocho):**
> Hola, desde soporte Groot sólo atendemos errores sistémicos. Este tipo de solicitud la pueden hacer los líderes actuales a través de `https://envios.adminml.com/tools/auth/users/shared?active=true` usando la opción de **cambio de líder**.

## Señales para identificar este patrón

- Summary o description dice: "cambio de supervisor directo", "cambiar líder a X usuarios", "trocar líder", "mover reps a supervisor Y".
- El requester **no** reporta error — simplemente pide la operación.
- Lista de usuarios a mover + un nuevo líder target claro.

## Verificación previa antes de descartar

Confirmar que **no** hay un error sistémico. Si el requester dice "intenté y me da error" → **no aplica** R-DESC-04, reclasificar como `VALIDO_GROOT` (runbook Jerarquía/Líder).

## URL de la tool

`https://envios.adminml.com/tools/auth/users/shared?active=true` — opción **cambio de líder**.

## Tags

`cambio-lider` `supervisor-directo` `autogestion` `envios-adminml` `descarte` `R-DESC-04`
