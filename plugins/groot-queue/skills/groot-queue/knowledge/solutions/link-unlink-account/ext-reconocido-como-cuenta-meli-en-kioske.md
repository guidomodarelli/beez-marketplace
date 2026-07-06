---
ticket: SSHP-1412206
category: link-unlink-account
summary: Usuario externo (ext_) reconocido como cuenta Meli en Kioske y no puede cambiar contraseña — TOTEM autogestión no lo gestiona
date: 2026-04-21
effectiveness: confirmed
verdict: DERIVAR
rule: R-DER-06
destination: IAM Soporte
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

Un colaborador externo (`ext_*`) aparece como **cuenta Meli** en el Kioske (no como EXT) y no consigue cambiar contraseña porque el sistema lo interpreta como usuario interno.

## Causa Raíz

El usuario es **externo** (LDAP con prefijo `ext_`) pero está marcado a nivel identidad como interno, por eso el **TOTEM de autogestión** de las operaciones lo rechaza. El fix no corresponde a Groot — requiere que IAM Soporte ajuste el flag de identidad/cuenta.

## Solución Aplicada

1. Se verificó en Groot admin que el usuario efectivamente tiene LDAP `ext_*`.
2. Se confirmó que no es un problema de configuración en Groot/Kraken.
3. Se derivó el ticket a **IAM Soporte**.

**Respuesta al cliente / reasignación (copy validado por Gocho):**
> Usuario externo que es reconocido como usuario interno y por esta razón no puede ser gestionado por el TOTEM de autogestión de las operaciones.

## Señales para identificar este patrón

- Usuario con LDAP `ext_*` (colaborador externo).
- Aparece como **cuenta Meli** en el Kioske o en flujos donde debería aparecer como EXT.
- No puede cambiar contraseña vía TOTEM.
- Groot lo muestra correctamente como ext_ pero otros sistemas no reconocen el flag.

## Verificación previa antes de derivar

Confirmar en Groot que el LDAP tiene prefijo `ext_` y que en Groot sí figura como externo. Si en Groot aparece como Meli → **no aplica** R-DER-06; primero corregir en Groot (runbook `Vincular/Desvincular`).

## Tags

`ext_` `cuenta-meli` `kioske` `totem` `autogestion` `iam-soporte` `derivacion` `R-DER-06`
