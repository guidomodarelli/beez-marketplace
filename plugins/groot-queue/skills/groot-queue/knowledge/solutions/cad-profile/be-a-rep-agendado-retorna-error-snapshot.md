---
ticket: SSHP-1400938
category: cad-profile
summary: Usuario lbaqueiro: Be a Rep queda agendado pero retorna ERROR. Mismo bug del deploy 30/03. Solución: deploy de corrección en el componente snapshot de usuario.
date: 2026-04-04
effectiveness: confirmed
---

## Problema
El usuario lbaqueiro intentó usar el proceso "Be a Rep" (CAD) y la solicitud quedaba en estado "agendado" pero finalmente retornaba un ERROR. El usuario no podía completar el proceso de complemento de turno.

## Causa Raiz
Mismo bug identificado en SSHP-1401334: el deploy del 30/03 afectó el componente de snapshot de usuario, que es el responsable de persistir los cambios de configuración. Al fallar el snapshot, el proceso de "Be a Rep" quedaba en estado intermedio y terminaba en error.

## Solucion Aplicada
Se desplegó la corrección en el componente snapshot de usuario, resolviendo el bug introducido por el deploy del 30/03. Tras el fix, el proceso de "Be a Rep" funcionó correctamente para lbaqueiro y demás usuarios afectados.

## Tags
be-a-rep, cad, lbaqueiro, snapshot, deploy-bug, error-estado-agendado
