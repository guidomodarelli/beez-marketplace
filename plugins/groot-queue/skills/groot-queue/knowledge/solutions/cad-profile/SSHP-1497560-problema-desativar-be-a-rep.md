---
ticket: SSHP-1497560
category: cad-profile
summary: Be a Rep activo bloquea modificaciones de accesos/warehouse — remover tag de Be a Rep y restaurar configuración original
date: 2026-07-01
effectiveness: confirmed
---

## Problema
Usuario no puede incluir accesos del warehouse SSP51 porque tiene Be a Rep activo. El Be a Rep bloquea modificaciones en el perfil del usuario mientras está vigente.

## Solución Aplicada
Se removió el tag de Be a Rep y se volvió a la configuración original del usuario. Tras la remoción, el gestor pudo realizar las modificaciones de accesos necesarias.

## Señales para identificar este patrón
- "não consegue incluir acessos" / "no puede incluir accesos" / "cannot add access" + Be a Rep activo
- "desativar Be a Rep" / "desactivar Be a Rep" / "deactivate Be a Rep" para poder modificar usuario
- Usuario con Be a Rep vigente que necesita cambios en warehouse/accesos/atributos
- Gestor reporta que no puede editar al usuario mientras tiene Be a Rep

## Tags
be a rep, desactivar, accesos bloqueados, warehouse, modificar usuario, tag be a rep
