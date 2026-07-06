---
ticket: SSHP-1413000
category: role-permission
summary: Usuario sin acceso a la sección de notificaciones de chat interno en xtools (pidgey). Derivado al equipo de chat interno; el ticket llegó mal asignado a Groot/WoWChat.
date: 2026-04-18
effectiveness: confirmed
rule: R-DER-13
derived_to: Equipo Chat Interno (Pidgey)
destination: Equipo Chat Interno (Pidgey)
verdict: DERIVAR
---

## Problema
Un usuario reportó que al acceder a `https://xtools.adminml.com/tools/pidgey/notifications/messages` (notificaciones de chat interno/burbuja outbound) recibía el error "NO AUTORIZADO". La funcionalidad de chat interno no estaba disponible para ese usuario.

## Causa Raiz
El usuario no contaba con los permisos necesarios para acceder a la sección de notificaciones de chat interno de xtools (Pidgey). El ticket llegó mal asignado, ya que no corresponde ni a Groot ni a WoWChat.

## Solucion Aplicada
El ticket fue derivado al equipo responsable del chat interno (Pidgey). El equipo de Groot confirmó que el inconveniente no era de su dominio y lo redirigió al equipo correspondiente para su atención.

## API Calls Involucrados
- xtools: `xtools.adminml.com/tools/pidgey/notifications/messages`

## Tags
xtools, pidgey, no-autorizado, chat-interno, outbound-bubble, derivacion, mal-asignado
