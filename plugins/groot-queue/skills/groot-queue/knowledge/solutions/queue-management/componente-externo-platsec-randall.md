---
ticket: SSHP-1412840
category: queue-management
summary: No se puede cambiar SVC en Logistics Package Management — el componente es externo a Groot/Kraken, owner es Platsec/Randall
date: 2026-04-21
effectiveness: confirmed
verdict: DERIVAR
destination: Helpdesk IA
rule: R-DER-04
source: Francisco Gonzalez (Slack group DM 2026-04-21)
---

## Problema

User reporta que en `https://envios.adminml.com/logistics/package-management` el selector de SVC aparece pero no guarda el cambio (de SHP2 a SHP1). Afecta sólo a algunos usuarios. LDAP afectado: `yaarroyo`.

## Causa Raíz

El componente de package-management (SVC selector) **no pertenece a Groot/Kraken**. El owner es el equipo de **Platsec/Randall**. En Groot/Kraken el usuario está correctamente configurado — el problema vive en el componente externo.

## Solución Aplicada

1. Se verificó en Groot/Kraken que el usuario `yaarroyo` tiene la configuración correcta.
2. Se confirmó que la falla está en el componente de package-management, fuera del alcance de Groot.
3. Se derivó el ticket a **Helpdesk IA** para que lo ruteen al owner correcto (Platsec/Randall).

**Respuesta al cliente / reasignación (copy validado por Gocho):**
> Hola, el error corresponde a un componente externo a nuestro soporte Groot/Kraken. Esto debe ser revisado con el equipo de Platsec/Randall owner del componente. El usuario está correctamente configurado en Kraken.

## Señales para identificar este patrón

- URL afectada está en `envios.adminml.com/logistics/...` o menciona módulos de logistics/package management / app nav / Shield.
- Síntoma: "no guarda el cambio", "boton no responde", "se cierra la solicitud automáticamente".
- En Groot/Kraken el usuario está correctamente configurado.
- El problema afecta sólo a algunos usuarios sin patrón claro de permisos Groot.

## Verificación previa antes de derivar

Validar roles/facility/atributos del usuario en Groot. Si todo luce bien en Groot/Kraken → derivar a Helpdesk IA / Platsec. Si falta un rol Groot → **no aplica** R-DER-04; reclasificar como `VALIDO_GROOT`.

## Canal de contacto directo

Para escalación rápida desde Slack: `#help-authz-internal-admins` (canal de plataforma para reportar issues de authz/appnav/Shield).

## Tags

`platsec` `randall` `helpdesk-ia` `componente-externo` `package-management` `derivacion` `R-DER-04`
