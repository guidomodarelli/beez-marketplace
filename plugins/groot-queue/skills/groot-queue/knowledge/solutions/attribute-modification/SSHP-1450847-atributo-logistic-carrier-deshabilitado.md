---
ticket: SSHP-1450847
category: attribute-modification
verdict: VALIDO_GROOT
summary: Atributo logistic carrier aparece deshabilitado en herramienta auth users — ni el usuario ni su líder pueden editarlo; fix asignando el carrier desde la vista de admin
date: 2026-06-02
effectiveness: confirmed
---

## Problema

El usuario necesita el rol `TRANSPORTATION_BC_CONTROL_FACTURACION_UTR_ANALYST` pero no puede obtenerlo porque el atributo `logistic carrier` aparece deshabilitado en la herramienta de auth users (`envios.adminml.com/tools/auth/users/shared/<groot_id>`). Ni el usuario ni su líder pueden editar el campo. No aparece mensaje de error, simplemente el campo está inactivo.

Site: MLB (Brasil). URL afectada: `https://envios.adminml.com/tools/auth/users/shared/<groot_id>`.

## Causa Raíz

El campo `logistic carrier` aparece deshabilitado en la herramienta de auth users. El origen exacto no fue determinado en este ticket (fue escalado desde SRE → Groot con nota "La operación comparte problemas con la pantalla de gestión de GROOT"). Puede estar relacionado con una inconsistencia de datos o un estado incompleto del usuario en la capa de atributos.

## Solución Aplicada

⚠️ **Workaround, no fix definitivo**: Julio Nicolas Gutierrez (2026-05-22) desbloqueó la operación asignando el atributo directamente desde la vista de administración del usuario en Groot:

```
https://envios.adminml.com/tools/auth/users/<groot_id>
```

Reemplazar `<groot_id>` con el ID numérico del usuario en Groot (visible en la URL del perfil en `envios.adminml.com/tools/auth/users/shared/<groot_id>`).

Comentario al usuario: "Buenos dias, podria intentar asignar el carrier desde esta vista? [URL del usuario] por favor notificarme si pudo realizar la accion"

Una vez asignado el carrier, el usuario pudo obtener el rol de facturación UTR.

**Después del workaround**: abrir un bug interno para investigar por qué el campo queda disabled — el workaround desbloquea al usuario pero no corrige la causa raíz.

## Señales para identificar este patrón

- ES: "atributo logistic carrier deshabilitado", "no puede editar logistic carrier", "campo carrier aparece inactivo", "líder tampoco puede editar el carrier"
- PT: "atributo logistic carrier desabilitado", "nao consegue editar logistic carrier", "campo carrier nao editavel"
- EN: "logistic carrier attribute disabled", "cannot edit logistic carrier", "carrier field is grayed out", "neither user nor leader can edit carrier"

## Tags

logistic-carrier, atributo-deshabilitado, attribute-modification, correios, facturacion-utr, auth-users
