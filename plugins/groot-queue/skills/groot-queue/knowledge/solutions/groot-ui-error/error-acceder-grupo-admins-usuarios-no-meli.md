---
ticket: SSHP-1494154
category: groot-ui-error
summary: Error al acceder a grupo de usuarios en Groot para editar administradores — se removieron usuarios no-MELI del listado de admins
date: 2026-07-01
effectiveness: confirmed
---

## Problema
Error al acceder a grupo de usuarios 48 en Groot para editar administradores.

## Solución Aplicada
Se removieron dos usuarios del listado de admins (HOP Places y Ariel Chavez). Estos no deberían ser meli users. Al removerlos del grupo de administradores, el acceso a la pantalla se restableció correctamente.

## Señales para identificar este patrón
- "error al acceder a grupo de usuarios" / "erro ao acessar grupo de usuários" / "error accessing user group"
- "editar administradores en Groot" / "editar administradores no Groot" / "edit administrators in Groot"
- URL de grupo de usuarios (`/tools/auth/users-group/<id>`)
- Usuarios no-MELI en el listado de admins de un grupo

## Tags
grupo de usuarios, administradores, error acceso, usuarios no-meli, user group, admins
