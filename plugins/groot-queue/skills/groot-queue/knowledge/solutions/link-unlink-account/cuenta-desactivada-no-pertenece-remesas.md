---
ticket: SSHP-1471443
category: link-unlink-account
summary: Derivado a IAM Soporte (R-DER-01) — cuenta ext_beatrnog desactivada y "no pertenece a remesas" al accederla en el ABM de Groot; la cuenta no está marcada como shipping a nivel IAM y solo IAM puede setear el flag para habilitarla/reactivarla.
date: 2026-06-02
effectiveness: confirmed
---

## Problema
Usuario reporta error de permisos/atributos en la herramienta de gestión de usuarios. Al acceder al perfil en `https://envios.adminml.com/tools/auth/users/shared/1191953` aparece el mensaje **"usuario nao pertence as remessas"** y la **cuenta figura desactivada**. Solicitan reactivar la cuenta y "deixar o rep disponivel sistemicamente". Usuario afectado: `ext_beatrnog`.

## Solución Aplicada
Derivado a IAM Soporte (R-DER-01): la cuenta `ext_beatrnog` figura desactivada y "no pertenece a remesas" al accederla desde el ABM de Groot. La cuenta no está marcada como shipping a nivel IAM; Groot no puede habilitarla. IAM debe setear el flag de shipping para que Groot pueda gestionar/reactivar al usuario desde el ABM. Confirmado: ticket Resolved y asignado a `sup_iamcommerce_01`.

Nota interna sugerida al derivar (R-DER-01):
> "Hola, les derivamos este ticket para que nos ayuden marcando la cuenta con el flag de shipping. Una vez marcada, el usuario queda habilitado y podemos gestionarla desde nuestro ABM (tools de Groot). ¡Gracias!"

Regla de triage asociada: **R-DER-01** en `triage-rules.md`.

## Señales para identificar este patrón
- El admin/gestor, al acceder al perfil del usuario en el ABM de Groot (`envios.adminml.com/tools/auth/users/shared/...`), ve que la cuenta está **desactivada** y un mensaje de que el usuario **no pertenece a envíos/remesas**.
- Variantes de wording: ES "no pertenece a envíos" / "no es cuenta de envíos"; PT "usuario nao pertence as remessas" / "não pertence às remessas" / "conta não é de envios"; EN "does not belong to shipping" / "is not a shipping account".
- Piden **reactivar** la cuenta / "dejar el rep disponible sistémicamente"; no aparece la opción de habilitar desde Groot.
- El usuario puede ser `ext_*` (externo): eso solo no lo convierte en R-DER-06 (que exige que el ext_* sea reconocido como cuenta Meli en Kioske/TOTEM).
- Diferenciar de R-DER-10: el bloqueo lo ve el **admin** en el ABM, no el usuario final desde el frontend.

## Tags
no pertenece a remesas, nao pertence as remessas, does not belong to shipping, cuenta desactivada, conta desativada, flag shipping, reactivar cuenta, ABM Groot, ext_beatrnog, IAM Soporte, derivar, R-DER-01, habilitar usuario
