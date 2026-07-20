---
name: groot-queue-triage-rules
description: Reglas de triage para determinar si un ticket de la cola Groot (SSHP) debe descartarse, derivarse a otro equipo o ya tiene fix aplicado. Alimentada a partir del seguimiento histórico de la ticketera y de la resolución diaria de tickets.
---

# Reglas de Triage — Cola Groot (SSHP)

> Fuente original: "Seguimiento Ticketera Jira Groot.xlsx" (snapshot 2025-11 / 2025-12).
> Actualizada con casos del día a día del equipo (ver `solutions/` para ejemplos concretos).
> Uso: consultar en `/groot-queue list` y `/groot-queue classify` para marcar cada ticket con un **Veredicto de Triage** antes de mostrarlo.

---

## Alcance de Groot Soporte — definición de "error sistémico"

Groot Soporte atiende **exclusivamente errores sistémicos**: bugs, comportamientos inesperados o fallos de la herramienta que **no pueden resolverse mediante las herramientas de autogestión disponibles** (Groot admin, Alfred, xtools, autogestión del líder).

**Son errores sistémicos (→ `VALIDO_GROOT`):**
- Crashes, timeouts, errores 500, pantallas en blanco o comportamiento inesperado del sistema.
- La herramienta falla al ejecutar una operación que debería funcionar (no muestra mensaje de validación claro, no guarda sin motivo aparente).
- Un usuario o administrador con permisos válidos no puede realizar una acción que el sistema debería permitirle.

**NO son errores sistémicos (→ `DESCARTAR` o `DERIVAR`):**
- Solicitudes de asignar, cambiar o remover roles, atributos, permisos o configuraciones — esas operaciones las ejecuta el gestor de usuarios de la operación desde la tool de autogestión.
- Errores de validación esperables: mensajes del tipo "atributo X es obligatorio", "debe tener un valor por defecto", "debe corregir lo siguiente" — la herramienta está funcionando correctamente al bloquear datos incompletos.
- Funcionalidades que no aparecen porque faltan permisos, roles o atributos — eso es configuración operativa, no bug de la plataforma.

> **Criterio de distinción**: si la herramienta muestra un mensaje claro indicando qué falta o qué condición no se cumple → es validación esperada, no bug. Si falla de forma inesperada sin mensaje de validación claro → es error sistémico.

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

### R-DESC-02 — Solicitud de asignación de roles a un usuario ⚡
- **Señales**:
  - Summary/description contiene una solicitud operativa de asignación de roles: ES "asignar rol", "asignación de roles", "darle rol", "agregar rol a usuario"; PT "atribuir role", "atribuição de roles", "dar role ao usuário", "adicionar role ao usuário"; EN "assign role", "role assignment", "grant role", "add role to user".
  - Cuenta **sin** tag azul de "no es cuenta de envíos" (es decir, es de shipping).
  - No hay problema técnico: el usuario simplemente pide que le asignen un rol.
- **Razón**: Groot Soporte **no** hace asignación de roles; eso lo hace el gestor de usuarios de la operación. Groot atiende **solo errores sistémicos**.
- **Verificación previa**: Si el requester reporta que intentó asignar el rol y la herramienta **da error / no guarda**, o que un usuario con permisos válidos para asignarlo **no puede hacerlo aunque debería poder** → distinguir: si el error es un **mensaje de validación** (ej. "atributo obligatorio", "debe tener valor por defecto", "debe corregir lo siguiente") → aplicar `R-DER-24` (derivar a IAM Soporte, no es error sistémico). Solo reclasificar como `VALIDO_GROOT` (runbook Roles/Permisos) si el error es **sistémico** (500, timeout, crash, comportamiento inesperado sin mensaje de validación claro). Señales de excepción sistémica: ES "no puede asignar el rol", "debería poder asignarlo", "error inesperado al asignar rol"; PT "não consegue atribuir o role", "deveria conseguir atribuir", "erro inesperado ao atribuir role"; EN "cannot assign the role", "should be able to assign it", "unexpected error assigning role". Mismo criterio de escape que `R-DESC-09`.
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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1410959 (2026-04-21).

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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1415474 (2026-04-21). Excepción "líder inactivo" agregada el 2026-05-27.

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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1416994 (2026-04-21).

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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1409680 (2026-04-21).

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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1409554 (2026-04-21).

### R-DESC-08 — Solicitud de rol por Learning Hub / Training Hub completado ⚡
- **Señales**:
  - Summary/description menciona: "completó learning", "learning hub", "training hub", "asistió al entrenamiento", "terminó capacitación".
  - El usuario pide la asignación de un rol específico post-capacitación.
  - En Groot no hay error técnico (la tool funciona).
- **Razón**: La correspondencia "learning completado → rol asignado" es competencia del gestor de usuarios de la operación, no de Groot.
- **Verificación previa**: Confirmar que no hay error al intentar asignar el rol en Groot. Si la tool falla al asignar → reclasificar como `VALIDO_GROOT`.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola, las solicitudes de roles a partir de asistencia en Learning Hub / Training Hub son atendidas por el equipo de gestión de usuarios de la operación. Desde aquí no damos soporte a este tipo de solicitudes."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1412472 (2026-04-21).

### R-DESC-09 — Remoción manual de rol sin error técnico → gestor de usuarios de la operación ⚡
- **Señales**:
  - Summary/description: "remover rol", "quitar rol", "desasignar rol" a un operario puntual.
  - No hay error técnico reportado.
  - El requester no es gestor de usuarios de operación; simplemente pide que Groot ejecute la remoción.
- **Razón**: Groot Soporte no ejecuta asignación ni remoción manual de roles (complementa `R-DESC-02`). Esas operaciones las realiza el gestor de usuarios del site desde la propia herramienta Groot admin.
- **Verificación previa**: Si el requester dice "intenté remover y me da error" → distinguir: si el error es un **mensaje de validación** (ej. "atributo obligatorio", "debe tener valor por defecto") → aplicar `R-DER-24` (derivar a IAM Soporte). Solo reclasificar como `VALIDO_GROOT` (runbook Roles/Permisos) si el error es **sistémico** (500, timeout, crash, comportamiento inesperado).
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Esta solicitud debe ser enviada al equipo de gestión de usuario de su operación. Desde soporte Groot/Kraken no hacemos este tipo de asignaciones o remociones."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1418490 (2026-04-21). Patrón absorbido por la regla; el archivo de ejemplo fue eliminado por redundancia (la regla es suficiente).

### R-DESC-10 — Solicitud de asignación/cambio de valor de atributo sin error sistémico → gestor de usuarios de la operación ⚡
- **Señales**:
  - Summary/description pide **asignar / agregar / cambiar / quitar un valor de atributo** (CAD, facility, atributo operativo) a uno o pocos usuarios. Variantes de texto: ES "asignar atributo", "agregar atributo", "cambiar CAD", "asignar facility", "falta el atributo X", "asignar valor de atributo"; PT "atribuir atributo", "adicionar atributo", "trocar CAD", "atribuir facility", "falta o atributo", "valor de atributo faltando"; EN "assign attribute", "add attribute", "change CAD", "assign facility", "set attribute value", "missing attribute".
  - **No** hay error técnico/sistémico: la herramienta de Groot funciona; el requester solo pide que Groot ejecute la asignación/cambio.
  - El requester no es gestor de usuarios de la operación; pide que Groot haga la operación por él.
- **Razón**: Groot Soporte atiende **solo errores sistémicos**. La asignación o cambio de valores de atributo sin error de la herramienta la realiza el gestor de usuarios de la operación (mismo criterio que `R-DESC-02` / `R-DESC-09` para roles, extendido a atributos). Si la solicitud es solo "ejecutá esta acción porque al usuario le falta el atributo", el canal no es la ticketera de Groot.
- **Verificación previa**: Si el requester reporta que intentó la operación y la tool **da error / no guarda** → distinguir: si el error es un **mensaje de validación** (ej. "atributo X es obligatorio", "debe tener valor por defecto") → aplicar `R-DER-24` (derivar a IAM Soporte, no es error sistémico). Solo reclasificar como `VALIDO_GROOT` si el error es **sistémico** (500, timeout, crash, comportamiento inesperado sin mensaje de validación claro). Distinto de `R-DESC-03` (el valor no aparece en autogestión porque el líder no lo tiene), `R-DESC-06` (rep sin clock-in) y `R-DESC-07` (reps ya ubicados en el facility): si matchea una de esas señales específicas, usar esa regla.
- **Acción**: Cerrar como `Won't Do`.
- **Comentario sugerido**:
  > "Hola, desde soporte Groot/Kraken solo atendemos errores sistémicos. La asignación o cambio de valores de atributo (CAD, facility, etc.) sin un error de la herramienta debe gestionarla el equipo de gestión de usuarios de su operación."
- **Fuente**: Sync Groot Queue, criterio general de triage roles/atributos, 2026-06-02.

### R-DESC-11 — Incidencia en sistema externo a Groot (ej. HCM Rostering) → falso positivo, rechazar ⚡
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

### R-DESC-13 — Solicitud de liberar bolha/permisos o roles sin error técnico → gestor de aplicación ⚡
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

### R-DESC-14 — Usuario interno dado de baja en SSFF no puede reactivarse manualmente ⚡
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
- **⚠️ NO APLICA cuando**:
  - El rol temporal **nunca impactó** en la operación (no se reflejó en la HH, el usuario nunca pudo trabajar con el rol asignado). Eso es un **bug real** → `VALIDO_GROOT`.
  - El usuario reporta que el **proceso de rol temporal falló completamente** (asignación no efectiva, retorno no ejecutado, el sistema no procesó el cambio). Eso es un **error sistémico** → `VALIDO_GROOT`.
  - El ticket menciona roles temporales usados **justamente para evitar compliance** en procesos operativos (ej: Picking temporal para cubrir turno). Estos roles se usan dentro del diseño del sistema; si no funcionan, es un bug.
  - **Aplica SOLO cuando**: el usuario se queja de que **perdió roles que antes tenía** (roles incompatibles que coexistían) después de pasar por un flujo de roles temporales, y la pérdida se debe a que ya no se exceptúan incompatibilidades desde el 14 de marzo.
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
- **Fuente**: ticket SSHP-1417376 (2026-04-17).

### R-DESC-19 — Solicitud de operación que ya es funcionalidad existente en la tool de autogestión (catch-all) ⚡
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

### R-DER-03 — Vincular/desvincular cuenta o cambio de contraseña → IAM Soporte
- **Señales**:
  - Aparece como "cuenta Meli" y debería ser `ext_`, o al revés.
  - Pide cambio de contraseña que requiere flujo de autogestión.
- **Razón**: Problemas de vinculación de cuenta los maneja **IAM Soporte** (`57102`).
- **Acción**: Derivar a IAM Soporte.
- **Comentario sugerido**:
  > "Hola, la vinculación o desvinculación de cuentas (cuenta MELI vs cuenta ext_) y cambios de contraseña requieren la intervención del equipo de IAM Soporte. Derivamos para que puedan ayudarte."
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
  > "Hola, este ticket no corresponde a Groot/Kraken Soporte. El usuario está correctamente configurado en Kraken y el error corresponde a un componente externo (Platsec/Randall) que está fuera de nuestro alcance. Derivamos a Helpdesk IA para que enruten el caso con el equipo owner del componente."
- **Canal directo Slack**: `#help-authz-internal-admins`.
- **Fuente**: Francisco Gonzalez, ticket SSHP-1412840 (2026-04-21).

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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1403550 (2026-04-21).

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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1412206 (2026-04-21).

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
- **Fuente**: Francisco Gonzalez, ticket SSHP-1415340 (2026-04-21).

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
  - ES: "tax id inválido", "tax id invalido", "identificador tributario inválido", "Identificador tributario invalido", "CUIT inválido", "documento inválido", "error al validar tax id".
  - PT: "tax id inválido", "identificador tributário inválido", "CPF inválido", "documento inválido", "erro ao validar tax id".
  - EN: "invalid tax id", "invalid tax identifier", "invalid tax document", "invalid document", "tax id validation error".
  - Puede aparecer en **frontend** (un usuario reporta) o en **bulk/masivo** (lote falla por tax id).
- **Prioridad de triage**: Si aparece el wording exacto "Identificador tributario invalido" / "identificador tributario inválido", aplicar esta regla aunque el error ocurra durante la creación de cuenta o colaborador. No clasificarlo como `VALIDO_GROOT` ni como R-DER-16.
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

### R-DER-12 — Errores en la contabilidad de horas en Be a Rep → LMS
- **Señales**:
  - ES: "errores en la contabilidad de horas en Be a Rep", "horas mal contabilizadas en Be a Rep", "diferencia de horas en Be a Rep", "las horas de Be a Rep no coinciden en LMS".
  - PT: "erros na contabilização de horas no Be a Rep", "horas contabilizadas incorretamente no Be a Rep", "divergência de horas no Be a Rep", "horas do Be a Rep não batem no LMS".
  - EN: "Be a Rep hours accounting error", "hours incorrectly accounted in Be a Rep", "Be a Rep hours mismatch", "Be a Rep hours do not match in LMS".
  - Contexto típico: el requester reporta diferencias, errores de cálculo o inconsistencias en las horas asociadas al flujo Be a Rep y el impacto esperado está en LMS / Labour Management System, no en roles, atributos ni permisos de Groot.
- **Prioridad de triage**: Esta regla debe matchear antes de clasificar el ticket como `Labour Share` genérico o `VALIDO_GROOT`. Si el texto combina `Be a Rep` + diferencias/errores de horas + `LMS`, el veredicto es `DERIVAR` a LMS.
- **Razón**: La contabilización y conciliación de horas en LMS queda fuera del dominio de Groot/Kraken. Groot puede exponer o consumir datos del flujo Be a Rep, pero los desvíos de horas deben ser revisados por el equipo dueño de LMS.
- **Verificación previa**: Si el síntoma es devolución de roles en Be a Rep / Labour Share, verificar primero que el problema no sea una inconsistencia de snapshot resuelta por el equipo dev. Si el problema es una falla técnica de agendado, snapshot, permisos, CAD o rol dentro de Groot, no aplica esta regla y debe seguir el runbook correspondiente.
- **Acción**: Derivar a **LMS**.
- **Automatización**: Habilitada. Option id en `$SKILL_DIR/knowledge/jira-field-options.md`. Copy de nota interna pendiente de validación en ticket real — ajustar si hay feedback.
- **Comentario sugerido provisional**:
  > "Hola, derivamos este caso al equipo de LMS porque el problema reportado corresponde a la contabilidad de horas de Be a Rep en LMS, fuera del alcance de soporte Groot/Kraken."
- **Fuente**: Pedido directo del usuario, 2026-06-03. Regla agregada sin ticket real por instrucción explícita; pendiente de validar wording y copy contra un caso SSHP concreto.

### R-DER-13 — Acceso denegado a xtools/Pidgey, xtools/Alfred o Chat Interno → Célula Nexus (asignación interna)
- **Señales**:
  - La URL afectada pertenece a `xtools.adminml.com/tools/pidgey/*`, `xtools.adminml.com/tools/alfred/*` o la URL de Chat Interno (pendiente confirmar).
  - ES: "no autorizado en xtools", "no puede acceder a notificaciones", "error en pidgey", "sin acceso a sección de notificaciones en xtools", "error en alfred", "sin acceso a aprobaciones en xtools", "no puede ver procesos masivos", "sin acceso a chat interno", "error en chat interno".
  - PT: "nao autorizado no xtools", "sem acesso às notificações", "erro no pidgey", "nao consegue acessar notificações no xtools", "erro no alfred", "sem acesso a aprovações no xtools", "sem acesso ao chat interno", "erro no chat interno".
  - EN: "not authorized in xtools", "cannot access notifications", "pidgey error", "no access to notifications section in xtools", "alfred error", "no access to approvals in xtools", "cannot access mass processes", "no access to internal chat", "internal chat error".
  - El problema afecta específicamente a xtools/Pidgey (notificaciones), xtools/Alfred (tickets, aprobaciones, procesos masivos) o Chat Interno, no a configuración de usuario en Groot.
  - El ticket puede llegar mal asignado a Groot o a WoWChat.
- **Razón**: Pidgey, Alfred y Chat Interno son responsabilidad de la **célula Nexus**, que es una célula interna de Groot. No existe squad de Jira para derivación automática: el ticket debe asignarse directamente a un miembro de la célula.
- **Verificación previa**: Confirmar que la URL reportada es `xtools.adminml.com/tools/pidgey/*`, `xtools.adminml.com/tools/alfred/*` o la URL de Chat Interno. Si el error es en otra sección de xtools que sí involucre configuración de usuario Groot (ej. perfil, facility, CAD) → no aplica, reclasificar a la categoría correspondiente.
- **Acción**: Asignación automática vía shuffle a un miembro de la célula Nexus. Ver `$SKILL_DIR/knowledge/pidgey-team.md` para la lista de emails. No hay squad en Jira — se usa `acli jira workitem assign` en lugar de la transición "Derivar a otro equipo".
- **Comentario sugerido** (nota interna al asignar):
  > "Derivado a célula Nexus — acceso denegado a xtools/Pidgey (notificaciones), xtools/Alfred (tickets, aprobaciones, procesos masivos) o Chat Interno. La configuración del usuario en Groot no está involucrada."
- **Fuente**: ticket SSHP-1413000 (2026-04-18).

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
  > "Hola, este ticket no corresponde a Groot/Kraken Soporte. El alta de nodos o valores nuevos en Kraken está fuera de nuestras herramientas; debe gestionarse con los integradores o el equipo de platsec/randall. Derivamos a Helpdesk IA para que enruten el caso con el equipo correspondiente."
- **Fuente**: Francisco Gonzalez, ticket SSHP-1469338 (2026-07-07).

### R-DER-15 — Reactivación de usuario desactivado/expirado que Groot no puede resolver → IAM Soporte
- **Señales**:
  - ES: "reactivar usuario desactivado", "cuenta desactivada", "expirada", "no se puede reactivar", "error al reactivar", "cuenta expirada", "usuario desactivado no puede ser reactivado".
  - PT: "reativar usuário desativado", "conta desativada", "expirada", "não pode ser reativado", "erro ao reativar", "conta expirada", "usuário desativado não pode ser reativado".
  - EN: "reactivate disabled user", "account disabled", "expired", "cannot reactivate", "error reactivating", "account expired", "disabled user cannot be reactivated".
  - El líder o el usuario reporta que una cuenta aparece como desactivada/expirada en Groot o MeliHelp y no hay opción para reactivarla desde la autogestión.
- **Razón**: Cuando la desactivación involucra bloqueos de SuccessFactors, IAM o sincronización de HR, Groot Soporte no tiene herramientas para desbloquear. El equipo de IAM Soporte tiene acceso directo para resolver estos casos.
- **Verificación previa**: Confirmar que el usuario realmente aparece como desativado/expirado en Groot. Si el usuario está activo pero con permisos faltantes → reclasificar como `VALIDO_GROOT`.
- **Acción**: Derivar a **IAM Soporte** (`57102`).
- **Comentario sugerido**:
  > "Hola, la reactivación de cuentas desactivadas/expiradas que no se resuelve por autogestión requiere intervención del equipo de IAM. Derivamos para que puedan ayudarte."
- **Fuente**: Análisis histórico (5 tickets: SSHP-1508978, SSHP-1497366, SSHP-1498407, SSHP-1499951, SSHP-1458962).

### R-DER-16 — Error de creación de usuario por fallo de SuccessFactors / datos inválidos → IAM Soporte
- **Señales**:
  - ES: "error al crear usuario", "datos no válidos", "no genera Groot ID", "error de identificador", "SuccessFactors no permite continuar", "error de datos en creación masiva".
  - PT: "erro ao criar usuário", "dados inválidos", "não gera Groot ID", "erro de identificador", "SuccessFactors não permite continuar", "erro de dados na criação", "falha no SuccessFactors".
  - EN: "error creating user", "invalid data", "does not generate Groot ID", "identifier error", "SuccessFactors does not allow to continue", "data error in creation".
  - El líder intenta crear uno o varios usuarios (internos o externos) desde Groot y recibe error del sistema que menciona SuccessFactors, datos inválidos, o identificador tributario (pero **no** es un documento duplicado — para eso ver R-DER-11).
- **Razón**: Los errores sistémicos de integración con SuccessFactors requieren investigación del equipo IAM Soporte, que tiene acceso a los logs de integración y puede corregir datos en la fuente.
- **Verificación previa**: Confirmar que no es un caso de documento inválido (R-DER-09) ni documento duplicado (R-DER-11). Si el error menciona "identificador tributario inválido" / "Identificador tributario invalido" / "invalid tax id" → aplicar R-DER-09. Si menciona "tax_id has already been used" o "CPF já utilizado" → aplicar R-DER-11 en su lugar.
- **Acción**: Derivar a **IAM Soporte** (`57102`).
- **Comentario sugerido**:
  > "Hola, el error de creación está relacionado con la integración de SuccessFactors y requiere investigación del equipo de IAM. Derivamos para que puedan resolver el problema de datos."
- **Fuente**: Análisis histórico (8+ tickets: SSHP-1482522, SSHP-1483624, SSHP-1483830, SSHP-1483831, SSHP-1483993, SSHP-1482546, SSHP-1482691, SSHP-1480290, SSHP-1482672).

### R-DER-17 — Error funcional de WMS/Logistics con permisos correctos en Groot → Helpdesk IA
- **Señales**:
  - ES: "tiene permisos pero no puede acceder a WMS", "monitores WMS inbound sin acceso", "pantalla en blanco WMS", "error 403 WMS", "no puede tomar proceso", "WMS se recarga", "botón aplicar deshabilitado", "sin visibilidad del warehouse", "cambio automático de warehouse", "limitado al CAD local en WMS", "no puede consultar todos los CADs", "funciona en pestaña de incógnito", "solo pasa con su usuario en WMS".
  - PT: "tem permissões mas não consegue acessar WMS", "monitores WMS inbound sem acesso", "tela em branco WMS", "erro 403 WMS", "não consegue pegar processo", "WMS recarregando", "botão aplicar desabilitado", "sem visibilidade do warehouse", "mudança automática de warehouse", "limitado ao CAD local no WMS", "não consegue consultar todos os CADs", "funciona em aba anônima", "só acontece com o usuário dele no WMS".
  - EN: "has permissions but cannot access WMS", "WMS inbound monitors no access", "blank screen WMS", "403 error WMS", "cannot take process", "WMS reloading", "apply button disabled", "no warehouse visibility", "automatic warehouse change", "limited to local CAD in WMS", "cannot query all CADs", "works in incognito tab", "only happens to this user in WMS".
  - El usuario tiene roles y bolhas correctamente asignados en Groot/Kraken, pero **WMS/Logistics no refleja esos permisos** o presenta errores funcionales (pantalla en blanco, error 403, page reloading, botones deshabilitados, procesos inaccesibles, vista limitada al CAD local cuando debería ser regional).
  - **Señal fuerte**: si el usuario reporta que **funciona en pestaña de incógnito / aba anônima pero no en navegador normal**, es casi seguro un problema de sesión/cache del frontend WMS. Si el backend (Groot) tuviera mal la configuración, incógnito tampoco funcionaría. Esta señal por sí sola es suficiente para derivar a Helpdesk IA si se confirma que Groot está correcto.
- **Razón**: Groot Soporte atiende **solo errores sistémicos de Groot**. Si el usuario está correctamente configurado en Groot (bolhas asignadas, warehouse correcto, roles vigentes, atributos regionales) pero WMS/Logistics falla o no muestra las funciones esperadas, el problema es del **sistema WMS** (frontend o backend), no de la configuración de permisos. Groot Soporte no tiene visibilidad ni herramientas para resolver bugs de WMS. No es responsabilidad de Groot investigar problemas de sesión, cache ni rendering del frontend WMS.
- **Verificación previa**: Confirmar que el usuario **efectivamente tiene** los roles/bolhas/warehouse/atributos en Groot. Si la configuración en Groot es incorrecta o faltante → reclasificar como `VALIDO_GROOT` (ajustar permisos en Groot). Si todo en Groot está correcto → derivar sin demora, no intentar workarounds de cache ni troubleshooting de WMS: eso le compete al equipo WMS vía Helpdesk IA.
- **Acción**: Derivar a **Helpdesk IA** (ruteo a WMS/Logistics).
- **Comentario sugerido**:
  > "Hola, este ticket no corresponde a Groot Soporte. Verificamos la configuración del usuario en Groot y los permisos están correctos (roles, bolhas y warehouse asignados). El problema es funcional de WMS/Logistics, fuera del alcance de Groot. Derivamos a Helpdesk IA para que enruten el caso con el equipo de WMS."
- **Fuente**: Análisis histórico (9 tickets: SSHP-1508621, SSHP-1500233, SSHP-1495880, SSHP-1492695, SSHP-1486490, SSHP-1485607, SSHP-1484713, SSHP-1465825, SSHP-1486341). Reforzado con SSHP-1504561 (usuario regional limitado al CAD local en WMS solo en navegador normal; incógnito funciona correctamente).

### R-DER-18 — Solicitud operativa de WMS (gestión de paquetes/envíos, no de usuarios) → Helpdesk IA
- **Señales**:
  - ES: "actualizar status de orders", "destrabar pedidos", "liberar shipments", "paquetes en espera", "cambiar estado de envío", "shipment_id bloqueado".
  - PT: "atualizar status de orders", "destravar pedidos", "liberar shipments", "pacotes em espera", "mudar estado de envio", "shipment_id bloqueado".
  - EN: "update order status", "unlock shipments", "release packages", "packages on hold", "change shipment state", "blocked shipment_id".
  - La solicitud **no involucra usuarios, permisos ni roles** — pide una acción operativa sobre paquetes, envíos o estados en WMS.
- **Razón**: Groot Soporte gestiona usuarios y permisos. Las operaciones sobre paquetes/envíos/orders en WMS corresponden al equipo de WMS/Operaciones.
- **Verificación previa**: Confirmar que el pedido es puramente operativo y no un error derivado de permisos faltantes del usuario.
- **Acción**: Derivar a **Helpdesk IA** (ruteo a WMS/Operaciones).
- **Comentario sugerido**:
  > "Hola, este ticket no corresponde a Groot Soporte. Groot gestiona usuarios y permisos; las operaciones sobre paquetes/envíos en WMS están fuera de nuestro alcance. Derivamos a Helpdesk IA para que enruten el caso con el equipo de WMS/Operaciones."
- **Fuente**: Análisis histórico (2 tickets: SSHP-1489984, SSHP-1489350).

### R-DER-20 — Pérdida de acceso o desincronización IAM↔WMS/LMS (usuario activo pierde permisos sin causa visible en Groot) → IAM Soporte
- **Señales**:
  - ES: "perdió acceso después de login", "sin acceso al warehouse por defecto", "troca de gestión en LMS", "acceso desapareció", "permisos se desasignaron solos".
  - PT: "perdeu acesso após login", "sem acesso ao warehouse padrão", "troca de gestão no LMS", "acesso sumiu", "permissões se desatribuíram sozinhas".
  - EN: "lost access after login", "no access to default warehouse", "management swap in LMS", "access disappeared", "permissions unassigned by themselves".
  - El usuario estaba activo y funcionando, pero **perdió acceso a WMS/LMS sin que nadie modificara su configuración en Groot**. La cuenta sigue activa, los roles parecen estar, pero el sistema downstream (WMS/LMS) dejó de reconocer sus permisos.
- **Razón**: La sincronización entre IAM y los sistemas downstream (WMS, LMS) a veces falla o se corrompe sin intervención manual. El equipo IAM Soporte tiene acceso a los logs de sincronización y puede forzar re-sync o corregir inconsistencias.
- **Verificación previa**: Confirmar que el usuario está activo en Groot, tiene roles asignados, y el problema NO es configuración faltante en Groot (si le faltan roles → `VALIDO_GROOT`).
- **Acción**: Derivar a **IAM Soporte** (`57102`).
- **Comentario sugerido**:
  > "Hola, verificamos que tu configuración en Groot está correcta pero detectamos un problema de sincronización con el sistema. Derivamos al equipo de IAM para que puedan investigar y restaurar el acceso."
- **Fuente**: Análisis histórico (3 tickets: SSHP-1493771, SSHP-1491358, SSHP-1482519).

### R-DER-22 — Errores funcionales o pantalla en blanco en LMS (no involucra configuración de usuario) → LMS
- **Señales**:
  - ES: "LMS pantalla en blanco", "LMS no carga", "LMS muestra CAD incorrecto", "reps aparecen en site incorrecto en LMS", "LMS cargando indefinidamente", "pérdida de bolhas en LMS sin cambio en Groot".
  - PT: "LMS tela em branco", "LMS não carrega", "LMS mostra CAD incorreto", "reps aparecem no site incorreto no LMS", "LMS carregando indefinidamente", "perda de bolhas no LMS sem mudança no Groot".
  - EN: "LMS blank screen", "LMS not loading", "LMS shows incorrect CAD", "reps appear in wrong site in LMS", "LMS loading indefinitely", "loss of bubbles in LMS without change in Groot".
  - El reporte es sobre **LMS** (Labour Management System): pantalla en blanco, CAD/site incorrecto, bolhas que desaparecen — y la configuración en Groot/Kraken está correcta.
- **Razón**: Si el usuario está correctamente configurado en Groot pero LMS muestra datos incorrectos o no carga, el problema es del sistema LMS. Groot Soporte no tiene herramientas para corregir inconsistencias internas de LMS.
- **Verificación previa**: Confirmar que no es un problema de R-DER-12 (horas Be a Rep) ni de configuración faltante en Groot. Si al usuario le faltan roles en Groot → `VALIDO_GROOT`.
- **Acción**: Derivar a **LMS** (equipo Labour Management).
- **Automatización**: Habilitada. Option id en `$SKILL_DIR/knowledge/jira-field-options.md`.
- **Comentario sugerido**:
  > "Hola, verificamos tu configuración en Groot y está correcta. El problema parece ser funcional de LMS. Derivamos al equipo de LMS para que puedan investigar."
- **Fuente**: Análisis histórico (2 tickets: SSHP-1475187, SSHP-1470659).

### R-DER-23 — Errores en AppSheet (SHE, GEMBA) → Equipo SHE/AppSheet
- **Señales**:
  - ES: "AppSheet error", "Something has gone wrong en AppSheet", "Internal Server Error AppSheet", "no carga GEMBA", "no carga SHE", "error 500 AppSheet".
  - PT: "Erro no AppSheet", "Something has gone wrong no AppSheet", "Internal Server Error no AppSheet", "não carrega GEMBA", "não carrega SHE", "erro 500 AppSheet".
  - EN: "AppSheet error", "Something has gone wrong in AppSheet", "Internal Server Error AppSheet", "cannot load GEMBA", "cannot load SHE", "error 500 AppSheet".
  - El reporte menciona una URL de `appsheet.com/start/...` con errores como "Something has gone wrong", "Internal Server Error" o la app no carga.
- **Razón**: AppSheet SHE y GEMBA son aplicaciones externas mantenidas por otro equipo. Groot Soporte no tiene acceso ni herramientas para diagnosticar errores internos de AppSheet. El equipo de SHE gestiona estas apps.
- **Verificación previa**: Confirmar que la URL reportada es de `appsheet.com` y el error NO está relacionado con permisos de usuario en Groot (si el usuario no puede loguearse → verificar primero en Groot).
- **Acción**: Derivar a **Equipo SHE/AppSheet**.
- **Automatización**: Habilitada. Option id en `$SKILL_DIR/knowledge/jira-field-options.md`.
- **Comentario sugerido**:
  > "Hola, el error reportado ocurre en AppSheet (plataforma externa). Groot Soporte no administra esa herramienta. Derivamos al equipo responsable de SHE/GEMBA para que puedan investigar."
- **Fuente**: Análisis histórico (2 tickets: SSHP-1434223, SSHP-1435140).

### R-DER-24 — Error de validación al guardar en Groot por atributo/rol/permiso faltante (error esperable, no sistémico) → IAM Soporte
- **Señales**:
  - ES: "No es posible guardar los cambios", "El atributo X es obligatorio", "debe tener un valor por defecto", "error al guardar: atributo obligatorio", "debe corregir lo siguiente", "no se puede salvar las alteraciones".
  - PT: "Não é possível salvar as alterações", "O atributo X é obrigatório", "deve ter um valor padrão", "erro ao salvar: atributo obrigatório", "você deve corrigir o seguinte", "nao e possivel salvar as alteracoes".
  - EN: "Cannot save changes", "Attribute X is required", "must have a default value", "error saving: mandatory attribute", "you must correct the following".
  - El usuario intenta editar/guardar un cambio en Groot (quitar facility, cambiar rol, modificar atributos) y la herramienta muestra un **mensaje de validación** indicando que un campo obligatorio no está completo o que falta un valor por defecto.
  - El error **no** es un crash, timeout, 500, ni comportamiento inesperado del sistema — es la herramienta validando correctamente que los datos están incompletos.
- **Razón**: Groot Soporte atiende **solo errores sistémicos** (bugs, crashes, fallos inesperados). Los errores de validación por atributos/roles/permisos faltantes son **comportamiento esperado** de la herramienta: está correctamente bloqueando un guardado inválido. La configuración de atributos obligatorios y valores por defecto es responsabilidad de IAM / gestión de usuarios.
- **Verificación previa**: Confirmar que el error reportado es un mensaje de validación (texto del tipo "atributo X es obligatorio" / "debe tener valor por defecto") y **no** un error sistémico (500, timeout, "ocurrió un error inesperado", stack trace, pantalla en blanco). Si el error es sistémico real → reclasificar como `VALIDO_GROOT`.
- **Distinción clave**: Un "error al guardar" puede ser sistémico (bug) o de validación (esperable). Solo es `VALIDO_GROOT` si el sistema falla de forma **inesperada** (error no controlado, crash, timeout). Si el sistema muestra un mensaje claro indicando qué campo falta o qué condición no se cumple → es validación, no bug.
- **Acción**: Derivar a **IAM Soporte**.
- **Comentario sugerido**:
  > "Hola, el error que reportan es una validación esperada de la herramienta indicando que hay un atributo o configuración obligatoria faltante. Esto no es un error sistémico de Groot. Derivamos a IAM Soporte para que puedan asistir con la configuración de los atributos requeridos."
- **Fuente**: SSHP-1518473, 2026-07-14. Ticket reporta "Não é possível salvar as alterações: El atributo Service Center es obligatorio / debe tener un valor por defecto" al intentar retirar un facility — validación esperada, no bug.

---

## Comentario universal — auto-descarte de alta confianza

> ⚡ Reglas marcadas con ⚡ son **alta confianza**: el texto del ticket es suficiente para aplicarlas sin verificación en Groot admin. `/groot-queue classify` puede ejecutar su descarte automáticamente.

Cuando `/groot-queue classify` auto-descarta tickets de reglas ⚡, **usa este comentario** en lugar del comentario por regla:

> "Hola, desde Groot/Kraken Soporte atendemos exclusivamente errores sistémicos: bugs, comportamientos inesperados o fallos de la herramienta que no pueden resolverse por autogestión. La asignación o cambio de roles, permisos, atributos y configuraciones operativas — incluyendo errores de validación por datos faltantes — no es responsabilidad de este equipo y debe gestionarla el responsable de usuarios de su operación."

**Rejection reason** a usar en la transición: `[R] Funcionalidad existente` (id: `81170`), salvo que la tabla de `discard.md` indique otro para la regla específica.

**Excepción — R-DESC-14**: para esta regla, el comentario universal se complementa con la explicación específica porque el motivo de cierre es distinto (baja en SSFF, no gestión de permisos):
> "Hola, desde Groot/Kraken Soporte atendemos exclusivamente errores sistémicos. Los usuarios internos dados de baja en SSFF no pueden reactivarse manualmente desde Groot — cuando SSFF los reactive, la cuenta se actualizará automáticamente."

---

## Algoritmo de triage (para `list` y `classify`)

Para cada ticket abierto, evaluar en este orden y asignar el **primer** veredicto que matchee:

1. **R-DER-12** _[clasificación activa; no ejecutar derivación automáticamente]_ → si el reporte menciona errores, diferencias o inconsistencias en la contabilidad de horas de Be a Rep con impacto en LMS / Labour Management System.
2. **R-DER-22** → si LMS muestra pantalla en blanco, CAD/site incorrecto o bolhas que desaparecen, y la configuración en Groot/Kraken está correcta (no es R-DER-12 ni configuración faltante).
3. **R-DER-06** → si LDAP `ext_*` aparece como **cuenta Meli** en Kioske/TOTEM y no puede cambiar contraseña.
4. **R-DER-07** → si la herramienta afectada es **Shield** y el flujo es cambio de líder para colaboradores externos.
5. **R-DER-09** → si el reporte menciona "tax id inválido", "identificador tributario inválido", "Identificador tributario invalido", "CUIT inválido", "CPF inválido", "documento inválido" (frontend o bulk).
6. **R-DER-11** → si al crear/dar de alta un colaborador el error es "Tax_id has already been used" / ES "tax id ya utilizado" / PT "tax_id já utilizado" (documento **válido** pero ya en uso; distinto de R-DER-09 que es tax id *inválido*).
7. **R-DER-10** → si el usuario final ve un mensaje tipo "no perteneces a envíos" / "no pertence a envios" al intentar crear cuenta o desbloquearla (y por eso no puede conocer su LDAP).
8. **R-DER-08** → si el pedido es **cambio de nombre** del usuario (first/last name), sin error técnico de Groot.
9. **R-DER-13** _[asignación automática vía shuffle — célula interna Nexus, sin squad Jira]_ → si la URL afectada es `xtools.adminml.com/tools/pidgey/*` (notificaciones), `xtools.adminml.com/tools/alfred/*` (tickets, aprobaciones, procesos masivos) o Chat Interno, y el problema no involucra configuración de usuario en Groot.
10. **R-DER-14** → si la solicitud pide dar de **alta / crear / registrar** un nodo o valor nuevo que no existe en Kraken (ej. "alta de nodo NEX", "registrar nodo", "crear valor nuevo").
11. **R-DER-15** → si un usuario está desactivado/expirado en Groot y no puede ser reactivado por autogestión (error al reactivar, cuenta expirada sin opción de recovery).
12. **R-DER-16** → si la creación de usuario(s) falla con error de SuccessFactors / "datos inválidos" / "identificador tributario" (pero **no** es documento inválido — para eso R-DER-09 — ni documento duplicado — para eso R-DER-11).
13. **R-DER-20** → si el usuario estaba activo y perdió acceso a WMS/LMS sin que nadie modificara su configuración en Groot (desincronización IAM↔downstream).
14. **R-DER-17** → si el usuario tiene roles/bolhas/warehouse correctos en Groot pero **WMS/Logistics no refleja esos permisos** o presenta errores funcionales (pantalla en blanco, error 403, reloading, botones deshabilitados).
15. **R-DER-18** → si la solicitud es puramente **operativa de WMS** (gestión de paquetes, envíos, shipments) y no involucra usuarios, permisos ni roles.
16. **R-DER-23** → si la URL afectada es `appsheet.com/start/...` y el error es "Something has gone wrong" / "Internal Server Error" (apps SHE/GEMBA externas a Groot).
17. **R-DER-04** → si la URL afectada es `envios.adminml.com/logistics/...` / **package-management** / app nav / componente externo y el usuario está correctamente configurado en Groot/Kraken.
18. **R-DER-05** → si el tema es de **clasificación/taxonomía** de proceso madre en la tool Groot o issues de **app nav** (no un error real de Groot).
19. **R-DER-01** → si menciona "tag azul", "no es cuenta de envíos", "conta não é de envios", "sin opción de deshabilitar", o el admin (accediendo al perfil en la tool de Groot) ve que "no puede habilitar al usuario" porque "no pertenece a envíos / no pertenece a Mercado Envío" / PT "não pertence às remessas" / "nao pertence as remessas" / EN "does not belong to shipping" / "not a shipping account" (cuenta desactivada que piden reactivar; IAM debe ajustar el flag de shipping).
20. **R-DER-02** → si menciona "app nav", "navegación del app", "navegação" sin señal de R-DER-05.
21. **R-DER-03** → si menciona "vincular cuenta", "desvincular", "cuenta Meli vs ext_", "cambio de contraseña" (sin señal de Kioske/TOTEM que apunte a R-DER-06).
22. **R-DER-24** → si el usuario reporta un "error al guardar" en Groot pero el mensaje es una **validación** (ej. "atributo X es obligatorio", "debe tener un valor por defecto", "deve corrigir o seguinte") y **no** un error sistémico (500, timeout, crash). Es comportamiento esperado, no bug.
23. **R-DESC-03** → si el usuario reporta que en xtools / autogestión "no aparece CAD" / "não aparece CAD" / "no puedo seleccionar facility" + contexto de visitar otro site.
24. **R-DESC-06** → si el usuario afectado es **rep** y el reporte es previo al clock-in físico del día en el site objetivo.
25. **R-DESC-07** → si reps no ven una bolha/función y la verificación confirma que **están** en el facility correcto.
26. **R-DESC-13** ⚡ → si pide liberar bolha/permisos/roles para una función operativa sin error técnico de Groot, y la acción corresponde al gestor de aplicación u operación.
27. **R-DESC-08** ⚡ → si el requester menciona "learning completado", "training hub", "learning hub" y pide asignación de rol post-capacitación.
28. **R-DESC-04** → si es pedido de **cambio de líder / supervisor directo** sin error técnico (lista de usuarios a mover + nuevo líder).
29. **R-DESC-09** ⚡ → si pide **remover** un rol a un operario y no hay error técnico reportado.
30. **R-DESC-05** → si hay error "no autorizado" / "not authorized" o solicitud de permisos para un módulo/URL específico y el usuario **sí** logra loguearse.
31. **R-DESC-02** ⚡ → si es solicitud de **asignación de rol** a usuario (sin error técnico) y la cuenta **no** tiene tag azul.
32. **R-DESC-10** ⚡ → si pide **asignar / cambiar / quitar un valor de atributo** (CAD, facility, atributo operativo) sin error técnico, y no matchea R-DESC-03 / R-DESC-06 / R-DESC-07.
33. **R-DESC-18** → si el usuario no puede crear Labour Share para ninguno de sus HCs y la verificación confirma que tiene posición `analyst` (no `team_lead` ni `supervisor`).
34. **R-DESC-01** → si proviene de **Opex Full / SMO** y fue derivado fuera de ventana (>15 días de aging al llegar a Groot, posterior a 2025-10-28).
35. **R-DESC-11** ⚡ → si el problema ocurre en un sistema externo a Groot/Kraken (ej. HCM Rostering) y no hay error en ninguna herramienta de Groot.
36. **R-DESC-12** ⚠️ _[pendiente validación — clasificar como `REVISAR_MANUAL` hasta confirmar copy con Francisco Gonzalez]_ → si el reporte es una jerarquía que cambió automáticamente en LMS (sin solicitud manual) y el contexto apunta a un sync de Rostering, clasificar como `REVISAR_MANUAL` hasta validar el copy de descarte.
37. **R-DESC-14** ⚡ → si un usuario interno dado de baja en SSFF aparece inactivo en Groot y no puede reactivarse manualmente.
38. **R-DESC-15** → si roles previos no se restauran tras expirar un rol temporal **por incompatibilidades de roles que ya no se exceptúan** (regla de auditoría del 14 de marzo). ⚠️ **NO aplicar** si el rol temporal nunca impactó en la operación, el retorno no se ejecutó, o el proceso falló completamente — en esos casos el veredicto es `VALIDO_GROOT` (bug real del proceso de roles temporales).
39. **R-DESC-16** → si el usuario reporta jerarquía/gestor incorrecto en Groot pero la verificación confirma que el valor coincide con SSFF (SuccessFactors).
40. **R-DESC-17** → si el usuario reporta que no puede acceder a sistemas/tools cuyas URLs NO pertenecen al dominio de Groot (`envios.adminml.com/tools/auth/*`).
41. **R-DESC-19** ⚡ → si la solicitud pide ejecutar una operación estándar que la tool ya provee por autogestión, sin error técnico, y no matchea ninguna regla más específica anterior.
42. Si ninguna regla matchea → `VALIDO_GROOT` (si la categoría del ticket está en los runbooks de `runbooks.md`) o `REVISAR_MANUAL` (si no hay categoría clara).

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
- Archivar el caso concreto en `solutions/<categoria>/` solo si agrega una señal, excepción, causa raíz o procedimiento reusable que no esté documentado en esta regla ni en otro solution.
- Mantener el **comentario sugerido** tal cual lo escribió el equipo (es copy validado para responder al usuario). Si es necesario normalizar tildes o puntuación, hacerlo mínimamente y sin alterar el sentido.
- Siempre incluir el campo **Fuente** con autor + ticket + fecha. Agregar link a `solutions/` únicamente cuando exista un caso reusable materializado.
- Si un fix deja de ser válido (regresión), marcar la regla con `[DEPRECATED — fecha]` pero no borrarla (historial).
