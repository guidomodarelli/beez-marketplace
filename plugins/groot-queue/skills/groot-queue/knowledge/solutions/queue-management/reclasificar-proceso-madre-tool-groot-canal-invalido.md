---
ticket: SSHP-1403550
category: queue-management
summary: Reclasificar proceso madre bulky_sorting en tool Groot — tema llevado por Leticia Alvarez; canal correcto es #help-authz-internal-admins
date: 2026-04-21
effectiveness: confirmed
verdict: DESCARTAR
subverdict: Rechazado — canal inválido
rule: R-DER-05
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

En la tool de usuarios de Groot (`https://envios.adminml.com/tools/auth/users/shared/9311`) el proceso madre `bulky_sorting` (soporte de armado de HU y clasificación bulky) aparece asignable dentro del área madre **Inventory - FBM**, pero debería estar bajo **Outbound - FBM**. Afecta a todos los sites. Impacto: la categoría es incorrecta y confunde la asignación.

## Causa Raíz

El tema ya está siendo trabajado por **Leticia Alvarez**. Se trata de un error puntual cuyo owner real es un equipo externo (**platsec**), igual que los issues del **app nav**. El ticket llegó a la cola Groot pero **el canal correcto para reportar este tipo de problema es Slack, no la ticketera**.

## Solución Aplicada

1. Se identificó que el caso ya tiene dueño (Leticia Alvarez) y equipo (platsec).
2. Se rechazó el ticket por canal inválido.

**Respuesta al cliente (copy validado por Gocho):**
> Hola, este tema lo está llevando Leticia Alvarez. Tiene que ver con un error puntual que depende de equipos de platsec, al igual que con los issues del app nav. El canal de Slack de plataforma para reportar sería `#help-authz-internal-admins`.

## Señales para identificar este patrón

- Tema relacionado con la **clasificación/taxonomía del proceso madre** en la tool Groot.
- Issue de **app nav** en `envios.adminml.com`.
- Owner real está fuera del dominio Groot (platsec, authz).

## Canal correcto

`#help-authz-internal-admins` — canal de Slack de plataforma para reportar issues de authz / app nav / procesos madre en la tool de usuarios.

## Verificación previa antes de rechazar

Si el reporte es de un error de **asignación real** en Groot (ej. "asigno el rol y no se guarda") → **no aplica** R-DER-05, mantener en Groot. Esta regla sólo aplica a issues de **clasificación/taxonomía** de la tool.

## Tags

`platsec` `app-nav` `authz-admins` `canal-invalido` `bulky-sorting` `proceso-madre` `rechazo` `R-DER-05`
