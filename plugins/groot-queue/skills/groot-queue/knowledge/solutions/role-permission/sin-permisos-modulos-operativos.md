---
ticket: SSHP-1458905
category: role-permission
summary: Usuario problem solver sin permisos para modulos operativos INB/OUT en ARBA01; la asignacion de roles corresponde a gestion de usuarios de la operacion
date: 2026-06-12
effectiveness: confirmed
verdict: DESCARTAR
rule: R-DESC-05
source: Jira SSHP-1458905
---

## Problema

Un usuario con funcion de problem solver en ARBA01 no podia acceder a modulos operativos necesarios para operar INB/OUT: Stage in, Movimiento de stock, labeling, seguimiento de unidades y reimpresion de shipping label.

El ticket solicitaba revisar permisos para habilitar esos accesos. La ocurrencia fue reportada desde el 2026-05-20 a las 22:00.

## Causa Raiz

No se identifico una falla tecnica de Groot/Kraken. El caso correspondia a asignacion de roles/permisos operativos para modulos especificos, responsabilidad de los equipos de gestion de usuarios de la operacion.

## Solucion Aplicada

1. Se clasifico el caso como solicitud de permisos/roles para modulos operativos especificos.
2. Se informo al requester que Groot/Kraken Soporte no realiza asignaciones de roles.
3. Se indico que la gestion debe ser realizada por los equipos de gestion de usuarios de la operacion.
4. El ticket se resolvio como `Won't Do`.

## Senales para identificar este patron

- ES: "usuario sin permisos para acceder a modulos operativos INB/OUT", "sin permisos para Stage in", "sin permisos para Movimiento de stock", "sin permisos para labeling", "sin permisos para seguimiento de unidades", "sin permisos para reimpresion de shipping label".
- PT: "usuario sem permissao para acessar modulos operacionais INB/OUT", "usuário sem permissão para acessar módulos operacionais INB/OUT", "sem permissao para Stage in", "sem permissão para Stage in", "sem permissao para Movimento de estoque", "sem permissão para Movimento de estoque", "sem permissao para labeling", "sem permissão para labeling", "sem permissao para acompanhamento de unidades", "sem permissão para acompanhamento de unidades", "sem permissao para reimpressao de shipping label", "sem permissão para reimpressão de shipping label".
- EN: "user without permissions to access INB/OUT operational modules", "no permissions for Stage in", "no permissions for Stock movement", "no permissions for labeling", "no permissions for unit tracking", "no permissions for shipping label reprint".
- Contexto tipico: caso asociado a un rol operativo especifico, por ejemplo problem solver; el pedido apunta a asignar o corregir roles de operacion, no a un error tecnico de autenticacion o UI.

## Verificacion previa antes de descartar

Validar que el usuario pueda autenticarse y que el problema sea solo de permisos/roles sobre modulos especificos. Si falta un rol base conocido que Groot administra o hay un error tecnico reproducible de Groot, reclasificar como `VALIDO_GROOT`.

## Tags

`sin-permisos` `modulos-operativos` `inb-out` `stage-in` `movimiento-stock` `labeling` `shipping-label` `problem-solver` `gestion-usuarios-operacion` `descarte` `R-DESC-05`
