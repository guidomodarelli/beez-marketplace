---
ticket: SSHP-1451920
category: role-permission
verdict: VALIDO_GROOT
summary: Usuario no ve la opción para solicitar Be a Rep en WMS — validación de shipping position bloqueaba la opción; fix de dev requerido
date: 2026-06-02
effectiveness: confirmed
---

## Diferenciación importante con el cluster "Be a Rep funcionalidad existente"

Este caso **no** es el patrón de "Be a Rep muestra Acceso no autorizado" (que es funcionalidad existente y se descarta). Aquí el botón de Be a Rep **directamente no aparece** en la pantalla de WMS, causado por un bug de validación del lado del backend.

- Si el botón **aparece** pero devuelve "Acceso no autorizado" → ver cluster Be a Rep (funcionalidad existente, R-DESC-05).
- Si el botón **no aparece** → este patrón; es `VALIDO_GROOT` (bug real) y requiere escalado a dev.

## Problema

Usuario AUGUERRERO no ve la opción para solicitar el flujo Be a Rep en WMS (site MXCD02). Al acceder a la pantalla de WMS, el botón/opción de Be a Rep no aparece disponible — no es que devuelva error, simplemente no se renderiza.

## Causa Raíz

Una validación de shipping position en el backend bloqueaba la opción de Be a Rep para este usuario. El cambio de "shipping position" al nuevo esquema no fue contemplado en esa validación.

## Solución Aplicada

Fix de dev aplicado por Francisco Gonzalez el 2026-05-25: se ajustaron las validaciones para contemplar la nueva shipping position.

⚠️ **Esta solución no es reproducible por soporte**: es una corrección de código backend, no una acción en la herramienta de Groot. Si el patrón reaparece (otro usuario sin el botón Be a Rep en WMS), el agente de soporte debe:
1. Confirmar que el botón no aparece (no que da "no autorizado").
2. Registrar el LDAP, site y warehouse afectados.
3. Escalar al dev Groot con evidencia (screenshot + datos del usuario).

## Señales para identificar este patrón

- ES: "no tiene opción para solicitar Be a Rep", "el botón Be a Rep no aparece en WMS", "no se ve la opción de Be a Rep en la pantalla WMS"
- PT: "não vê a opção de solicitar Be a Rep no WMS", "botão Be a Rep não aparece no WMS", "opção de Be a Rep sumiu da tela WMS"
- EN: "user does not see Be a Rep option in WMS", "Be a Rep button missing in WMS screen", "Be a Rep option not rendered in WMS"

## Tags

be-a-rep, wms, opcion-no-aparece, shipping-position, validacion, role-permission, bug-dev, escalar-dev
