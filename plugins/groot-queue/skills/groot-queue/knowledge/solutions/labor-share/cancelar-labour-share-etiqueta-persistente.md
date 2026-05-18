---
ticket: SSHP-1408044
category: labor-share
summary: No se podía cancelar un Labour Share activo. Se resolvió eliminando manualmente la etiqueta de labour share del perfil del usuario.
date: 2026-04-10
effectiveness: confirmed
---

## Problema
Un operador reportó que no podía cancelar un Labour Share que estaba activo para un usuario. La opción de cancelación no funcionaba correctamente y el Labour Share permanecía activo.

## Causa Raiz
La etiqueta (label) de Labour Share en el perfil del usuario no podía ser removida a través del flujo estándar de cancelación. Esta etiqueta es el mecanismo que mantiene activo el Labour Share; si no se puede eliminar por el canal normal, el Labour Share queda "bloqueado".

## Solucion Aplicada
El equipo de soporte eliminó manualmente la etiqueta de Labour Share del perfil del usuario afectado en Groot, lo que permitió cancelar efectivamente el Labour Share y liberar al usuario de esa asignación temporal.

## API Calls Involucrados
- Consulta y modificación del perfil del usuario en: `envios.adminml.com/tools/auth/users/shared/`
- Eliminación de etiqueta de labour share via API interna de Groot

## Tags
labour-share, cancelacion, etiqueta, label, eliminacion-manual
