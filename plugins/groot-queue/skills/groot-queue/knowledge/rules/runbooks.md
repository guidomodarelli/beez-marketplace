---
name: groot-queue-runbooks
description: Runbooks procedurales por categoría de problema para la cola Groot (SSHP). Cada runbook contiene el paso-a-paso estándar para diagnosticar y resolver incidentes. Alimenta el subcomando /groot-queue solve y sirve de guía para la atención diaria.
---

# Runbooks — Cola Groot (SSHP)

> Conocimiento de dominio extraído del SKILL.md original. Se mantiene versionado junto a `triage-rules.md` y `solutions/` para que la base crezca en un solo lugar.
>
> Uso: el subcomando `/groot-queue solve SSHP-XXXXXX` debe:
> 1. Identificar la categoría del ticket.
> 2. Buscar aquí el runbook de esa categoría.
> 3. Complementar con casos concretos de `solutions/<categoria>/`.

---

## Contexto de Groot

**Groot** es el sistema de gestión de usuarios de shipping en Mercado Libre (`shipping-users-mgmt-api`). Administra:
- Usuarios de warehouse/fulfillment (reps, team leaders, managers)
- Roles y permisos (BISO roles via Kraken)
- Atributos de usuario (warehouse, facility, crossdocking, etc.)
- Jerarquía organizacional (líder directo, gestión)
- Badges y credenciales
- Labour Share entre sites

**Sistemas relacionados**:
- **Kraken**: Auth/roles — gestiona permisos y roles de usuario
- **Alfred**: Operaciones masivas (CSV upload para cambios bulk)
- **WMS** (wms.adminml.com): Sistema de warehouse management
- **LMS**: Labour Management System
- **Kioske**: Terminal de autoservicio para reps
- **xtools**: Herramientas de autogestión de perfil
- **SSFF**: Shipping Fulfillment Frontend

**Error codes conocidos del sistema**:
- `user_rollback_error`: Error haciendo rollback de cambios en usuario
- `remove_attribute_error`: Error removiendo atributos
- `update_attribute_error`: Error actualizando atributos
- `update_manager_error`: Error actualizando manager/líder
- `update_user_groups_error`: Error actualizando grupos de usuario
- `update_roles_error`: Error actualizando roles

---

## Runbook: Jerarquía/Líder

**Problema típico**: Un usuario no puede cambiar el líder de otro en Groot, o el cambio no persiste.

**Pasos**:
1. Verificar la jerarquía actual del usuario en Groot admin (https://envios.adminml.com/tools/auth/users/shared)
2. Verificar si el usuario target aparece "debajo de sí mismo" (bug de referencia circular conocido)
3. Si hay referencia circular → requiere corrección en BD, escalar a equipo dev Groot
4. Si el botón de cambio de gestión está deshabilitado → verificar que el usuario que intenta hacer el cambio tiene permisos de TL o superior
5. Si el cambio se hace pero revierte → verificar si hay un proceso de Rostering o Alfred Massive sobrescribiendo el cambio
6. **Escalación**: Crear bug para equipo dev Groot con el error observado, URL y screenshot si aplica

---

## Runbook: Warehouse/Site

**Problema típico**: Usuario vinculado a warehouse incorrecto, necesita ser movido.

**Pasos**:
1. Verificar el warehouse actual del usuario en Groot admin
2. Verificar si el usuario tiene operaciones en curso en el warehouse actual (bolhas activas, tareas pendientes)
3. Editar el usuario en Groot → cambiar campo warehouse/facility
4. Si la edición no guarda → verificar si hay conflicto con datos de Rostering
5. Si es un cambio masivo de múltiples usuarios → usar Alfred Massive con CSV
6. **Escalación**: Si Groot no permite el cambio, escalar a equipo dev con el error específico

---

## Runbook: Roles/Permisos

**Problema típico**: Usuario no puede acceder a una función, le falta un rol, o no puede asignar rol a otros.

**Pasos**:
1. Verificar los roles actuales del usuario en Groot admin
2. Verificar en Kraken si el rol existe y está activo para el site del usuario
3. Si el usuario completó learning pero no ve el rol → verificar que el learning está vinculado al rol correcto en la config
4. Si aparece "NO AUTORIZADO" → verificar que el usuario tiene el rol necesario Y que el site es correcto
5. Para remoción masiva de roles (BISO): el sistema tiene un threshold del 20% — si se remueve más del 20% de la población de un rol en 24h, requiere aprobación manual del owner del rol via Alfred Orchestrator
6. **Escalación**: Si el rol existe en Kraken pero no aparece en Groot, escalar a dev Groot

---

## Runbook: Visibilidad Usuario

**Problema típico**: Usuario no ve bolhas (bubbles) en WMS, o no aparece en LMS/Kioske.

**Pasos**:
1. Verificar que el usuario está activo en Groot (no deshabilitado)
2. Verificar que tiene el warehouse correcto asignado
3. Verificar que tiene los roles necesarios para la operación (ej: rol de picking para ver bolha de picking)
4. Verificar que el site tiene la operación habilitada
5. Si es "tela branca" → posible problema de sesión, pedir que limpie cache/reloguee
6. **Escalación**: Si todo está correcto pero sigue sin ver → escalar con screenshot y datos del usuario

---

## Runbook: Atributos

**Problema típico**: No se puede agregar/remover un atributo, o el cambio no persiste.

**Pasos**:
1. Verificar el atributo actual del usuario en Groot admin
2. Intentar editar → si da error "alteração não salva" verificar si hay validación de negocio bloqueando
3. Si es atributo crossdocking → verificar que el site soporta crossdocking
4. Si es cambio masivo → usar Alfred Massive
5. **Escalación**: Con el error code específico (`update_attribute_error`)

---

## Runbook: Labour Share

**Problema típico**: Labour share se ejecuta pero no impacta al usuario.

**Pasos**:
1. Verificar que el labour share se creó correctamente en Groot
2. Verificar que el usuario target está en el site de destino
3. Verificar que el labour share no expiró (tiene fecha de fin)
4. Verificar que el usuario tiene los roles necesarios en el site de destino
5. **Escalación**: Si el labour share se completa exitosamente pero el usuario no se mueve, escalar a dev Groot con los IDs del labour share

---

## Runbook: CAD/Perfil

**Problema típico**: CAD no aparece en autogestión, perfil incorrecto en xtools.

**Pasos**:
0. **Si el síntoma es "no aparece CAD/atributo para seleccionar en autogestión (xtools)"** → verificar primero si el **líder directo** del usuario tiene el CAD/atributo asignado. Si **no** lo tiene → aplicar `R-DESC-03` de `triage-rules.md` (descartar), porque la autogestión solo ofrece valores que el líder ya posee. No es un bug del sistema.
1. Verificar el CAD del usuario en Groot admin
2. Si el CAD es incorrecto → editar en Groot → campo facility/site
3. Si no aparece en autogestión (xtools) **y el líder sí tiene el atributo** → verificar que el usuario tiene acceso a xtools y que el CAD está sincronizado
4. Si el perfil muestra datos de otro site → posible dato stale, verificar última sincronización
5. **Escalación**: Si el dato en Groot es correcto pero xtools muestra otro, escalar como bug de sincronización

---

## Runbook: Error UI Groot

**Problema típico**: La UI de Groot muestra error, se queda cargando, o un botón desapareció.

**Pasos**:
1. Verificar si el error es reproducible con otro usuario/browser
2. Si el botón desapareció → posible cambio de permisos reciente, verificar roles del usuario que opera
3. Si "se queda cargando" → posible timeout de backend, verificar si el usuario target tiene muchos datos
4. **Escalación**: Siempre escalar errores de UI con URL completa y screenshot

---

## Runbook: Vincular/Desvincular

**Problema típico**: Usuario aparece como "cuenta Meli" en vez de cuenta ext_, o no puede cambiar contraseña.

**Pasos**:
1. Verificar el tipo de cuenta en Groot (Meli vs ext_)
2. Si aparece como cuenta Meli pero debería ser ext_ → posible error de vinculación en el onboarding
3. Para cambio de contraseña → el usuario debe usar el flujo de autogestión, no Groot
4. Si el usuario no puede acceder a autogestión → verificar que tiene CAD activo
5. **Escalación**: Problemas de vinculación de cuenta requieren IAM Soporte (`57102`)

---

## Mantenimiento

- Cuando un runbook se actualice (nuevo paso, escalación distinta, URL cambia), editar este archivo directamente.
- Los **casos concretos** que aporten información nueva deben ir también a `solutions/<categoria>/` con su frontmatter.
- Si un patrón recurrente justifica una regla de triage transversal → agregarlo a `triage-rules.md` y referenciarlo desde el runbook correspondiente (como se hizo con `R-DESC-03` en CAD/Perfil).
