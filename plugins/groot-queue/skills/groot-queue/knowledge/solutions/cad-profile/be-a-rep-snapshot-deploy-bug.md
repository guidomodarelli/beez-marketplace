---
tickets: SSHP-1400938, SSHP-1401302, SSHP-1401334
category: cad-profile
summary: Be a Rep falla / queda agendado con error / bolha no sube — bug en componente snapshot introducido por deploy del 30/03/2026
date: 2026-04-04
effectiveness: confirmed
verdict: FIX_APLICADO
rule: R-FIX-01
---

## Problema

Tres tickets con síntomas distintos del **mismo bug**:

- **SSHP-1400938** (`lbaqueiro`): Be a Rep queda en estado "agendado" y retorna ERROR al finalizar.
- **SSHP-1401302**: Be a Rep aprobado pero la bolha no sube (proceso no se completa).
- **SSHP-1401334**: Proceso Be a Rep falla masivamente para múltiples usuarios en distintos sites (~4 horas de afectación).

## Causa Raíz

El deploy del **30/03/2026** introdujo un defecto en el **componente de snapshot de usuario** — el responsable de persistir los cambios de configuración. Al fallar el snapshot:
- El proceso de Be a Rep queda en estado intermedio y termina en error, o
- Los cambios aprobados no se persisten y la bolha no sube.

## Solución Aplicada

Fix desplegado el mismo día (30/03/2026): corrección en el componente de snapshot de usuario. Tras el fix, Be a Rep funcionó correctamente para todos los usuarios afectados.

> ⚠️ Este bug ya está resuelto. Si aparece un ticket con síntomas similares **posterior al 30/03/2026**, verificar si el snapshot del usuario está fallando antes de escalar — puede ser una regresión nueva.

## Señales para identificar este patrón

- Be a Rep queda en estado "agendado" y termina en ERROR.
- Be a Rep aprobado pero la bolha no sube.
- Falla masiva de agendado de Be a Rep en múltiples sites simultáneamente.
- Coincide temporalmente con un deploy reciente al componente de snapshot.

## Tags

be-a-rep, snapshot, deploy-bug, bolha, agendado, error, masivo, fix-aplicado, R-FIX-01
