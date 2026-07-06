---
ticket: SSHP-1457833
category: link-unlink-account
summary: Error "Tax_id has already been used" al crear un nuevo colaborador en Groot — el documento ya está asociado a otra identidad/LDAP. Groot no puede resolver duplicados de identidad; se deriva a IAM Soporte.
date: 2026-06-02
effectiveness: confirmed
verdict: DERIVAR
rule: R-DER-11
destination: IAM Soporte
---

## Problema
Usuario de SRJ8 reporta que no puede crear un nuevo colaborador en Groot. El sistema devuelve el error literal **"LDAP account: Tax_id has already been used"** y, en la cuenta Groot, "No pudimos continuar con la creación de la cuenta". Se trata de un new hire (datos de identidad omitidos por PII); el LDAP no se pudo generar. El tax_id es válido pero ya quedó asociado a otra identidad/LDAP previa.

## Solución Aplicada
Derivar el ticket a **IAM Soporte** (`sup_iamcommerce_01`). Groot no es dueño del flujo de identidad ni puede resolver duplicados de tax_id (CPF/CUIT/documento): solo IAM puede verificar el tax_id existente y liberarlo/vincularlo para que la creación de la cuenta pueda completarse. El ticket quedó `Resolved` asignado a IAM, lo que confirma que la derivación es el camino correcto.

Nota interna sugerida al derivar:
> "Hola chicos, derivamos este caso para su analisis, no podemos resolver este ticket desde Groot"

Regla de triage asociada: **R-DER-11** en `triage-rules.md`.

## Señales para identificar este patrón
- Al crear/dar de alta un colaborador, error literal **"Tax_id has already been used"** (string en inglés, aparece igual en tickets ES/PT/EN) + "No pudimos continuar con la creación de la cuenta" y LDAP que no se genera.
- Variantes de wording: ES "tax id ya utilizado" / "documento ya registrado"; PT "tax_id já utilizado" / "não consegue criar novo colaborador" / "CPF já cadastrado"; EN "Tax_id has already been used" / "cannot create new collaborator".
- Contexto típico: alta de un new hire cuyo CPF/CUIT/documento ya está en uso por otra identidad.
- Diferenciar de R-DER-09 (tax id *inválido* por formato/validación): acá el documento es válido pero **ya está en uso** (duplicado).

## Tags
tax_id, tax id already used, duplicado, documento ya en uso, CPF, CUIT, crear colaborador, new hire, LDAP, IAM Soporte, derivar, R-DER-11, identidad
