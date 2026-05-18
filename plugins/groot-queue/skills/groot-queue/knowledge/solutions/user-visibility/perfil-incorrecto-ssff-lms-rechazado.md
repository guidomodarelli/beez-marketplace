---
ticket: SSHP-1409214
category: user-visibility
summary: Usuario shsousa con perfil errado en SSFF/LMS: aparecía como Analista de Control Tower en SP02 en lugar de su rol real de TL de Outbound en SP14. Rechazado por Groot ya que es gestión de usuarios.
date: 2026-04-14
effectiveness: confirmed
derived_to: Equipo Gestión de Usuarios
---

## Problema
La usuaria shsousa (Groot ID 459300) reportó que su perfil en SSFF y en el sistema LMS mostraba información incorrecta: aparecía como Analista de Control Tower en SP02, cuando en realidad era TL de Outbound en SP14. Adicionalmente, el perfil indicaba "TL de Returns", lo que tampoco era correcto. El problema fue detectado en `https://xtools.adminml.com/tools/profile/mercadoenvios`.

## Causa Raiz
El origen fue una inconsistencia en los datos de perfil (facility, función y departamento) en SSFF/Groot. Los datos de perfil de la usuaria no estaban alineados con su posición real. La gestión de estos campos no corresponde al equipo de soporte de Groot/Kraken.

## Solucion Aplicada
El ticket fue derivado al equipo de gestión de usuarios. El equipo de LMS lo redirigió a Groot, y desde Groot se rechazó la solicitud indicando que la gestión de atributos de perfil (facility, función, departamento) debe realizarse a través del equipo de gestión de usuarios de la operación, no mediante soporte Groot/Kraken.

## API Calls Involucrados
- xtools perfil: `xtools.adminml.com/tools/profile/mercadoenvios`

## Tags
ssff, lms, perfil-incorrecto, shsousa, facility, funcion, departamento, rechazado, gestion-usuarios, sp14, sp02
