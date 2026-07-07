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
  - Usuario "sin permisos" / "sem permissao" / "sem permissão" / "without permissions" para acceder a módulos operativos específicos.
  - Solicitud de "revisión de permisos" / "revisao de permissoes" / "revisão de permissões" / "permissions review" para funciones puntuales como "Stage in", "Movimiento de stock" / "Movimento de estoque" / "Stock movement", "labeling", "seguimiento de unidades" / "acompanhamento de unidades" / "unit tracking" o "reimpresión de shipping label" / "reimpressao de shipping label" / "reimpressão de shipping label" / "shipping label reprint".
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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1418490 (2026-04-21). Patrón absorbido por la regla; el archivo de ejemplo fue eliminado por redundancia (la regla es suficiente).

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

### R-DESC-12 — Cambio automático de jerarquía en LMS por sync de Rostering → funcionalidad esperada, no bug de Groot ⚠️ PENDIENTE VALIDACIÓN
- **Señales**:
  - ES: "alteración indevida de jerarquía en LMS", "equipo movido automáticamente sin solicitud", "cambio automático de supervisor en LMS sin aceptación".
  - PT: "alteração indevida de hierarquia no LMS", "equipe movida automaticamente para supervisor sem solicitação", "mudança indevida de hierarquia", "sem solicitacao manual nem aceite".
  - EN: "unexpected hierarchy change in LMS", "team moved automatically without request", "hierarchy changed automatically without manual approval".
  - Contexto típico: el reporte menciona que la jerarquía cambió "automáticamente" (sin solicitud manual), vinculado al CAD/site (ej. CAD SP10), y el TL/equipo aparece bajo un nuevo supervisor sin que nadie lo haya pedido.
- **Razón**: El sync de Rostering hacia LMS puede reasignar jerarquías automáticamente como parte del flujo estándar de la integración. No es un bug de Groot — es funcionalidad existente del sistema.
- **Acción**: Cerrar como `Won't Do`.
- **Verificación previa**: Requiere revisión manual hasta validar el copy de respuesta con Francisco Gonzalez. No usar en descarte automático.
- **Comentario sugerido**:
  > "Incidencia rechazada por IT / Incidente rejeitado pelo IT."
- **Fuente**: groot-queue:analyze-history, SSHP-1454812, 2026-05-26. Nota interna: el comentario real del equipo no estaba disponible en la API al minar este ticket; confirmar el copy validado con Francisco Gonzalez antes de usar.

### R-DESC-13 — Solicitud de liberar bolha/permisos o roles sin error técnico → gestor de aplicación
- **Señales**:
  - ES: "liberar acceso a bolha", "habilitar Put Away", "ajuste de permisos", "agregar función", "asignar rol para función operativa".
  - PT: "liberar acesso a bolha", "habilitar Put Away", "ajuste de permissoes", "adicionar funcao", "atribuir role para funcao operacional".
  - EN: "grant bubble access", "enable Put Away", "permissions adjustment", "add function", "assign role for operational function".
- **Razón**: Groot Soporte no modifica atributos ni roles por pedido operativo. Si no hay error sistémico de la herramienta, la gestión debe hacerla el gestor de la aplicación u operación.
- **Verificación previa**: Si el requester reporta que intentó asignar el rol/función y la herramienta da error o no guarda, reclasificar como `VALIDO_GROOT`. Si el caso menciona Training Hub / Learning Hub pero no indica entrenamiento completado ni asistencia validada, mantener esta regla antes que `R-DESC-08`.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Desde groot no hacemos modificacion de atributos/roles, para eso debe ponerse en contacto con el gestor de su aplicacion."
- **Fuente**: groot-queue:analyze-history, SSHP-1470912, 2026-06-08.

### R-DESC-14 — Usuario interno dado de baja en SSFF no puede reactivarse manualmente
- **Señales**:
  - ES: "usuario interno dado de baja en SSFF", "usuario inactivo en Groot no puede ser reactivado", "opción de activar deshabilitada".
  - PT: "usuario interno desligado no SSFF", "usuario inativo em Groot nao pode ser reativado", "opcao de ativar desabilitada".
  - EN: "internal user deactivated in SSFF", "inactive user in Groot cannot be reactivated", "activate option disabled".
- **Razón**: Los usuarios internos dados de baja en SSFF no se reactivan manualmente desde Groot. Cuando SSFF vuelve a activar al usuario, la cuenta se reactiva automáticamente.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola los usuarios internos que son dados de baja en SSFF no se pueden volver a reactivar. Cuando el usuario sea nuevamente activado se reactivara la cuenta automaticamente."
- **Fuente**: groot-queue:analyze-history, SSHP-1488491, 2026-06-14.

### R-DESC-15 — Roles temporales no restauran roles incompatibles por regla de auditoría
- **Señales**:
  - ES: "roles previos no se restauran", "permiso temporal expiró y no volvieron los roles", "roles incompatibles previamente asignados".
  - PT: "roles anteriores nao retornam", "permissao temporaria expirou e os roles nao voltaram", "roles incompatíveis previamente atribuídos".
  - EN: "previous roles are not restored", "temporary permission expired and roles did not return", "previously assigned incompatible roles".
- **Razón**: Desde el 14 de marzo no se exceptúan incompatibilidades de roles por pedido del equipo de auditoría. Usuarios con roles incompatibles asignados previamente pueden perder progresivamente esa concurrencia cuando pasan por flujos de roles temporales.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido** (nota interna):
  > "Usuarios con roles incompatibles previamente asignados desde el 14 de marzo esto se dejo de exceptuar incompatibilidades por pedido del equipo de auditoria esto hace que usuario con roles asignados previamente cuando entren en estos procesos empiecen a perder paultatinamente la concurrencia de roles incompatibles"
- **Fuente**: groot-queue:analyze-history, SSHP-1482125, 2026-06-14.

### R-DESC-16 — Jerarquía/gestor reportado como incorrecto en Groot pero coincide con SSFF → cambio debe gestionarse en SSFF
- **Señales**:
  - ES: "jerarquía incorrecta", "gestor/supervisor incorrecto en Groot", "no cambió el líder en Groot", "superior no corresponde".
  - PT: "hierarquia incorreta", "gestor incorreto no Groot", "superior hierárquico errado", "problema de hierarquia e gestão".
  - EN: "incorrect hierarchy", "wrong manager in Groot", "supervisor not updated", "hierarchy and management problem".
- **Razón**: El valor en Groot es un reflejo fiel de SSFF (SuccessFactors). Si la jerarquía es incorrecta, el cambio debe hacerse en SSFF y Groot lo sincronizará automáticamente.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "El superior asignado que figura es el mismo que el que tiene asignado en SSFF. El cambio de gestor debe realizarse en SuccessFactors para que se refleje automáticamente en Groot."
- **Fuente**: groot-queue:analyze-history, SSHP-1502400, 2026-06-29.

### R-DESC-17 — Tools/aplicaciones no administradas por Groot → acceso debe validarse con el equipo correspondiente
- **Señales**:
  - ES: "no puede acceder a sistemas/tools", "aplicaciones no administradas por Groot", "error al acceder" + URL que no es de Groot.
  - PT: "não consegue acessar sistemas mesmo com bolhas liberadas", "aplicações não administradas pelo Groot".
  - EN: "cannot access systems even with bubbles released", "applications not managed by Groot".
  - URLs reportadas NO pertenecen al dominio de Groot (`envios.adminml.com/tools/auth/*`).
- **Razón**: Groot solo administra tools bajo su dominio (`envios.adminml.com/tools/auth/*`). Problemas de acceso a otras tools deben ser gestionados por los equipos responsables de esas plataformas.
- **Verificación previa**: Confirmar que las URLs reportadas NO pertenecen a Groot. Si el error es en una tool de Groot → reclasificar como `VALIDO_GROOT`.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Estas aplicaciones no son administradas por Groot. Validar que el usuario tenga los permisos necesarios para acceder a las tools indicadas."
- **Fuente**: groot-queue:analyze-history, SSHP-1510443, 2026-07-01.

### R-DESC-18 — Error al crear Labour Share por posición "analyst" → funcionalidad by design, no bug
- **Señales**:
  - Usuario reporta que no puede crear Labour Share para ninguno de sus colaboradores.
  - ES: "no puedo crear labour share", "error al crear labour share", "no me permite crear LS", "la herramienta no me deja crear Labour Share".
  - PT: "nao consigo criar labour share", "erro ao criar labour share", "nao permite criar LS".
  - EN: "cannot create labour share", "error creating labour share", "not allowed to create LS".
  - El error afecta a **todos** los HCs del usuario, no a uno solo.
  - Al verificar en Groot, el usuario tiene posición `analyst` (no `team_lead` ni `supervisor`).
- **Razón**: Solo los usuarios con posición `team_lead` o `supervisor` tienen permiso para crear Labour Share. La posición `analyst` no habilita esta funcionalidad — es restricción by design del sistema, no un bug.
- **Verificación previa**: Confirmar en Groot admin que el usuario tiene posición `analyst`. Si la posición es `team_lead` o `supervisor` y aun así falla → reclasificar como `VALIDO_GROOT` (error sistémico real).
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola, el error al crear Labour Share se debe a que la posición del usuario es 'analyst'. Solo los usuarios con posición team_lead o supervisor tienen habilitada la funcionalidad de crear Labour Share. Esto es por diseño del sistema."
- **Fuente**: ticket SSHP-1417376 (2026-04-17). Ver `solutions/labor-share/error-labour-share-posicion-analyst.md`.

### R-DESC-19 — Solicitud de operación que ya es funcionalidad existente en la tool de autogestión (catch-all)
- **Señales**:
  - ES: "cambiar líder", "cambio de TL", "alteración de TL", "mover usuario a otro supervisor", "cambiar atributo", "asignar CAD", "modificar facility", "quiero cambiar X a Y".
  - PT: "alteração de TL", "trocar líder", "mover usuário para outro supervisor", "modificar atributo", "trocar facility", "quero alterar X para Y".
  - EN: "change TL", "change leader", "move user to another supervisor", "modify attribute", "change facility", "I want to change X to Y".
  - La solicitud pide ejecutar una **operación estándar** que la herramienta de Groot ya provee por autogestión (cambio de líder, asignación de atributos, cambio de facility, etc.).
  - **No** hay error técnico / sistémico reportado: la tool funciona, el requester simplemente pide que Groot ejecute la operación en su lugar.
  - No matchea una regla más específica (R-DESC-02, R-DESC-04, R-DESC-09, R-DESC-10, R-DESC-13).
- **Razón**: Groot Soporte atiende **solo errores sistémicos**. Si la funcionalidad ya existe en la tool y está disponible para ser ejecutada por el líder/gestor de la operación, no hay intervención requerida por parte de soporte.
- **Verificación previa**: Si el requester reporta que intentó realizar la operación y la herramienta **da error / no guarda / falla** → reclasificar como `VALIDO_GROOT` (error sistémico). Si ya tiene asignado exactamente lo que pide (estado actual = estado deseado) → descartar sin más.
- **Acción**: Cerrar como `Won't Do` con razón `[R] Funcionalidad existente`.
- **Comentario sugerido**:
  > "Hola, la operación solicitada es una funcionalidad que ya existe en la tool de autogestión. Los líderes/gestores actuales pueden realizar esta acción directamente desde https://envios.adminml.com/tools/auth/users/shared?active=true. Desde soporte Groot solo atendemos errores sistémicos de la herramienta."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1494206 (2026-07-06). Regla catch-all para resolución `[R] Funcionalidad existente`.

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

### R-DER-12 — Errores en la contabilidad de horas en Be a Rep → LMS ⚠️ PENDIENTE VALIDACIÓN (option id LMS faltante)
- **Señales**:
  - ES: "errores en la contabilidad de horas en Be a Rep", "horas mal contabilizadas en Be a Rep", "diferencia de horas en Be a Rep", "las horas de Be a Rep no coinciden en LMS".
  - PT: "erros na contabilização de horas no Be a Rep", "horas contabilizadas incorretamente no Be a Rep", "divergência de horas no Be a Rep", "horas do Be a Rep não batem no LMS".
  - EN: "Be a Rep hours accounting error", "hours incorrectly accounted in Be a Rep", "Be a Rep hours mismatch", "Be a Rep hours do not match in LMS".
  - Contexto típico: el requester reporta diferencias, errores de cálculo o inconsistencias en las horas asociadas al flujo Be a Rep y el impacto esperado está en LMS / Labour Management System, no en roles, atributos ni permisos de Groot.
- **Prioridad de triage**: Esta regla debe matchear antes de clasificar el ticket como `Labour Share` genérico o `VALIDO_GROOT`. Si el texto combina `Be a Rep` + diferencias/errores de horas + `LMS`, el veredicto es `DERIVAR` a LMS.
- **Razón**: La contabilización y conciliación de horas en LMS queda fuera del dominio de Groot/Kraken. Groot puede exponer o consumir datos del flujo Be a Rep, pero los desvíos de horas deben ser revisados por el equipo dueño de LMS.
- **Verificación previa**: Si el síntoma es devolución de roles en Be a Rep / Labour Share, verificar primero que el problema no sea una inconsistencia de snapshot resuelta por el equipo dev. Si el problema es una falla técnica de agendado, snapshot, permisos, CAD o rol dentro de Groot, no aplica esta regla y debe seguir el runbook correspondiente.
- **Acción**: Derivar a **LMS**.
- **Automatización**: No ejecutar derivación automática hasta completar el option id de LMS para `DERIVATION_DESTINATION_SQUAD_FIELD` y validar el copy de nota interna con un ticket real.
- **Comentario sugerido provisional**:
  > "Hola, derivamos este caso al equipo de LMS porque el problema reportado corresponde a la contabilidad de horas de Be a Rep en LMS, fuera del alcance de soporte Groot/Kraken."
- **Fuente**: Pedido directo del usuario, 2026-06-03. Regla agregada sin ticket real por instrucción explícita; pendiente de validar wording y copy contra un caso SSHP concreto.

### R-DER-13 — Acceso denegado a xtools/Pidgey (chat interno / notificaciones outbound) → Equipo Chat Interno
- **Señales**:
  - La URL afectada pertenece a `xtools.adminml.com/tools/pidgey/*`.
  - ES: "no autorizado en xtools", "no puede acceder a notificaciones de chat", "error en pidgey", "sin acceso a sección de notificaciones en xtools".
  - PT: "nao autorizado no xtools", "sem acesso às notificações de chat", "erro no pidgey", "nao consegue acessar notificações no xtools".
  - EN: "not authorized in xtools", "cannot access chat notifications", "pidgey error", "no access to notifications section in xtools".
  - El problema afecta específicamente a funcionalidades de chat interno / burbuja outbound en xtools, no a configuración de usuario en Groot.
  - El ticket puede llegar mal asignado a Groot o a WoWChat.
- **Razón**: xtools/Pidgey (chat interno y notificaciones outbound) no pertenece al dominio de Groot ni de WoWChat. El equipo dueño es el de Chat Interno (Pidgey), que gestiona los permisos de acceso a esa sección.
- **Verificación previa**: Confirmar que la URL reportada es `xtools.adminml.com/tools/pidgey/*`. Si el error es en otra sección de xtools que sí involucre configuración de usuario Groot (ej. perfil, facility, CAD) → no aplica, reclasificar a la categoría correspondiente.
- **Acción**: Derivar a **Equipo Chat Interno (Pidgey)**.
- **Comentario sugerido**:
  > "Hola, este inconveniente corresponde al equipo de Chat Interno (Pidgey), que es el responsable de los permisos de acceso a las notificaciones en xtools. Derivamos para que continúen con la atención del caso."
- **Fuente**: ticket SSHP-1413000 (2026-04-18). Ver `solutions/role-permission/no-autorizado-xtools-pidgey-derivado.md`.

### R-DER-14 — Alta/regularización de nodo o valor nuevo en Kraken → Helpdesk IA (platsec/randall o integradores)
- **Señales**:
  - ES: "alta de nodo", "regularización de nodo", "crear nodo nuevo en Kraken", "dar de alta valor", "agregar nodo", "asociar nodo a SC", "no existe el nodo", "valor nuevo en Kraken".
  - PT: "cadastro de nó", "regularização de nó", "criar nó novo no Kraken", "cadastrar valor", "adicionar nó", "associar nó ao SC", "nó não existe", "valor novo no Kraken".
  - EN: "register node", "create new node in Kraken", "add new value", "add node", "associate node to SC", "node does not exist", "new value in Kraken".
  - La solicitud pide **dar de alta / crear / registrar** un nodo o valor que **no existe** actualmente en Kraken.
  - Contexto típico: quieren asociar un nodo (ej. NEX, XD, SC) a otro nodo padre (ej. SC, warehouse) pero el nodo hijo no existe en el sistema.
- **Razón**: Groot/Kraken Soporte no tiene herramientas para dar de alta valores nuevos en Kraken. El alta de nodos/valores nuevos debe llegar por los integradores o solicitarse al equipo de platsec/randall.
- **Verificación previa**: Confirmar que el nodo/valor efectivamente no existe en Kraken. Si el nodo existe pero hay un error al intentar asociarlo → reclasificar como `VALIDO_GROOT` (error sistémico).
- **Acción**: Derivar a **Helpdesk IA** (ruteo a platsec/randall o integradores).
- **Comentario sugerido**:
  > "Hola, desde soporte Groot/Kraken no tenemos opción para dar de alta valores nuevos. Estos deben llegar por los integradores o pedir ayuda al equipo de platsec/randall."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1469338 (2026-07-07).

---

## Algoritmo de triage (para `list` y `classify`)

Para cada ticket abierto, evaluar en este orden y asignar el **primer** veredicto que matchee:

1. **R-DER-12** ⚠️ _[pendiente validación — no ejecutar automáticamente]_ → si el reporte menciona errores, diferencias o inconsistencias en la contabilidad de horas de Be a Rep con impacto en LMS / Labour Management System.
2. **R-DER-06** → si LDAP `ext_*` aparece como **cuenta Meli** en Kioske/TOTEM y no puede cambiar contraseña.
3. **R-DER-07** → si la herramienta afectada es **Shield** y el flujo es cambio de líder para colaboradores externos.
4. **R-DER-09** → si el reporte menciona "tax id inválido", "CUIT inválido", "CPF inválido", "documento inválido" (frontend o bulk).
5. **R-DER-11** → si al crear/dar de alta un colaborador el error es "Tax_id has already been used" / ES "tax id ya utilizado" / PT "tax_id já utilizado" (documento **válido** pero ya en uso; distinto de R-DER-09 que es tax id *inválido*).
6. **R-DER-10** → si el usuario final ve un mensaje tipo "no perteneces a envíos" / "no pertence a envios" al intentar crear cuenta o desbloquearla (y por eso no puede conocer su LDAP).
7. **R-DER-08** → si el pedido es **cambio de nombre** del usuario (first/last name), sin error técnico de Groot.
8. **R-DER-13** → si la URL afectada es `xtools.adminml.com/tools/pidgey/*` (chat interno / notificaciones outbound) y el problema no involucra configuración de usuario en Groot.
9. **R-DER-14** → si la solicitud pide dar de **alta / crear / registrar** un nodo o valor nuevo que no existe en Kraken (ej. "alta de nodo NEX", "registrar nodo", "crear valor nuevo").
10. **R-DER-04** → si la URL afectada es `envios.adminml.com/logistics/...` / **package-management** / app nav / componente externo y el usuario está correctamente configurado en Groot/Kraken.
11. **R-DER-05** → si el tema es de **clasificación/taxonomía** de proceso madre en la tool Groot o issues de **app nav** (no un error real de Groot).
12. **R-DER-01** → si menciona "tag azul", "no es cuenta de envíos", "conta não é de envios", "sin opción de deshabilitar", o el admin (accediendo al perfil en la tool de Groot) ve que "no puede habilitar al usuario" porque "no pertenece a envíos / no pertenece a Mercado Envío" / PT "não pertence às remessas" / "nao pertence as remessas" / EN "does not belong to shipping" / "not a shipping account" (cuenta desactivada que piden reactivar; IAM debe ajustar el flag de shipping).
13. **R-DER-02** → si menciona "app nav", "navegación del app", "navegação" sin señal de R-DER-05.
14. **R-DER-03** → si menciona "vincular cuenta", "desvincular", "cuenta Meli vs ext_", "cambio de contraseña" (sin señal de Kioske/TOTEM que apunte a R-DER-06).
15. **R-DESC-03** → si el usuario reporta que en xtools / autogestión "no aparece CAD" / "não aparece CAD" / "no puedo seleccionar facility" + contexto de visitar otro site.
16. **R-DESC-06** → si el usuario afectado es **rep** y el reporte es previo al clock-in físico del día en el site objetivo.
17. **R-DESC-07** → si reps no ven una bolha/función y la verificación confirma que **están** en el facility correcto.
18. **R-DESC-13** → si pide liberar bolha/permisos/roles para una función operativa sin error técnico de Groot, y la acción corresponde al gestor de aplicación u operación.
19. **R-DESC-08** → si el requester menciona "learning completado", "training hub", "learning hub" y pide asignación de rol post-capacitación.
20. **R-DESC-04** → si es pedido de **cambio de líder / supervisor directo** sin error técnico (lista de usuarios a mover + nuevo líder).
21. **R-DESC-09** → si pide **remover** un rol a un operario y no hay error técnico reportado.
22. **R-DESC-05** → si hay error "no autorizado" / "not authorized" o solicitud de permisos para un módulo/URL específico y el usuario **sí** logra loguearse.
23. **R-DESC-02** → si es solicitud de **asignación de rol** a usuario (sin error técnico) y la cuenta **no** tiene tag azul.
24. **R-DESC-10** → si pide **asignar / cambiar / quitar un valor de atributo** (CAD, facility, atributo operativo) sin error técnico, y no matchea R-DESC-03 / R-DESC-06 / R-DESC-07.
25. **R-DESC-18** → si el usuario no puede crear Labour Share para ninguno de sus HCs y la verificación confirma que tiene posición `analyst` (no `team_lead` ni `supervisor`).
26. **R-DESC-01** → si proviene de **Opex Full / SMO** y fue derivado fuera de ventana (>15 días de aging al llegar a Groot, posterior a 2025-10-28).
27. **R-DESC-11** → si el problema ocurre en un sistema externo a Groot/Kraken (ej. HCM Rostering) y no hay error en ninguna herramienta de Groot.
28. **R-DESC-12** ⚠️ _[pendiente validación — clasificar como `REVISAR_MANUAL` hasta confirmar copy con Francisco Gonzalez]_ → si el reporte es una jerarquía que cambió automáticamente en LMS (sin solicitud manual) y el contexto apunta a un sync de Rostering, clasificar como `REVISAR_MANUAL` hasta validar el copy de descarte.
29. **R-DESC-14** → si un usuario interno dado de baja en SSFF aparece inactivo en Groot y no puede reactivarse manualmente.
30. **R-DESC-15** → si roles previos no se restauran tras expirar un rol temporal por incompatibilidades de roles que ya no se exceptúan.
31. **R-DESC-16** → si el usuario reporta jerarquía/gestor incorrecto en Groot pero la verificación confirma que el valor coincide con SSFF (SuccessFactors).
32. **R-DESC-17** → si el usuario reporta que no puede acceder a sistemas/tools cuyas URLs NO pertenecen al dominio de Groot (`envios.adminml.com/tools/auth/*`).
33. **R-DESC-19** → si la solicitud pide ejecutar una operación estándar que la tool ya provee por autogestión, sin error técnico, y no matchea ninguna regla más específica anterior.
34. Si ninguna regla matchea → `VALIDO_GROOT` (si la categoría del ticket está en los runbooks de `runbooks.md`) o `REVISAR_MANUAL` (si no hay categoría clara).

---

## Cambios en `list` y `classify`

### `list` — columna extra

```
| # | Key | Summary | Status | Priority | Assignee | Edad | Triage |
```

Donde `Triage` es el indicador (`⛔ DESCARTAR`, `➡️ DERIVAR→<Equipo>`, `🟢 VALIDO_GROOT`, `❓ REVISAR_MANUAL`).

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

- Cada vez que el equipo (Francisco, Julián, etc.) deje en los threads de Slack una acción sobre un ticket (`Descartar`, `Derivar a otro equipo`), **actualizar este archivo** agregando una nueva regla `R-DESC-XX` o `R-DER-XX`.
- Paralelamente, archivar el caso concreto en `solutions/<categoria>/` con el formato de la knowledge base (ver `README.md`).
- Mantener el **comentario sugerido** tal cual lo escribió el equipo (es copy validado para responder al usuario). Si es necesario normalizar tildes o puntuación, hacerlo mínimamente y sin alterar el sentido.
- Siempre incluir el campo **Fuente** con autor + ticket + fecha + link al archivo `solutions/` correspondiente.
- Si un fix deja de ser válido (regresión), marcar la regla con `[DEPRECATED — fecha]` pero no borrarla (historial).
