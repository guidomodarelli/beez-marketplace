---
ticket: SSHP-1408403
category: link-unlink-account
summary: No se podía vincular la cuenta de dbautistadel (se quedaba cargando). El usuario ya tenía una cuenta vinculada con Groot ID 2067001. Ticket rechazado.
date: 2026-04-14
effectiveness: confirmed
verdict: DESCARTAR
---

## Problema
Al intentar vincular la cuenta del usuario dbautistadel, el proceso quedaba cargando indefinidamente sin completarse. El solicitante reportó que la vinculación no podía finalizarse.

## Causa Raiz
El usuario dbautistadel ya tenía una cuenta vinculada en Groot (Groot ID: 2067001). El sistema no permitía vincular una nueva cuenta porque ya existía una vinculación activa para ese usuario.

## Solucion Aplicada
El ticket fue rechazado al identificar que el usuario ya tenía una cuenta vinculada. Se informó al solicitante que dbautistadel ya contaba con Groot ID 2067001 vinculado, por lo que no era necesaria ni posible una nueva vinculación sin antes desvincular la cuenta existente.

## Tags
vinculacion, link-account, groot-id, dbautistadel, cuenta-ya-vinculada, rechazado, 2067001
