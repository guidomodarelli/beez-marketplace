---
ticket: SSHP-1464062
category: queue-management
summary: Derivado a IAM Soporte — R-DER-09
date: 2026-05-27
rule: R-DER-09
destination: IAM Soporte
effectiveness: confirmed
---

## Problema
Erro ao criar conta ext no Groot por identificador tributario invalido (CPF).
El documento de una colaboradora no supera la validación al intentar crear cuenta ext en BRMG02.

## Acción Aplicada
Derivado a **IAM Soporte** aplicando regla **R-DER-09** — Tax ID inválido.

## Comentario Posteado
> "Hola, el error de tax id inválido corresponde a la validación de identidad gestionada por IAM Soporte. Derivamos para que continúen con el ajuste del documento."

## Señales que activaron la regla
- Error "Identificador tributario invalido" al crear cuenta ext en Groot
- Documento inválido para colaboradora específica en warehouse BRMG02
- Error en pantalla /tools/auth/users/shared
