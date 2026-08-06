---
ticket: SSHP-1497560
category: cad-profile
summary: Be a Rep activo bloquea modificaciones de accesos/warehouse — antecedente de estado bloqueado
date: 2026-07-01
effectiveness: confirmed
verdict: VALIDO_GROOT
---

## Problema
Usuario no puede incluir accesos del warehouse SSP51 porque tiene Be a Rep activo. El Be a Rep bloquea modificaciones en el perfil del usuario mientras está vigente.

## Antecedente Histórico — No Reproducible Por Soporte
El caso histórico reportó una intervención sobre el estado de Be a Rep antes de continuar una modificación. No reutilizarlo como instrucción para remover estados, restaurar configuración ni definir accesos de una persona. Ante un caso similar, verificar si existe falla sistémica, reunir evidencia técnica y escalarla; la gestión de accesos corresponde al responsable de gestión de usuarios de la operación.

## Señales para identificar este patrón
- "não consegue incluir acessos" / "no puede incluir accesos" / "cannot add access" + Be a Rep activo
- "desativar Be a Rep" / "desactivar Be a Rep" / "deactivate Be a Rep" para poder modificar usuario
- Usuario con Be a Rep vigente que necesita cambios en warehouse/accesos/atributos
- Gestor reporta que no puede editar al usuario mientras tiene Be a Rep

## Tags
be a rep, desactivar, accesos bloqueados, warehouse, modificar usuario, tag be a rep
