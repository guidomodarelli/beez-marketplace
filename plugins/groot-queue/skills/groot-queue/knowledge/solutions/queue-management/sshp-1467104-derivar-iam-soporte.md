---
ticket: SSHP-1467104
category: queue-management
summary: Derivación manual pendiente a IAM Soporte — R-DER-10
date: 2026-05-27
rule: R-DER-10
destination: IAM Soporte
effectiveness: unconfirmed
status: manual_transition_pending
---

## Problema
Groot external user creation blocked because document already has LDAP not belonging to shipping.
El sistema muestra: "El CUIT ya cuenta con una cuenta LDAP asociada que no pertenece a shipping, por favor verifique la información."
El TL no puede dar de alta a un colaborador recién ingresado en SJP1 porque el CUIT ya tiene un LDAP pero no está marcado como shipping.

## Acción Recomendada
Derivar manualmente a **IAM Soporte** aplicando regla **R-DER-10** — "No perteneces a envíos" al crear / desbloquear cuenta.

## Comentario Sugerido
> "Hola, el mensaje 'no perteneces a envíos' indica que la cuenta no está marcada como shipping a nivel de IAM. Derivamos para que IAM Soporte ajuste el flag y el usuario pueda completar el flujo."

## Señales que activaron la regla
- Usuario intenta crear cuenta externa en Groot (`/tools/auth/users/external/new`)
- Mensaje del sistema incluye "no pertenece a shipping" / "no pertenece a envíos"
- El CUIT tiene un LDAP existente pero sin flag de shipping
- El usuario no puede completar el flujo de creación — queda bloqueado antes de obtener su LDAP

## Nota operativa — Limitación ACLI
La transición a "Derivar a otro equipo" en Jira requiere campos adicionales (motivo de derivación + comentario privado de traspaso) que ACLI no puede proveer por línea de comandos. La transición debe completarse **manualmente en la UI de Jira**:
1. Abrir https://mercadolibre.atlassian.net/browse/SSHP-1467104
2. Hacer clic en la transición "Derivar a otro equipo"
3. Completar: motivo de derivación = "R-DER-10 — cuenta no marcada como shipping en IAM"
4. Completar: comentario privado de traspaso = "Derivar a IAM Soporte para ajuste del flag de shipping"
