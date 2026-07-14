---
ticket: SSHP-1416401
category: hierarchy-leader
summary: Error al solicitar cambio de lider para usuario externo; se resolvio adecuando el lider manualmente en Groot.
date: 2026-04-16
effectiveness: confirmed
verdict: VALIDO_GROOT
---

## Problema

Al intentar realizar un cambio de lider para un usuario externo (`ext_*`) mediante el flujo estandar de Groot, el proceso fallaba con error. El solicitante no podia completar la operacion por los medios normales.

## Causa Raiz

No se identifico una causa raiz definitiva para el error. La operacion no pudo completarse por el canal estandar, lo que requirio intervencion manual del equipo de soporte.

## Solucion Aplicada

El equipo de soporte adecuo manualmente el lider del usuario externo en Groot, resolviendo el inconveniente de forma directa.

## Señales para identificar este patron

- ES: "error al cambiar lider de usuario externo", "no puedo cambiar el supervisor de ext_", "falla el cambio de lider en Groot para ext_", "solicitud de cambio de lider falla".
- PT: "erro ao trocar lider de usuario externo", "nao consigo alterar o supervisor de ext_", "falha na troca de lider no Groot para ext_", "solicitacao de troca de lider falha".
- EN: "external user leader change fails", "cannot change supervisor for ext_", "Groot leader-change flow fails for ext_", "leader change request fails".
- El usuario afectado es externo (`ext_*`) y el flujo estandar de cambio de lider/supervisor en Groot arroja error o no guarda el cambio.
- El ticket reporta una falla de herramienta, no una solicitud operativa sin error. No aplicar descarte por autogestion (`R-DESC-04`) cuando esta condicion se cumple.

## Tags

cambio-lider, error-flujo, intervencion-manual, ext_, external-user, leader-change, manual-workaround
