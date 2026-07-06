---
ticket: SSHP-1410959
category: cad-profile
summary: No aparece CAD/atributo para seleccionar en autogestión (xtools profile) porque el líder directo no tiene el valor asignado. Comportamiento esperado — se descarta.
date: 2026-04-21
effectiveness: confirmed
rule: R-DESC-03
verdict: DESCARTAR
---

## Problema
Usuario reporta que en la autogestión de su perfil (`https://xtools.adminml.com/tools/profile/mercadoenvios`) **no aparece ningún CAD / valor de atributo** disponible para seleccionar. Como consecuencia, no puede cambiar su CAD para acceder a herramientas del site de destino (ej. LMS).

Contexto típico: usuario de un site visitando temporalmente otro site (ej. un usuario de BRBA02 visitando BRBA01) que necesita cambiar el CAD para trabajar desde la operación visitada.

## Causa Raiz
En el flujo de autogestión, un usuario **solo puede solicitar valores de atributo que su líder directo ya tenga asignados**. Si el líder no tiene el valor → la UI no ofrece la opción en el dropdown. No es un bug del sistema, es comportamiento esperado.

## Solucion Aplicada
Se descarta el ticket (`Won't Do`). Para que el usuario pueda solicitar el valor, el líder directo debe tener primero el atributo asignado; una vez que lo tenga, el usuario podrá solicitarlo desde autogestión.

**Comentario sugerido al reportero:**
> "Hola, su líder no tiene el valor de atributo asignado, es por esto que el usuario no puede solicitar el valor de atributo desde autogestión. Para habilitarlo, el líder directo debe tener primero el atributo asignado."

## Señales para identificar este patrón
- Síntoma en UI: "no aparece CAD" / "não aparece CAD" / "no puedo seleccionar facility" / dropdown vacío en autogestión.
- URL afectada: `xtools.adminml.com/tools/profile/mercadoenvios`.
- Contexto: usuario visitando otro site / cambio de CAD requerido.
- Verificación previa: inspeccionar al líder directo en Groot admin → confirmar que no tiene el CAD/atributo objetivo. Si el líder **sí** lo tiene, no aplica este patrón y hay que seguir el runbook normal de CAD/Perfil.

## Tags
cad, autogestion, xtools, lider, atributo, descartar, won't-do, jerarquia-requisito
