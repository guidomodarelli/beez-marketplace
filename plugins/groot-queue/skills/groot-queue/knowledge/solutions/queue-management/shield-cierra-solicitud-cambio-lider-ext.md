---
ticket: SSHP-1415340
category: queue-management
summary: Shield cierra automáticamente las solicitudes de cambio de líder para colaboradores externos (ext_) — herramienta fuera de scope Groot
date: 2026-04-21
effectiveness: confirmed
verdict: DERIVAR
destination: IAM Soporte
rule: R-DER-07
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

Al solicitar cambio de líder para colaboradores externos (`ext_*`) en **Shield**, el chamado se cierra automáticamente. Sucede de forma consistente. Usuarios afectados: `ext_giovevan`, `ext_kelvidan`, `ext_oljmaria`, `ext_macedped`, `ext_thjacint`, `ext_raquegon`, `ext_daianfag`. Nuevo líder deseado: `ext_vinquint`.

## Causa Raíz

**Shield** es una herramienta fuera del alcance de Groot Soporte. El flujo de cambio de líder para colaboradores externos vive en Shield y el comportamiento (cierre automático) es un issue del propio Shield / su flujo de validación, no de Groot/Kraken.

## Solución Aplicada

1. Se identificó que el síntoma ocurre dentro de Shield.
2. Se derivó a **IAM Soporte** (`sup_iamcommerce_01`).

**Respuesta al cliente / reasignación (copy validado por Gocho):**
> Herramientas de Shield que no damos soporte. Derivar a IAM Soporte.

## Señales para identificar este patrón

- Mención de **Shield** como la herramienta afectada.
- Flujo de cambio de líder para colaboradores **externos** (`ext_*`).
- Síntoma: "el ticket se cierra solo", "la solicitud se cierra automáticamente".

## Verificación previa antes de derivar

Si el síntoma es en Shield → derivar directamente. Si el usuario pide un cambio de líder que **sí** se puede hacer desde la tool Groot (`envios.adminml.com/tools/auth/users/shared`) → **no aplica** R-DER-07; redirigir al líder para que use la autogestión (ver R-DESC-04).

## Tags

`shield` `iam-soporte` `cambio-lider` `ext_` `herramienta-externa` `derivacion` `R-DER-07`
