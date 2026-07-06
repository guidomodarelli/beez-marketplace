---
ticket: SSHP-1466772
category: queue-management
summary: Derivado a IAM Soporte — R-DER-09
date: 2026-05-27
effectiveness: confirmed
verdict: DERIVAR
rule: R-DER-09
destination: IAM Soporte
---

## Problema
Erro ao criar contas ext no Groot (identificador tributario invalido) no SSC1.
6 colaboradores afectados: error "Identificador tributario invalido" al intentar creación manual de cuentas ext. Los usuarios no tienen LDAP porque la creación falla.

## Acción Aplicada
Derivado a **IAM Soporte** aplicando regla **R-DER-09** — Tax ID inválido.

## Comentario Posteado
> "Hola, el error de tax id inválido corresponde a la validación de identidad gestionada por IAM Soporte. Derivamos para que continúen con el ajuste del documento."

## Señales que activaron la regla
- Error "Identificador tributario invalido" al crear cuentas ext en Groot
- CPFs de 6 colaboradores nuevos en SSC1 no superan la validación
- Los usuarios aún no tienen LDAP (creación bloqueada)
