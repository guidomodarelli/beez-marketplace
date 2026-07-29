# Jira Field Options — SSHP

Fuente de verdad centralizada para los option IDs de campos custom de Jira en el proyecto SSHP.
Los subcomandos deben leer este archivo para obtener los IDs; no hardcodear valores en otros archivos.

---

## `customfield_13781` — Squad destino (`DERIVATION_DESTINATION_SQUAD_FIELD`)

Campo usado en la transición `121` "Derivar a otro equipo".

| Equipo | option id |
|--------|-----------|
| IAM Soporte | `57102` |
| SMO (Randall) | `41817` |
| Helpdesk IA | `125821` |
| LMS | `19721` |
| SHE | `85286` |

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
