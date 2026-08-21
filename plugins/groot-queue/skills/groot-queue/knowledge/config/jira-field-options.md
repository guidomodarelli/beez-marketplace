# Jira Field Options — SSHP

Fuente de verdad centralizada para los option IDs de campos custom de Jira en el proyecto SSHP.
Los subcomandos deben leer este archivo para obtener los IDs; no hardcodear valores en otros archivos.

---

## `customfield_13781` — Squad destino (`DERIVATION_DESTINATION_SQUAD_FIELD`)

Campo usado en la transición `121` "Derivar a otro equipo". Es además el campo que
identifica la **cola dueña** del ticket, así que es también el filtro de cola en JQL.

| Equipo | option id |
|--------|-----------|
| IAM Soporte | `57102` |
| SMO (Randall) | `41817` |
| Helpdesk IA | `125821` |
| LMS | `19721` |
| SHE | `85286` |

### Formas del campo según destino

El mismo campo se escribe distinto según dónde se use. Estas son las dos únicas formas válidas:

| Alias | Expansión | Dónde se usa |
|-------|-----------|--------------|
| `DERIVATION_DESTINATION_SQUAD_FIELD` | `customfield_13781` | Payload de `fields` para Jira/MCP (transición `121`). |
| `<SQUAD_FIELD_JQL>` | `cf[13781]` | Cualquier `--jql` que filtre por cola. |

Expandir el alias al valor real antes de ejecutar; no dejar el alias literal en el comando
ni en el payload.

> ⚠️ **En JQL el campo se referencia por field id, nunca por su nombre visible.** El nombre
> que muestra la UI de Jira es `Squad`, pero `Squad = Groot` no resuelve el option y la query
> falla al parsear:
>
> ```
> failed to parse JQL query: la opción 'groot' para el campo 'squad' no existe.
> ```
>
> El filtro de la cola Groot es `<SQUAD_FIELD_JQL> = "Groot"`, expandido a
> `cf[13781] = "Groot"`, respetando el escaping de comillas del contexto de shell
> (`\"Groot\"` dentro de `--jql "..."`, `"Groot"` dentro de `--jql '...'`).

---

## `customfield_14924` — Motivo de derivación

Campo usado en la misma transición `121`.

| Motivo | option id |
|--------|-----------|
| Solución parcial, otro Squad requerido | `20884` |
| Falta de información | `54593` |
| Herramientas resolución no disponibles | `20880` |
| Asignación incorrecta | `20879` |
| Procedimiento no resuelve el incidente | `20881` |
| Validado NO Crítico | `96238` |

---

## `customfield_19296` — Reason for rejection

Campo obligatorio en la transición `101` "Descartar" (pantalla JSM).

### Catálogo completo

| Razón | option id |
|-------|-----------|
| [R] Funcionalidad existente | `81170` |
| [R] Canal invalido | `81172` |
| [R] Categoría incorrecta | `81175` |
| [R] Cierre por agrupacion de tickets | `81176` |
| [R] Duplicados | `81177` |
| [R] Rechazado Datos Incorrectos | `81169` |
| [R] Procedimiento operativo indicado | `81171` |
| [R] Requerimiento rechazado por aprobadores | `81173` |
| [R] Usuario no valido para generar la solicitud | `81174` |
| [R] Cancelado por el usuario | `96919` |

### Razones estructuradas de descarte fuera de alcance

Solo estas opciones prueban por sí mismas que cierre corresponde a pedido fuera del alcance de Groot y permiten materialización histórica como `DESCARTADO`:

| Razón | ID |
|---|---|
| [R] Funcionalidad existente | `81170` |
| [R] Canal invalido | `81172` |
| [R] Categoría incorrecta | `81175` |
| [R] Procedimiento operativo indicado | `81171` |

`[R] Cancelado por el usuario`, duplicados, agrupación, rechazo de aprobadores, usuario no válido o datos incorrectos no prueban fuera de alcance sistémico y no habilitan una regla R-DESC histórica sin match versionado independiente.

### Mapeo por regla R-DESC

| Regla | Rejection Reason | ID |
|-------|------------------|----|
| R-DESC-01 (sin error sistémico) | [R] Rechazado Datos Incorrectos | `81169` |
| R-DESC-02 (asignación de roles autogestión) | [R] Funcionalidad existente | `81170` |
| R-DESC-03 (usuario ya tiene lo solicitado) | [R] Funcionalidad existente | `81170` |
| R-DESC-04 (cambio de líder autogestión) | [R] Funcionalidad existente | `81170` |
| R-DESC-05 (determinar rol/permiso de funcionalidad) | [R] Funcionalidad existente | `81170` |
| R-DESC-06 (canal inválido) | [R] Canal invalido | `81172` |
| R-DESC-07 (procedimiento operativo) | [R] Procedimiento operativo indicado | `81171` |
| R-DESC-08 (funcionalidad existente) | [R] Funcionalidad existente | `81170` |
| R-DESC-09 (cancelado por usuario) | [R] Cancelado por el usuario | `96919` |
| R-DESC-10 (determinar o aplicar atributos) | [R] Funcionalidad existente | `81170` |
| R-DESC-11 (sistema externo / HCM / no es Groot) | [R] Categoría incorrecta | `81175` |
| R-DESC-12 (requerimiento rechazado) | [R] Requerimiento rechazado por aprobadores | `81173` |
| R-DESC-13 (roles/permisos/atributos operativos) | [R] Funcionalidad existente | `81170` |
| R-DESC-15 (roles incompatibles) | [R] Funcionalidad existente | `81170` |
| R-DESC-17 (aplicación externa a Groot) | [R] Categoría incorrecta | `81175` |
| R-DESC-19 (configuración operativa genérica) | [R] Funcionalidad existente | `81170` |

---

## Semántica de workflow Jira SSHP

Los nombres visibles de estado y resolución pueden variar según idioma o configuración Jira. Esta sección es fuente única para compararlos en subcommands y referencias.

### Normalización y match

1. Aplicar `trim`, colapsar espacios repetidos, convertir a minúsculas y normalizar Unicode sin diacríticos.
2. Comparar por igualdad exacta después de normalizar. No usar substrings, coincidencias parciales ni traducciones inferidas.
3. Agregar aliases solo después de verificarlos contra transiciones, metadatos o tickets reales de SSHP.

### Estados semánticos

| Grupo | Aliases verificados |
|-------|---------------------|
| `WAITING_FOR_SUPPORT` | `Waiting for support`, `Esperando soporte`, `Esperando por Soporte` |
| `WAITING_FOR_CUSTOMER` | `Waiting for customer`, `Esperando al cliente` |
| `IN_PROGRESS` | `In Progress`, `En progreso`, `En curso` |

Un ticket abierto se determina preferentemente con `resolution = Unresolved`; un ticket cerrado se determina con `statusCategory = Done`. No inferir esos estados desde aliases nominales.

### Resoluciones históricas

| Grupo | Aliases verificados |
|-------|---------------------|
| `DISCARDED_RESOLUTION` | `Won't Do`, `Cancelled`, `Withdrawn`, `Rechazado` |
| `RESOLVED_RESOLUTION` | `Done`, `Fixed`, `Fix aplicado`, `Functionality`, `Cannot Reproduce` |

En análisis histórico, estos grupos complementan changelog y comentarios contemporáneos. Si ninguna fuente determina el desenlace, usar revisión manual.

### Resolver y transicionar de forma segura

1. Leer y normalizar el nombre de estado actual; resolverlo contra un único grupo semántico.
2. Para llegar a `IN_PROGRESS`, consultar transiciones disponibles y elegir una única transición cuyo destino pertenezca a `IN_PROGRESS`. Ejecutar con el ID o nombre real devuelto por Jira, nunca con un alias hardcodeado.
3. Releer el ticket y confirmar que su estado final pertenece a `IN_PROGRESS` antes de ejecutar una mutación dependiente, como asignar, comentar, descartar o consumir turno.
4. Si el estado no pertenece a un grupo, hay más de una transición candidata, no existe transición disponible o falla la verificación posterior, registrar `SKIP_ESTADO_NO_RECONOCIDO` o `REVISAR_MANUAL`. No realizar mutaciones dependientes.

IDs de workflow conocidos para SSHP: transición hacia progreso `21`, descarte `101` y derivación `121`. Los IDs no reemplazan la validación de estado y transición real.
