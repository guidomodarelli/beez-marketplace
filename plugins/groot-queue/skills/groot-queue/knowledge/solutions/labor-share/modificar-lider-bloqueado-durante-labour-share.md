---
ticket: SSHP-1504527
category: labor-share
summary: No se puede modificar superior directo mientras usuario está en labour share — esperar a que finalice el LS
date: 2026-07-01
effectiveness: confirmed
verdict: VALIDO_GROOT
---

## Problema
Se solicita modificar el superior directo del rep mmdmiranda, pero el cambio no puede realizarse porque el usuario se encuentra actualmente en proceso de Labour Share.

## Solución Aplicada
Se informó que mientras el usuario está en Labour Share, ciertos atributos (incluyendo el líder directo) quedan bloqueados para modificación. Se debe esperar a que finalice el Labour Share o cancelarlo primero antes de hacer el cambio de superior.

## Señales para identificar este patrón
- "modificar superior directo" / "modificar líder" + usuario en labour share
- "modificar superior direto" / "trocar líder" + usuário em labour share
- "change direct supervisor" / "modify leader" + user in labour share
- El cambio de líder falla silenciosamente o es rechazado para un usuario con LS activo

## Tags
labour share, labor share, líder directo, superior, bloqueo, modificar supervisor, cambio bloqueado
