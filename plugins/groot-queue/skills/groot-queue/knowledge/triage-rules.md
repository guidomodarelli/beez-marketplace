---
name: groot-queue-triage-rules
description: Reglas de triage para determinar si un ticket de la cola Groot (SSHP) debe descartarse, derivarse a otro equipo o ya tiene fix aplicado. Alimentada a partir del seguimiento histórico de la ticketera y de la resolución diaria de tickets.
---

# Reglas de Triage — Cola Groot (SSHP)

> Fuente original: "Seguimiento Ticketera Jira Groot.xlsx" (snapshot 2025-11 / 2025-12).
> Actualizada con casos del día a día del equipo (ver `solutions/` para ejemplos concretos).
> Uso: consultar en `/groot-queue list` y `/groot-queue classify` para marcar cada ticket con un **Veredicto de Triage** antes de mostrarlo.

---

## Veredictos posibles

| Veredicto | Indicador | Significado |
|-----------|-----------|-------------|
| `DESCARTAR` | `⛔` | No corresponde a Groot Soporte. Cerrar con comentario plantilla. |
| `DERIVAR` | `➡️` | Corresponde a otro equipo. Reasignar con comentario. |
| `FIX_APLICADO` | `✅` | Causa raíz ya corregida por dev Groot. Cerrar confirmando al reporter. |
| `VALIDO_GROOT` | `🟢` | Pertenece al alcance de Groot Soporte. Seguir runbook normal. |
| `REVISAR_MANUAL` | `❓` | No matchea ninguna regla. Requiere lectura humana. |

Para `list` agregar columna **Triage**. Para `classify` agregar una sección extra al inicio: **"Tickets candidatos a derivar/descartar"** con los matches de reglas `DESCARTAR` y `DERIVAR`.

---

## Reglas `DESCARTAR`

### R-DESC-01 — Derivación a destiempo desde SMO / Opex Full
- **Señales**:
  - Ticket originalmente asignado a **Opex Full** o **SMO** y derivado a cola Groot.
  - Aging original > 15 días al llegar a Groot.
  - Fecha de derivación posterior al desarme de primer nivel Opex Full (28-oct-2025).
- **Razón**: Opex Full ya no actúa como primer nivel; el ticket llegó fuera de ventana.
- **Acción**: Cerrar como `Won't Do` / `Cancelled`.
- **Comentario sugerido**:
  > "Hola, lamentamos el tiempo de respuesta de este ticket, sin embargo el mismo fue derivado a nuestra cola a destiempo. En caso de seguir necesitando soporte, volver a abrir el ticket con las evidencias del caso."

### R-DESC-02 — Solicitud de asignación de roles a un usuario
- **Señales**:
  - Summary/description contiene: "asignar rol", "asignación de roles", "darle rol", "agregar rol a usuario".
  - Cuenta **sin** tag azul de "no es cuenta de envíos" (es decir, es de shipping).
  - No hay problema técnico: el usuario simplemente pide que le asignen un rol.
- **Razón**: Groot Soporte **no** hace asignación de roles; eso lo hace el gestor de usuarios de la operación. Groot atiende **solo errores sistémicos**.
- **Verificación previa**: Si el requester reporta que intentó asignar el rol y la herramienta **da error / no guarda** → reclasificar como `VALIDO_GROOT` (error sistémico, runbook Roles/Permisos). Mismo criterio de escape que `R-DESC-09`.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Desde Groot Soporte no hacemos asignación de roles a usuarios. Para esto debe comunicarse con el gestor de usuarios de su operación."

### R-DESC-03 — Autogestión de CAD/atributo sin opciones porque el líder no tiene el valor
- **Señales**:
  - Usuario reporta que en autogestión (xtools profile) **no le aparece** un CAD / facility / atributo para seleccionar.
  - Contexto típico: usuario visitando otro site (ej. BRBA02 visitando BRBA01) y no puede cambiar el CAD para acceder a LMS / herramientas del site de destino.
  - URL típica: `https://xtools.adminml.com/tools/profile/mercadoenvios`.
- **Razón**: En autogestión un usuario solo puede solicitar valores de atributo que **su líder directo tenga asignados**. Si el líder no tiene el valor → la opción no aparece en la UI. No es un bug de Groot.
- **Verificación previa**: Inspeccionar al líder directo del usuario en Groot admin y confirmar que **no** tiene el CAD/atributo en cuestión. Si el líder sí lo tiene → no aplica esta regla (reclasificar como `VALIDO_GROOT`).
- **Acción**: Cerrar como `Won't Do` / descartado.
- **Comentario sugerido**:
  > "Hola, su líder no tiene el valor de atributo asignado, es por esto que el usuario no puede solicitar el valor de atributo desde autogestión. Para habilitarlo, el líder directo debe tener primero el atributo asignado."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1410959 (2026-04-21). Ver `solutions/cad-profile/autogestion-cad-lider-sin-atributo.md`.

### R-DESC-04 — Cambio de líder / supervisor directo sin error técnico → autogestionable por el líder actual
- **Señales**:
  - Summary/description: "cambio de supervisor directo", "cambiar líder a X usuarios", "trocar líder", "mover reps a supervisor Y".
  - El requester **no** reporta error técnico — pide que nosotros ejecutemos la operación.
  - Hay una lista clara de usuarios a mover y un nuevo líder target.
- **Razón**: Groot Soporte atiende **errores sistémicos**. El cambio de líder/supervisor es operación que el líder actual puede ejecutar por autogestión desde la tool de Groot admin.
- **Verificación previa**: Confirmar que no hay error técnico. Si el requester dice "intenté y me da error" → reclasificar como `VALIDO_GROOT` (runbook Jerarquía/Líder).
- **Excepción — líder actual inactivo**: Si el líder actual está **inactivo / desvinculado / dado de baja / fuera de la empresa / sin acceso a la tool**, la autogestión no es posible. En ese caso **no aplica** esta regla → reclasificar como `VALIDO_GROOT` (runbook Jerarquía/Líder) y Groot ejecuta el cambio.
  - Señales de la excepción: el requester menciona explícitamente que el líder "ya no está", "fue dado de baja", "está inactivo", "no trabaja más", "no tiene acceso", "salió de la empresa", "não está mais", "foi desligado", "não tem acesso", "is no longer active", "was offboarded", "doesn't have access", "left the company", "was terminated", "no longer works here".
  - Verificación: confirmar en Groot admin que el líder actual figura como inactivo / sin acceso antes de reclasificar.
  - **Límite**: si Groot admin muestra al líder como **activo**, mantener veredicto `DESCARTAR` y solicitar al requester que lo contacte directamente para ejecutar la operación.
- **Acción**: Cerrar como `Won't Do` redirigiendo al requester a la tool de autogestión.
- **Comentario sugerido**:
  > "Hola, desde soporte Groot sólo atendemos errores sistémicos. Este tipo de solicitud la pueden hacer los líderes actuales a través de https://envios.adminml.com/tools/auth/users/shared?active=true usando la opción de cambio de líder."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1415474 (2026-04-21). Ver `solutions/hierarchy-leader/cambio-supervisor-directo-autogestion-lider.md`. Excepción "líder inactivo" agregada el 2026-05-27.

### R-DESC-05 — Error "no autorizado" en módulo específico → Groot no mapea rol↔funcionalidad
- **Señales**:
  - Error "no autorizado" / "nao autorizado" / "not authorized" al entrar a una URL/módulo puntual.
  - El usuario **sí** logra loguearse (auth OK).
  - Afecta a uno o pocos usuarios; el requester pregunta "qué rol necesita" o "qué permiso falta".
- **Razón**: Groot/Kraken Soporte no es dueño del mapeo "funcionalidad ↔ rol requerido". Esa correspondencia la define el gestor de usuarios de la operación del site.
- **Verificación previa**: Revisar que el usuario tenga los roles **base** de su función (Rep, TL, PS, etc.). Si falta un rol base que ya tenía → reclasificar como `VALIDO_GROOT`.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola, desde soporte Groot/Kraken no somos responsables de saber cuál es el permiso/rol que habilita una funcionalidad. Esto debe ser dirigido a los equipos de gestión de usuarios de su operación para que determinen si hay un rol faltante o si requiere ajustes en los roles actuales."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1416994 (2026-04-21). Ver `solutions/role-permission/no-autorizado-modulo-logistics.md`.

### R-DESC-06 — Rep sin clock-in físico → valor de atributo se obtiene dinámicamente al hacer clock-in
- **Señales**:
  - Usuario afectado es **rep** (no TL ni manager).
  - Summary: "vinculada al CAD errado", "no puede solicitar bolha", "CAD incorrecto en Groot".
  - El reporte es **antes** de que el rep haya hecho clock-in en el site deseado.
- **Razón**: Los reps **no** tienen CAD/atributo fijo. Los valores se asignan dinámicamente a partir del **clock-in físico** diario. Antes del clock-in, el sistema no conoce el facility de trabajo.
- **Verificación previa**: Consultar al rep en Groot admin tras un clock-in en el site objetivo. Si el valor aparece correcto → descartar. Si **ya hizo clock-in** y aun así falta → reclasificar como `VALIDO_GROOT` (posible bug de sincronización).
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola, el usuario al ser un rep obtiene los valores a partir de los clock-in físicos. Vemos que el usuario después de hacer el clock-in tiene asignado el valor que requiere."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1409680 (2026-04-21). Ver `solutions/user-visibility/rep-sin-clock-in-no-ve-bolha.md`.

### R-DESC-07 — Reps sin acceso a bolha/función pero ya ubicados en el facility correcto → gestor de usuarios de la operación
- **Señales**:
  - Summary: "reps no ven bolha", "nao visualizam", "não aparece no login", "sem acceso a función X".
  - Verificación: los usuarios **están** correctamente ubicados en el facility mencionado en Groot.
  - No hay error técnico en la edición/guardado del usuario.
- **Razón**: Si la ubicación en Groot es correcta, el acceso a una función puntual del site lo gestiona el equipo de usuarios de la operación, no Groot Soporte.
- **Verificación previa**: Confirmar en Groot admin que los usuarios reportados **están** en el facility indicado. Si **no** lo están → reclasificar como `VALIDO_GROOT` (runbook Warehouse/Site).
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola, los usuarios están ubicados en el facility mencionado. En caso de no tener acceso a alguna función, esto debe ser revisado con el equipo de gestión de usuarios de su operación."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1409554 (2026-04-21). Ver `solutions/user-visibility/reps-no-ven-bolha-inventario.md`.

### R-DESC-08 — Solicitud de rol por Learning Hub / Training Hub completado
- **Señales**:
  - Summary/description menciona: "completó learning", "learning hub", "training hub", "asistió al entrenamiento", "terminó capacitación".
  - El usuario pide la asignación de un rol específico post-capacitación.
  - En Groot no hay error técnico (la tool funciona).
- **Razón**: La correspondencia "learning completado → rol asignado" es competencia del gestor de usuarios de la operación, no de Groot.
- **Verificación previa**: Confirmar que no hay error al intentar asignar el rol en Groot. Si la tool falla al asignar → reclasificar como `VALIDO_GROOT`.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola, las solicitudes de roles a partir de asistencia en Learning Hub / Training Hub son atendidas por el equipo de gestión de usuarios de la operación. Desde aquí no damos soporte a este tipo de solicitudes."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1412472 (2026-04-21). Ver `solutions/role-permission/rol-learning-hub-asignacion-gestion-usuarios-operacion.md`.

### R-DESC-09 — Remoción manual de rol sin error técnico → gestor de usuarios de la operación
- **Señales**:
  - Summary/description: "remover rol", "quitar rol", "desasignar rol" a un operario puntual.
  - No hay error técnico reportado.
  - El requester no es gestor de usuarios de operación; simplemente pide que Groot ejecute la remoción.
- **Razón**: Groot Soporte no ejecuta asignación ni remoción manual de roles (complementa `R-DESC-02`). Esas operaciones las realiza el gestor de usuarios del site desde la propia herramienta Groot admin.
- **Verificación previa**: Si el requester dice "intenté remover y me da error" → reclasificar como `VALIDO_GROOT` (runbook Roles/Permisos).
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Esta solicitud debe ser enviada al equipo de gestión de usuario de su operación. Desde soporte Groot/Kraken no hacemos este tipo de asignaciones o remociones."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1418490 (2026-04-21). Ver `solutions/queue-management/remover-rol-gestion-usuarios-operacion.md`.

### R-DESC-10 — Solicitud de asignación/cambio de valor de atributo sin error sistémico → gestor de usuarios de la operación
- **Señales**:
  - Summary/description pide **asignar / agregar / cambiar / quitar un valor de atributo** (CAD, facility, atributo operativo) a uno o pocos usuarios. Variantes de texto: ES "asignar atributo", "agregar atributo", "cambiar CAD", "asignar facility", "falta el atributo X", "asignar valor de atributo"; PT "atribuir atributo", "adicionar atributo", "trocar CAD", "atribuir facility", "falta o atributo", "valor de atributo faltando"; EN "assign attribute", "add attribute", "change CAD", "assign facility", "set attribute value", "missing attribute".
  - **No** hay error técnico/sistémico: la herramienta de Groot funciona; el requester solo pide que Groot ejecute la asignación/cambio.
  - El requester no es gestor de usuarios de la operación; pide que Groot haga la operación por él.
- **Razón**: Groot Soporte atiende **solo errores sistémicos**. La asignación o cambio de valores de atributo sin error de la herramienta la realiza el gestor de usuarios de la operación (mismo criterio que `R-DESC-02` / `R-DESC-09` para roles, extendido a atributos). Si la solicitud es solo "ejecutá esta acción porque al usuario le falta el atributo", el canal no es la ticketera de Groot.
- **Verificación previa**: Si el requester reporta que intentó la operación y la tool **da error / no guarda** → reclasificar como `VALIDO_GROOT` (error sistémico). Distinto de `R-DESC-03` (el valor no aparece en autogestión porque el líder no lo tiene), `R-DESC-06` (rep sin clock-in) y `R-DESC-07` (reps ya ubicados en el facility): si matchea una de esas señales específicas, usar esa regla.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola, desde soporte Groot/Kraken solo atendemos errores sistémicos. La asignación o cambio de valores de atributo (CAD, facility, etc.) sin un error de la herramienta debe gestionarla el equipo de gestión de usuarios de su operación."
- **Fuente**: Sync Groot Queue, criterio general de triage roles/atributos, 2026-06-02.

### R-DESC-11 — Incidencia en sistema externo a Groot (ej. HCM Rostering) → falso positivo, rechazar
- **Señales**:
  - ES: "no pudo crear usuario en HCM Rostering", "error al dar de alta en HCM Rostering", "fallo en Rostering al crear colaborador".
  - PT: "nao foi possivel criar usuario no HCM Rostering", "erro no HCM Rostering ao criar usuario", "nao consegue criar novato no Rostering".
  - EN: "cannot create employee in HCM Rostering", "failed to create user in HCM Rostering", "HCM Rostering error creating new hire".
  - Patrón general: el problema reportado ocurre en un sistema distinto de Groot/Kraken/xtools/Alfred y no hay error en ninguna herramienta de Groot.
- **Razón**: HCM Rostering (y sistemas similares de gestión de plantilla/schedule externos) no pertenecen al dominio de Groot. Los tickets sobre fallas en sistemas externos son falsos positivos para esta cola.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Incidencia rechazada por IT / Incidente rejeitado pelo IT."
- **Fuente**: groot-queue:analyze-history, SSHP-1460997, 2026-05-26.

### R-DESC-12 — Cambio automático de jerarquía en LMS por sync de Rostering → funcionalidad esperada, no bug de Groot
- **Señales**:
  - ES: "alteración indevida de jerarquía en LMS", "equipo movido automáticamente sin solicitud", "cambio automático de supervisor en LMS sin aceptación".
  - PT: "alteração indevida de hierarquia no LMS", "equipe movida automaticamente para supervisor sem solicitação", "mudança indevida de hierarquia", "sem solicitacao manual nem aceite".
  - EN: "unexpected hierarchy change in LMS", "team moved automatically without request", "hierarchy changed automatically without manual approval".
  - Contexto típico: el reporte menciona que la jerarquía cambió "automáticamente" (sin solicitud manual), vinculado al CAD/site (ej. CAD SP10), y el TL/equipo aparece bajo un nuevo supervisor sin que nadie lo haya pedido.
- **Razón**: El sync de Rostering hacia LMS puede reasignar jerarquías automáticamente como parte del flujo estándar de la integración. No es un bug de Groot — es funcionalidad existente del sistema.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Incidencia rechazada por IT / Incidente rejeitado pelo IT."
  > *(Nota: el comentario real del equipo no estaba disponible en la API al minar este ticket; se recomienda confirmar el copy validado con Francisco Gonzalez antes de usar.)*
- **Fuente**: groot-queue:analyze-history, SSHP-1454812, 2026-05-26.

---

## Reglas `DERIVAR`

### R-DER-01 — Cuenta no marcada como shipping ("no puedo habilitar al usuario" / tag azul) → IAM Soporte
- **Señales**:
  - La cuenta tiene el **tag azul** de "no es cuenta de envíos" / "conta não é de envios".
  - El admin/gestor, al acceder al perfil en la tool de Groot (`envios.adminml.com/tools/auth/users/shared/...`), ve que **no puede habilitar al usuario** porque **no pertenece a envíos / a las remesas** y la cuenta figura desactivada. Variantes de texto: ES "no pertenece a Mercado Envío" / "no pertenece a envíos" / "no es cuenta de envíos"; PT "(usuário) não pertence às remessas" / "nao pertence as remessas" / "conta não é de envios"; EN "(user) does not belong to shipping" / "is not a shipping account" / "account is not part of shipping".
  - Síntomas típicos: no aparece la opción de deshabilitar, opciones de Groot bloqueadas para esa cuenta, no se le habilitan flujos de shipping, cuenta **desactivada** que piden **reactivar** / "dejar el rep disponible sistémicamente".
- **Razón**: La cuenta no está marcada como shipping; IAM debe setear el flag correcto para que Groot pueda habilitar/gestionar al usuario desde el ABM.
- **Verificación previa**:
  - Distinto de **R-DER-10** (el mensaje "no perteneces a envíos" lo ve el **usuario final** al crear/desbloquear su cuenta). Acá el bloqueo lo ve el **admin/gestor** al intentar habilitar la cuenta desde el ABM de Groot.
  - El usuario afectado puede ser `ext_*` (externo): eso **no** lo convierte en **R-DER-06**, que exige que el `ext_*` aparezca reconocido como **cuenta Meli** en Kioske/TOTEM. Si la señal es "no pertenece a remesas / cuenta desactivada en la tool de Groot", aplica R-DER-01.
- **Acción**: Derivar a **IAM Soporte**.
- **Comentario sugerido** (nota interna — la postea `/groot-queue:derive`):
  > "Hola, les derivamos este ticket para que nos ayuden marcando la cuenta con el flag de shipping. Una vez marcada, el usuario queda habilitado y podemos gestionarla desde nuestro ABM (tools de Groot). ¡Gracias!"
- **Fuente**: SSHP-1471443, 2026-06-02. Señal "no puedo habilitar / no pertenece a envíos/remesas" + comentario interno unificados en esta regla a partir de este ticket. Verificado contra el ticket real (PT: "usuario nao pertence as remessas", cuenta desactivada, usuario `ext_beatrnog`): ya resuelto y asignado a IAM Soporte (`sup_iamcommerce_01`), lo que confirma la derivación.

### R-DER-02 — Problemas de navegación App Nav → SMO (Randall + Process Dev Full)
- **Señales**:
  - Summary/description menciona: "app nav", "navegación del app", "no me aparecen apps", "navegação app".
  - No es configuración de usuario en Groot; es un problema de la shell/nav.
- **Razón**: El equipo de **Randall** (SMO) está trabajando con Process Dev Full en un walk-around.
- **Acción**: Derivar a **SMO** (squad Randall).
- **Comentario sugerido**:
  > "Hola, derivo este caso porque no es un problema de configuración. El equipo de Randall ya está trabajando en conjunto con Process Dev Full para bajar un walk-around."

### R-DER-03 — Vincular/desvincular cuenta o cambio de contraseña → IAM Commerce
- **Señales**:
  - Aparece como "cuenta Meli" y debería ser `ext_`, o al revés.
  - Pide cambio de contraseña que requiere flujo de autogestión.
- **Razón**: Problemas de vinculación de cuenta los maneja **IAM Commerce** (`sup_iamcommerce`).
- **Acción**: Derivar a IAM Commerce.
- **Nota**: Este runbook también existe en `runbooks.md` (Runbook: Vincular/Desvincular). La regla lo formaliza como derivación directa cuando la señal es clara.

### R-DER-04 — Componente externo a Groot/Kraken (Platsec / Randall) → Helpdesk IA
- **Señales**:
  - URL afectada en `envios.adminml.com/logistics/...` o módulos de package-management / app nav / Shield.
  - Síntoma: "no guarda el cambio", "botón no responde", "se cierra la solicitud automáticamente".
  - En Groot/Kraken el usuario luce **correctamente configurado**.
  - El problema afecta a algunos usuarios sin patrón claro de permisos Groot.
- **Razón**: El componente (p.ej. SVC selector en package-management) pertenece a Platsec/Randall, no a Groot/Kraken. Groot no puede arreglarlo.
- **Verificación previa**: Revisar roles/facility/atributos del usuario en Groot. Si todo está correcto → derivar. Si falta un rol Groot → `VALIDO_GROOT`.
- **Acción**: Derivar a **Helpdesk IA** (ruteo al owner correcto).
- **Comentario sugerido**:
  > "Hola, el error corresponde a un componente externo a nuestro soporte Groot/Kraken. Esto debe ser revisado con el equipo de Platsec/Randall owner del componente. El usuario está correctamente configurado en Kraken."
- **Canal directo Slack**: `#help-authz-internal-admins`.
- **Fuente**: Francisco Gonzalez, ticket SSHP-1412840 (2026-04-21). Ver `solutions/queue-management/componente-externo-platsec-randall.md`.

### R-DER-05 — Issues de taxonomía/clasificación en tool Groot o app nav → canal Slack #help-authz-internal-admins
- **Señales**:
  - Tema de **clasificación/taxonomía** del proceso madre en la tool Groot (ej. "proceso bulky_sorting está bajo Inventory-FBM y debería estar en Outbound-FBM").
  - Issues de **app nav** en `envios.adminml.com`.
  - Owner real está fuera del dominio Groot (platsec, authz).
- **Razón**: Estos issues ya son tratados por platsec/Leticia Alvarez; la ticketera no es el canal correcto, es Slack.
- **Verificación previa**: Si el reporte es un error de asignación real en Groot ("asigno el rol y no se guarda") → **no aplica**, mantener en Groot. Esta regla sólo cubre issues de **clasificación/taxonomía** o de app nav.
- **Acción**: Rechazar el ticket por canal inválido y redirigir al canal de Slack de plataforma.
- **Comentario sugerido**:
  > "Hola, este tema depende de equipos de platsec al igual que los issues del app nav. El canal de Slack de plataforma para reportar sería #help-authz-internal-admins."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1403550 (2026-04-21). Ver `solutions/queue-management/reclasificar-proceso-madre-tool-groot-canal-invalido.md`.

### R-DER-06 — Usuario externo (ext_) reconocido como cuenta Meli en Kioske/TOTEM → IAM Soporte
- **Señales**:
  - LDAP del usuario es `ext_*` (colaborador externo).
  - Aparece como **cuenta Meli** en Kioske u otro flujo donde debería ser EXT.
  - No puede cambiar contraseña vía TOTEM de autogestión.
  - En Groot sí figura como externo, pero otros sistemas no reconocen el flag.
- **Razón**: El flag de identidad (interno/externo) que leen el Kioske y el TOTEM lo gestiona IAM, no Groot.
- **Verificación previa**: Confirmar que en Groot el LDAP `ext_*` aparece efectivamente como externo. Si en Groot aparece como Meli → primero corregir en Groot (runbook Vincular/Desvincular) antes de derivar.
- **Acción**: Derivar a **IAM Soporte**.
- **Comentario sugerido**:
  > "Usuario externo que es reconocido como usuario interno y por esta razón no puede ser gestionado por el TOTEM de autogestión de las operaciones."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1412206 (2026-04-21). Ver `solutions/link-unlink-account/ext-reconocido-como-cuenta-meli-en-kioske.md`.

### R-DER-07 — Flujos en Shield (herramienta externa) → IAM Soporte
- **Señales**:
  - La herramienta afectada es **Shield**.
  - Flujo típico: cambio de líder para colaboradores **externos** (`ext_*`).
  - Síntoma: "el chamado se cierra solo", "la solicitud se cierra automáticamente al abrirla".
- **Razón**: Shield es herramienta de IAM, no de Groot. Comportamiento y bugs de Shield los atiende **IAM Soporte** (`sup_iamcommerce_01`).
- **Verificación previa**: Si la solicitud puede resolverse desde la tool de Groot (`envios.adminml.com/tools/auth/users/shared`) → **no aplica**, redirigir al líder vía `R-DESC-04`.
- **Acción**: Derivar a **IAM Soporte**.
- **Comentario sugerido**:
  > "Herramientas de Shield que no damos soporte. Derivar a IAM Soporte."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1415340 (2026-04-21). Ver `solutions/queue-management/shield-cierra-solicitud-cambio-lider-ext.md`.

### R-DER-08 — Cambio de nombre de usuario → IAM Soporte
- **Señales**:
  - Summary/description: "cambio de nombre", "cambiar nombre del usuario", "modificar nombre", "trocar nome do usuário", "nombre incorrecto en la cuenta".
  - El pedido afecta al **dato de identidad** (first name / last name) de la cuenta, no a atributos operativos de Groot.
- **Razón**: El nombre del usuario lo gestiona IAM (la fuente de verdad es SSFF / la identidad corporativa). Groot solo consume ese dato y no puede modificarlo.
- **Verificación previa**: Si el pedido es cambiar **rol**, **atributo** o **facility** (no nombre) → no aplica, reclasificar a la categoría que corresponda.
- **Acción**: Derivar a **IAM Soporte**.
- **Comentario sugerido**:
  > "Hola, el cambio de nombre del usuario lo gestiona IAM Soporte. Desde Groot no podemos modificar datos de identidad de la cuenta — derivamos para que continúen con el flujo correspondiente."
- **Fuente**: Sync Groot Queue, 2026-05-18 (Francisco Gonzalez + equipo).

### R-DER-09 — Tax ID inválido → IAM Soporte
- **Señales**:
  - Summary/description: "tax id inválido", "tax id invalido", "CUIT inválido", "CPF inválido", "documento inválido", "error al validar tax id".
  - Puede aparecer en **frontend** (un usuario reporta) o en **bulk/masivo** (lote falla por tax id).
- **Razón**: La validación de tax id ocurre del lado de IAM (identidad). Groot no es dueño del flujo de validación de documentos.
- **Verificación previa**: Si el error es de **otra validación** (rol faltante, líder NULL, atributo) → no aplica.
- **Acción**: Derivar a **IAM Soporte**.
- **Comentario sugerido**:
  > "Hola, el error de tax id inválido corresponde a la validación de identidad gestionada por IAM Soporte. Derivamos para que continúen con el ajuste del documento."
- **Fuente**: Sync Groot Queue, 2026-05-18 (Francisco Gonzalez + equipo). Caso identificado como candidato a automatización (5-10% del volumen).

### R-DER-10 — "No perteneces a envíos" al crear / desbloquear cuenta → IAM Soporte
- **Señales**:
  - El usuario final ve un mensaje al intentar **crear cuenta** o **desbloquearla** que indica: "no perteneces a envíos", "no pertence a envios", "esta cuenta no es de shipping", "no podés acceder a esta operación".
  - El usuario **no puede conocer su LDAP** porque el flujo lo bloquea antes (la cuenta no figura como shipping).
  - Distinto de **R-DER-01** (tag azul visible al admin en Groot): acá el problema lo ve el **usuario final** desde el frontend de autogestión / creación de cuenta.
- **Razón**: El flag de "pertenece a envíos" lo setea IAM. Sin ese flag, los flujos de creación/desbloqueo bloquean al usuario antes de que pueda completar el proceso. Groot no puede setear ese flag.
- **Verificación previa**: Si la cuenta **sí** está marcada como shipping en Groot pero falla otro flujo → no aplica, reclasificar.
- **Acción**: Derivar a **IAM Soporte**.
- **Comentario sugerido**:
  > "Hola, el mensaje 'no perteneces a envíos' indica que la cuenta no está marcada como shipping a nivel de IAM. Derivamos para que IAM Soporte ajuste el flag y el usuario pueda completar el flujo."
- **Fuente**: Sync Groot Queue, 2026-05-18 (Francisco Gonzalez + equipo). Caso identificado como candidato a automatización (5-10% del volumen).

### R-DER-11 — Error "Tax_id has already been used" al crear colaborador (documento ya en uso) → IAM Soporte
- **Señales**:
  - Al crear un nuevo colaborador / dar de alta una cuenta en Groot, el sistema devuelve el error literal **"Tax_id has already been used"** (string en inglés, aparece igual en tickets ES/PT/EN), acompañado de "No pudimos continuar con la creación de la cuenta" y el LDAP que no se genera.
  - Variantes de texto en summary/description: ES "tax id ya utilizado" / "tax id ya fue usado" / "documento ya registrado" / "CUIT ya utilizado" / "no puedo crear el colaborador"; PT "tax_id já utilizado" / "tax_id already used" / "CPF já cadastrado" / "não consegue criar novo colaborador"; EN "Tax_id has already been used" / "tax id already used" / "cannot create new collaborator".
  - Contexto típico: alta de un **new hire** cuyo CPF/CUIT/documento ya quedó asociado a otra identidad/LDAP previa.
- **Razón**: El tax_id (CPF/CUIT/documento) ya está vinculado a otra identidad/LDAP a nivel IAM. Groot no es dueño del flujo de identidad ni puede resolver duplicados de documento; solo IAM puede verificar y liberar/vincular el tax_id existente.
- **Verificación previa**: Distinto de **R-DER-09** (tax id *inválido* — falla de formato/validación). Acá el documento es **válido** pero **ya está en uso**. Si el error es de formato/validación → R-DER-09. Si la falla es por otra validación (rol, líder NULL, atributo) → no aplica.
- **Acción**: Derivar a **IAM Soporte**.
- **Comentario sugerido** (nota interna — la postea `/groot-queue:derive`):
  > "Hola chicos, derivamos este caso para su analisis, no podemos resolver este ticket desde Groot"
- **Fuente**: SSHP-1457833, 2026-06-02. Verificado contra el ticket real (summary PT "Nao consegue criar novo colaborador no Groot; erro tax_id already used", description EN con error literal "Tax_id has already been used", alta de un new hire): status `Resolved` y assignee `sup_iamcommerce_01` (IAM Soporte), lo que confirma la derivación.

---

## Reglas `FIX_APLICADO`

> Estos casos ya tienen un fix en producción. Si aparece un ticket que matchea la señal, se debe **verificar con una query** y si el síntoma ya no reproduce → cerrar confirmando.

### R-FIX-01 — Be a Rep / Labour Share — Devolución de roles
- **Señales**:
  - Problema con devolución de roles en Be a Rep y/o Labour Share.
  - Usuarios con muchos valores asignados.
- **Causa raíz (histórica)**: El componente de **snapshot de usuario** fallaba para usuarios con muchos valores asignados.
- **Fix**: Aplicado (fix al componente de snapshot de usuario, fines de oct 2025).
- **Verificación**:
  ```sql
  select *
  from user_scheduled_snapshot
  where groot_id = '<groot_id>'
  order by created_at desc;
  ```
  Revisar que el último snapshot esté OK (sin error, posterior a fecha del fix).
- **Acción si el snapshot está OK**: Cerrar como `Done`.
- **Comentario sugerido**:
  > "Hola, nos disculpamos por las dificultades ocurridas con la herramienta de Be a Rep / Labour Share. Desde el 28 de octubre hicimos ajustes a la tool para mejorar la performance de la devolución de roles. El problema ya debería estar resuelto; si persiste, por favor reabrí el ticket con evidencia reciente."

### R-FIX-02 — Usuarios con Líder en NULL
- **Señales**:
  - Usuario no puede editarse.
  - Al inspeccionar en Groot admin, el líder aparece vacío / NULL.
- **Causa raíz (histórica)**: Inconsistencia en el campo líder (heredada de SSFF).
- **Fix**: Workaround — agregar el líder de SSFF para desbloquear; investigación de causa raíz en curso.
- **Acción**: Si el líder ya está seteado por el fix → confirmar al reporter que ya puede editar.
- **Comentario sugerido**:
  > "Se resolvió la inconsistencia en el líder y grupo del usuario. Ya deberías poder editar la cuenta normalmente."

### R-FIX-03 — Alta masiva Alfred: proceso de envío de resultados trabado
- **Señales**:
  - Alta masiva ejecutada desde **Alfred** que "no completa" o "deja usuarios sin alta".
  - La ejecución parece haber corrido pero Alfred no marca el resultado como completado.
  - Afecta lotes grandes de usuarios (decenas).
  - Fecha del reporte: cercano o posterior a 2026-04-21.
- **Causa raíz (histórica)**: El proceso interno que enviaba los **resultados** de la ejecución masiva a Alfred estaba trabado — por eso el mensaje de completitud nunca llegaba y la alta aparentaba no haber impactado.
- **Fix**: Aplicado el 2026-04-21 (equipo dev Groot desbloqueó el proceso de envío de resultados).
- **Verificación**:
  - Confirmar que la alta masiva reportada es **posterior** al 2026-04-21.
  - Revisar que los usuarios afectados estén correctamente dados de alta en Groot tras el desbloqueo.
  - Si la falla ocurrió **antes** del fix → puede requerir reenvío manual de los resultados; coordinar con dev Groot antes de cerrar.
- **Acción si está confirmado**: Cerrar como `Done` con comentario explicativo.
- **Comentario sugerido**:
  > "Se detectó que un proceso que envía los resultados a Alfred estaba trabado y era la razón por la que el mensaje no llegaba. Ya fue desbloqueado; si persiste, por favor reabrí con evidencia reciente."
- **Fuente**: Francisco Gonzalez, tickets SSHP-1415407 y SSHP-1423184 (2026-04-21). Ver `solutions/queue-management/alfred-bulk-proceso-envio-resultados-trabado.md`.

---

## Algoritmo de triage (para `list` y `classify`)

Para cada ticket abierto, evaluar en este orden y asignar el **primer** veredicto que matchee:

1. **R-FIX-01** → si summary/description cita "Be a Rep" o "Labour Share" + "devolución de roles" / "no devuelve" / "no impacta".
2. **R-FIX-02** → si summary/description cita "líder NULL" / "sin líder" / "manager vacío" + reporta que no puede editar usuario.
3. **R-FIX-03** → si menciona "alta masiva Alfred", "bulk Alfred", "alta en Alfred no completa", "usuarios sin alta tras ejecución masiva" y la fecha del reporte es cercana o posterior al 2026-04-21.
4. **R-DER-06** → si LDAP `ext_*` aparece como **cuenta Meli** en Kioske/TOTEM y no puede cambiar contraseña.
5. **R-DER-07** → si la herramienta afectada es **Shield** y el flujo es cambio de líder para colaboradores externos.
6. **R-DER-09** → si el reporte menciona "tax id inválido", "CUIT inválido", "CPF inválido", "documento inválido" (frontend o bulk).
7. **R-DER-11** → si al crear/dar de alta un colaborador el error es "Tax_id has already been used" / ES "tax id ya utilizado" / PT "tax_id já utilizado" (documento **válido** pero ya en uso; distinto de R-DER-09 que es tax id *inválido*).
8. **R-DER-10** → si el usuario final ve un mensaje tipo "no perteneces a envíos" / "no pertence a envios" al intentar crear cuenta o desbloquearla (y por eso no puede conocer su LDAP).
9. **R-DER-08** → si el pedido es **cambio de nombre** del usuario (first/last name), sin error técnico de Groot.
10. **R-DER-04** → si la URL afectada es `envios.adminml.com/logistics/...` / **package-management** / app nav / componente externo y el usuario está correctamente configurado en Groot/Kraken.
11. **R-DER-05** → si el tema es de **clasificación/taxonomía** de proceso madre en la tool Groot o issues de **app nav** (no un error real de Groot).
12. **R-DER-01** → si menciona "tag azul", "no es cuenta de envíos", "conta não é de envios", "sin opción de deshabilitar", o el admin (accediendo al perfil en la tool de Groot) ve que "no puede habilitar al usuario" porque "no pertenece a envíos / no pertenece a Mercado Envío" / PT "não pertence às remessas" / "nao pertence as remessas" / EN "does not belong to shipping" / "not a shipping account" (cuenta desactivada que piden reactivar; IAM debe ajustar el flag de shipping).
13. **R-DER-02** → si menciona "app nav", "navegación del app", "navegação" sin señal de R-DER-05.
14. **R-DER-03** → si menciona "vincular cuenta", "desvincular", "cuenta Meli vs ext_", "cambio de contraseña" (sin señal de Kioske/TOTEM que apunte a R-DER-06).
15. **R-DESC-03** → si el usuario reporta que en xtools / autogestión "no aparece CAD" / "não aparece CAD" / "no puedo seleccionar facility" + contexto de visitar otro site.
16. **R-DESC-06** → si el usuario afectado es **rep** y el reporte es previo al clock-in físico del día en el site objetivo.
17. **R-DESC-07** → si reps no ven una bolha/función y la verificación confirma que **están** en el facility correcto.
18. **R-DESC-08** → si el requester menciona "learning completado", "training hub", "learning hub" y pide asignación de rol post-capacitación.
19. **R-DESC-04** → si es pedido de **cambio de líder / supervisor directo** sin error técnico (lista de usuarios a mover + nuevo líder).
20. **R-DESC-09** → si pide **remover** un rol a un operario y no hay error técnico reportado.
21. **R-DESC-05** → si hay error "no autorizado" / "not authorized" en un módulo/URL específico y el usuario **sí** logra loguearse.
22. **R-DESC-02** → si es solicitud de **asignación de rol** a usuario (sin error técnico) y la cuenta **no** tiene tag azul.
23. **R-DESC-10** → si pide **asignar / cambiar / quitar un valor de atributo** (CAD, facility, atributo operativo) sin error técnico, y no matchea R-DESC-03 / R-DESC-06 / R-DESC-07.
24. **R-DESC-01** → si proviene de **Opex Full / SMO** y fue derivado fuera de ventana (>15 días de aging al llegar a Groot, posterior a 2025-10-28).
25. **R-DESC-11** → si el problema ocurre en un sistema externo a Groot/Kraken (ej. HCM Rostering) y no hay error en ninguna herramienta de Groot.
26. **R-DESC-12** → si el reporte es una jerarquía que cambió automáticamente en LMS (sin solicitud manual) y el contexto apunta a un sync de Rostering.
27. Si ninguna regla matchea → `VALIDO_GROOT` (si la categoría del ticket está en los runbooks de `runbooks.md`) o `REVISAR_MANUAL` (si no hay categoría clara).

---

## Cambios en `list` y `classify`

### `list` — columna extra

```
| # | Key | Summary | Status | Priority | Assignee | Edad | Triage |
```

Donde `Triage` es el indicador (`⛔ DESCARTAR`, `➡️ DERIVAR→<Equipo>`, `✅ FIX_APLICADO`, `🟢 VALIDO_GROOT`, `❓ REVISAR_MANUAL`).

### `classify` — sección extra al principio

```markdown
## 🚨 Acciones de triage recomendadas

### ⛔ Descartar (N tickets)
| Key | Summary | Regla | Comentario sugerido |

### ➡️ Derivar a otro equipo (N tickets)
| Key | Summary | Equipo destino | Regla |

### ✅ Fix ya aplicado — verificar y cerrar (N tickets)
| Key | Summary | Regla | Query de verificación |
```

Luego continuar con la clasificación por categoría habitual.

---

## Mantenimiento

- Cada vez que el equipo (Francisco, Julián, etc.) deje en los threads de Slack una acción sobre un ticket (`Descartar`, `Derivar a otro equipo`, `Fix aplicado`), **actualizar este archivo** agregando una nueva regla `R-DESC-XX`, `R-DER-XX` o `R-FIX-XX`.
- Paralelamente, archivar el caso concreto en `solutions/<categoria>/` con el formato de la knowledge base (ver `README.md`).
- Mantener el **comentario sugerido** tal cual lo escribió el equipo (es copy validado para responder al usuario). Si es necesario normalizar tildes o puntuación, hacerlo mínimamente y sin alterar el sentido.
- Siempre incluir el campo **Fuente** con autor + ticket + fecha + link al archivo `solutions/` correspondiente.
- Si un fix deja de ser válido (regresión), marcar la regla con `[DEPRECATED — fecha]` pero no borrarla (historial).
