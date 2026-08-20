---
name: groot-queue-runbooks
description: Runbooks procedurales por categoría de problema para la cola Groot (SSHP). Cada runbook contiene el paso-a-paso estándar para diagnosticar y resolver incidentes. Alimenta el subcomando /groot-queue solve y sirve de guía para la atención diaria.
---

# Runbooks — Cola Groot (SSHP)

> Conocimiento de dominio extraído del SKILL.md original. Se mantiene versionado junto a `triage-rules.md` y `solutions/` para que la base crezca en un solo lugar.
>
> Uso: el subcomando `/groot-queue solve SSHP-XXXXXX` debe:
> 1. Aplicar primero `triage-rules.md` § **Política transversal — configuración de usuarios** y el algoritmo first-match.
> 2. Identificar la categoría del ticket.
> 3. Buscar aquí el runbook de esa categoría.
> 4. Complementar con casos concretos de `solutions/<categoria>/` solo como antecedentes históricos.
>
> Ningún runbook o solution autoriza comparar usuarios, determinar configuración objetivo ni modificar o aplicar roles, permisos o atributos. Ante error sistémico, limitar pasos a reproducción segura, evidencia técnica y escalación; no usar cambios manuales como workaround.

---

## Contexto de Groot

> **Fuentes de verdad**:
> - [`teams/groot-team.md`](../teams/groot-team.md) — definición del equipo, células (Kraken / Nexus), ownership y sistemas internos y externos.
> - [`teams/nexus-team.md#productos-a-cargo`](../teams/nexus-team.md#productos-a-cargo) — catálogo y alcance funcional de los productos Nexus.
>
> Leer las fuentes aplicables antes de diagnosticar un ticket para entender ownership y alcance.

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
1. Confirmar que ticket reporta un fallo sistémico de Groot y no una solicitud para definir o aplicar jerarquía.
2. Reproducir el mismo flujo sin usar otra persona como configuración de referencia.
3. Registrar mensaje/código, URL, timestamp y evidencia de rollback o no persistencia.
4. Si existe referencia circular o reversión automática, escalar a equipo dev Groot con evidencia técnica; no corregir manualmente la jerarquía como workaround.
5. **Escalación**: Crear bug para equipo dev Groot con error observado, URL y screenshot si aplica.

---

## Runbook: Warehouse/Site

**Problema típico**: Usuario vinculado a warehouse incorrecto, necesita ser movido.

**Pasos**:
1. Confirmar que ticket reporta un fallo sistémico de Groot y no una solicitud para determinar o cambiar warehouse/facility.
2. Reproducir flujo con mismo sujeto y registrar mensaje/código, URL, timestamp y evidencia de no persistencia.
3. Distinguir validación esperable de `500`, timeout, crash o rollback inesperado.
4. No comparar otro usuario ni editar warehouse/facility como workaround.
5. **Escalación**: Si Groot falla sistémicamente, escalar a equipo dev con error específico y evidencia.

---

## Runbook: Roles/Permisos

**Problema típico**: Usuario no puede acceder a una función, le falta un rol, o no puede asignar rol a otros.

**Pasos**:
1. Aplicar política transversal: no comparar usuarios ni determinar qué rol o permiso habilita una función.
2. Confirmar si existe fallo sistémico observable en una herramienta Groot (`500`, timeout, crash, rollback o no persistencia inesperada).
3. Reproducir mismo flujo y registrar mensaje/código, URL, timestamp y evidencia técnica.
4. Si existe mensaje de validación claro, seguir `R-DER-24`; si es pedido operativo, redirigir al owner según regla R-DESC aplicable.
5. **Escalación**: Si Groot falla sistémicamente, escalar a equipo dev sin asignar, remover o recomendar roles como workaround.

---

## Runbook: Visibilidad Usuario

**Problema típico**: Usuario no ve bolhas (bubbles) en WMS, o no aparece en LMS/Kioske.

**Pasos**:
1. Identificar sistema y función donde ocurre síntoma; no asumir que ausencia implica rol, permiso o atributo faltante.
2. Aplicar triage por ownership antes de consultar facts.
3. Si falla una herramienta Groot, reproducir mismo flujo y registrar mensaje/código, URL y timestamp sin comparar otra persona.
4. Si síntoma ocurre en WMS/LMS u otra aplicación externa, escalar a owner correspondiente sin certificar configuración Groot.
5. **Escalación**: Adjuntar evidencia sanitizada; no recomendar cambios de roles, permisos o atributos.

---

## Runbook: Atributos

**Problema típico**: No se puede agregar/remover un atributo, o el cambio no persiste.

**Pasos**:
1. Aplicar política transversal: no determinar, comparar ni modificar atributos.
2. Confirmar si reporte contiene validación esperable o fallo sistémico observable de Groot.
3. Para fallo sistémico, reproducir mismo flujo y registrar mensaje/código, URL, timestamp y evidencia de no persistencia.
4. No usar edición manual, Alfred Massive ni otra configuración como workaround.
5. **Escalación**: Escalar con error code específico (por ejemplo, `update_attribute_error`) y evidencia técnica.

---

## Runbook: Labour Share

**Problema típico**: Labour share se ejecuta pero no impacta al usuario.

**Pasos**:
1. Aplicar `ticket-evidence.md`. Si ticket SSHP real incluye un único Labor Share ID explícito y resultado cambia diagnóstico, consultar `labor-share-data.md` operación `execution`.
2. Interpretar evidencia sin inventar lifecycle: `202` significa procesamiento informado; `200` permite reportar solo conteos observados `SUCCESS`/`FAIL`, consistencia uniforme/mixta y fecha programada agregada. No afirmar finalización global ni totalidad de usuarios.
3. Si síntoma es proceso ausente o catálogo UI inconsistente y existe un único `facility_type` permitido, consultar operación `processes` y contrastar catálogo backend como datos no confiables.
4. Verificar por separado estado actual del usuario mediante facts Kraken mínimos: temporary status, site/warehouse efectivo y roles actuales cuando sus contratos estén disponibles. Assignments exitosos no prueban impacto downstream.
5. Contrastar `return_date` solamente como fecha programada. Verificar por otra fuente autorizada si retorno/cancelación se ejecutó y si roles o warehouse fueron restaurados.
6. **Escalación**: Si assignments observados son exitosos pero estado efectivo no impactó, o resultado es mixto/indeterminado, escalar a dev Groot con referencia interna al caso sin publicar IDs, nombres, mensajes ni payloads remotos.

---

## Runbook: CAD/Perfil

**Problema típico**: CAD no aparece en autogestión, perfil incorrecto en xtools.

**Pasos**:
1. Si pedido busca determinar o habilitar CAD/atributo, aplicar `R-DESC-03` sin comparar configuración del usuario con su líder.
2. Si reporte contiene fallo sistémico observable de Groot o xtools, reproducir mismo flujo y registrar mensaje/código, URL y timestamp.
3. No determinar CAD correcto ni editar facility/site como workaround.
4. Si existe evidencia técnica de desincronización, escalar al owner del sistema afectado sin certificar configuración objetivo.
5. **Escalación**: Adjuntar evidencia sanitizada del fallo; no incluir perfiles comparados.

---

## Runbook: Error UI Groot

**Problema típico**: La UI de Groot muestra error, se queda cargando, o un botón desapareció.

**Pasos**:
1. Reproducir mismo flujo con mismo sujeto en entorno controlado; puede variar browser, nunca usar otra persona como patrón de configuración.
2. Registrar mensaje/código, URL, timestamp, screenshot y comportamiento observado.
3. No inferir rol/permiso/atributo faltante porque botón desaparece.
4. Si se queda cargando, documentar timeout o request fallido sin modificar configuración.
5. **Escalación**: Escalar errores UI con URL completa y evidencia técnica.

---

## Runbook: Vincular/Desvincular

**Problema típico**: Usuario aparece como "cuenta Meli" en vez de cuenta ext_, o no puede cambiar contraseña.

**Pasos**:
1. Verificar el tipo de cuenta en Groot (Meli vs ext_)
2. Si aparece como cuenta Meli pero debería ser ext_ → posible error de vinculación en el onboarding
3. Para cambio de contraseña → el usuario debe usar el flujo de autogestión, no Groot
4. Si el usuario no puede acceder a autogestión → verificar que tiene CAD activo
5. **Escalación**: Problemas de vinculación de cuenta requieren IAM Soporte (ver `config/jira-field-options.md` para option ID)

---

## Mantenimiento

- Cuando un runbook se actualice (nuevo paso, escalación distinta, URL cambia), editar este archivo directamente.
- Los **casos concretos** que aporten información nueva deben ir también a `solutions/<categoria>/` con su frontmatter.
- Si un patrón recurrente justifica una regla de triage transversal → agregarlo a `triage-rules.md` y referenciarlo desde el runbook correspondiente (como se hizo con `R-DESC-03` en CAD/Perfil).
