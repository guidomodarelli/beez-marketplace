---
ticket: SSHP-1408044
related-ticket: SSHP-1406774
category: labor-share
summary: Etiqueta persistente mantiene Labour Share activo o usuario atrapado en warehouse destino; remover etiqueta manualmente
date: 2026-04-10
effectiveness: confirmed
verdict: VALIDO_GROOT
---

## Problema
Un Labour Share finalizado o cancelado puede permanecer activo porque etiqueta del perfil no se elimina. Síntomas observados:

- Opción de cancelación no libera usuario.
- Rep queda atrapado en warehouse destino y no retorna al warehouse de origen.

## Causa Raiz
La etiqueta (label) de Labour Share en el perfil del usuario no podía ser removida a través del flujo estándar de cancelación. Esta etiqueta es el mecanismo que mantiene activo el Labour Share; si no se puede eliminar por el canal normal, el Labour Share queda "bloqueado".

## Solucion Aplicada
El equipo de soporte eliminó manualmente la etiqueta de Labour Share del perfil del usuario afectado en Groot. Esto canceló asignación temporal y permitió retorno al warehouse de origen cuando correspondía.

## API Calls Involucrados
- Consulta y modificación del perfil del usuario en: `envios.adminml.com/tools/auth/users/shared/`
- Eliminación de etiqueta de labour share via API interna de Groot

## Tags
labour-share, cancelacion, etiqueta, label, eliminacion-manual, warehouse-incorrecto, usuario-atrapado
