---
ticket: SSHP-1409680
category: user-visibility
summary: Rep reportada como "vinculada al CAD errado" — en realidad los valores se asignan tras el clock-in físico
date: 2026-04-21
effectiveness: confirmed
verdict: DESCARTAR
rule: R-DESC-06
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

Usuario reporta que la rep Caroline De Souza Mota (ID 2095151, groot_id `csmota`) está "vinculada sistémicamente al cad SP04" pero debería estar en SSP26, y por eso no puede solicitar la bolha **Out Shipping** para SSP26. Se pide corrección del vínculo de facility y habilitación de la bolha.

## Causa Raíz

No es un bug. El usuario es un **rep**, y los reps **no** tienen CAD/atributo fijo asignado — los valores se obtienen dinámicamente a partir del **clock-in físico** que el usuario hace cada día al entrar al site. Antes del clock-in, el sistema no sabe en qué facility está trabajando.

Se verificó que después de que la rep hizo el clock-in, automáticamente aparece con el valor correcto (SSP26) y puede solicitar la bolha Out Shipping.

## Solución Aplicada

1. Se verificó el estado del usuario en Groot admin.
2. Se confirmó que tras el clock-in la rep tenía el valor correcto.
3. Se cerró el ticket como descartado explicando el comportamiento esperado.

**Respuesta al cliente (copy validado por Gocho):**
> Hola, el usuario al ser un rep obtiene los valores a partir de los clock-in físicos. Vemos que el usuario después de hacer el clock-in tiene asignado el valor que requiere.

## Señales para identificar este patrón

- El usuario afectado es un **rep** (no TL ni manager).
- Summary menciona: "vinculada al cad errado", "no puede solicitar bolha", "CAD incorrecto".
- El usuario reporta el síntoma **antes** de haber hecho clock-in en el site deseado.
- Tras clock-in físico, el valor aparece correcto sin necesidad de intervención.

## Verificación previa antes de descartar

Consultar el estado actual del rep en Groot admin. Si **ya hizo clock-in** y aun así no tiene el valor correcto → **no aplica** R-DESC-06, reclasificar como `VALIDO_GROOT` (posible bug de sincronización clock-in ↔ Groot).

## Tags

`rep` `clock-in` `bolha` `out-shipping` `cad-dinamico` `descarte` `R-DESC-06`
