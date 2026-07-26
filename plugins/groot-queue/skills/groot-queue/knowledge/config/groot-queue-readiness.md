# Readiness De Groot Queue

Contrato central para verificar que `groot-queue` puede usar Grid Sharing y FuryDocs antes de cualquier operación.

La configuración máquina-legible es `knowledge/config/groot-queue-readiness.json`. El checker shell es `scripts/check-groot-queue-readiness.sh`. Este documento no replica endpoints, identificadores, URLs ni timeouts: esos valores se leen siempre desde el JSON.

Para onboarding y remediaciones orientadas a personas, consultar el [troubleshooting de la guía de Groot Queue](installation.md#troubleshooting). Esta referencia no modifica los checks, failure codes ni el gate definido aquí.

## Gate global de dos fases

El readiness es un gate global, read-only y bloqueante con dos fases complementarias:

1. **Shell reusable**: valida dependencias, configuración, inventario del provider, Grid Sharing y la instalación local/CLI MCP de Fury. Produce un JSON serializable con `schema_version: 2` y `scope: "shell"` que puede reutilizarse de forma controlada dentro de una misma invocación de alto nivel.
2. **Runtime MCP no reusable**: valida las tools realmente inyectadas por el server Fury en el runtime activo. Su estado es conceptual, no se serializa, no se guarda en archivos ni variables de entorno y no puede reutilizarse entre invocaciones.

Quedan exentos:

- `setup`, porque debe permanecer disponible para diagnosticar ambas fases de forma fresca.
- Cualquier invocación que contenga el token exacto `--help` o `-h`, porque la ayuda no debe depender del readiness.

La entrada vacía y los comandos desconocidos que el dispatcher resuelva a `start` no están exentos.

Solo se continúa cuando ambas fases están listas. Una variable de entorno, la presencia textual de una skill, una declaración MCP o la disponibilidad aparente de una tool no sustituyen el estado combinado.

## Fase shell

### Provider handling

El checker acepta exclusivamente:

```text
--provider claude|codex|copilot|auto
[--reuse-result FILE]
```

No acepta flags repetidos, valores faltantes ni argumentos adicionales.

- `claude`: usa los inventarios oficiales de plugins y MCP de Claude Code.
- `codex`: usa los inventarios oficiales de Codex para `tech-plugins-marketplace` y su CLI MCP.
- `copilot`: falla de forma cerrada porque actualmente no existe un inventario oficial que permita verificar instalación, estado, versión y path.
- `auto`: intenta primero `codex` y luego `claude`, y selecciona el primer provider cuyo readiness shell completo sea verificable. No selecciona Copilot por mera presencia del ejecutable.

Un provider explícito nunca hace fallback a otro provider.

### Checks shell y failure codes

El checker conserva el resultado de cada capa en `checks` y los fallos en `failures`. Los checks exitosos aparecen exactamente en este orden:

| Check | Failure codes propios |
|---|---|
| `dependencies` | `LOCAL_DEPENDENCY_UNAVAILABLE` |
| `configuration` | `CONFIGURATION_INVALID` |
| `provider_inventory` | `PROVIDER_CLI_UNAVAILABLE`, `PROVIDER_INVENTORY_UNSUPPORTED`, `PROVIDER_INVENTORY_FAILED`, `PROVIDER_INVENTORY_INVALID` |
| `grid_plugin` | `PLUGIN_NOT_INSTALLED`, `PLUGIN_DISABLED`, `PLUGIN_INVENTORY_AMBIGUOUS`, `PLUGIN_INVENTORY_INVALID` |
| `grid_required_skill` | `REQUIRED_SKILL_UNAVAILABLE` |
| `fury_plugin` | `FURY_PLUGIN_NOT_INSTALLED`, `FURY_PLUGIN_DISABLED`, `FURY_PLUGIN_INVENTORY_AMBIGUOUS`, `FURY_PLUGIN_INVENTORY_INVALID` |
| `fury_required_skill` | `FURY_REQUIRED_SKILL_UNAVAILABLE` |
| `fury_manifest` | `FURY_MANIFEST_UNAVAILABLE`, `FURY_MANIFEST_INVALID` |
| `fury_mcp_declaration` | `FURY_MCP_DECLARATION_UNAVAILABLE`, `FURY_MCP_DECLARATION_INVALID` |
| `fury_mcp_cli` | `FURY_MCP_CLI_CHECK_FAILED`, `FURY_MCP_NOT_CONFIGURED`, `FURY_MCP_CONNECTION_UNAVAILABLE`, `FURY_MCP_CLI_RESPONSE_INVALID` |
| `ping` | `GRID_TRANSPORT_FAILED`, `GRID_SERVICE_UNAVAILABLE`, `GRID_RATE_LIMITED`, `GRID_PING_FAILED`, `GRID_PING_FORBIDDEN`, `GRID_PING_NOT_FOUND`, `GRID_PING_RESPONSE_INVALID` |
| `skill_version` | `PLUGIN_VERSION_UNAVAILABLE`, `PLUGIN_VERSION_INVALID`, `PLUGIN_VERSION_INCOMPATIBLE`, `PLUGIN_VERSION_FORBIDDEN`, `PLUGIN_VERSION_ENDPOINT_NOT_FOUND`, `PLUGIN_VERSION_RESPONSE_INVALID` |
| `identity` | `GRID_IDENTITY_UNAVAILABLE`, `GRID_IDENTITY_FORBIDDEN`, `GRID_IDENTITY_ENDPOINT_NOT_FOUND`, `GRID_IDENTITY_RESPONSE_INVALID` |
| `general_read` | `GENERAL_READ_FAILED`, `GENERAL_READ_FORBIDDEN`, `GENERAL_READ_ENDPOINT_NOT_FOUND`, `GENERAL_READ_RESPONSE_INVALID` |
| `required_document` | `REQUIRED_DOCUMENT_READ_FAILED`, `REQUIRED_DOCUMENT_FORBIDDEN`, `REQUIRED_DOCUMENT_NOT_FOUND`, `REQUIRED_DOCUMENT_RESPONSE_INVALID` |

Los checks no ejecutados conservan el failure code concreto de la capa que los bloqueó. Los fallos del contrato de ejecución son `INVALID_ARGUMENTS`, `INVALID_PROVIDER`, `INVALID_REUSE_RESULT_PATH`, `REUSE_RESULT_FILE_UNSAFE`, `TEMP_DIRECTORY_UNAVAILABLE` e `INTERNAL_CONTRACT_FAILED`.

Los responses exitosos de Grid también deben cumplir su contrato mínimo:

- `ping`: body normalizado exactamente igual a `pong`.
- `skill_version`: `up_to_date` y `update_required` booleanos; si existe `version`, debe ser SemVer estricto. Solo pasa con `up_to_date: true` y `update_required: false`.
- `identity`: `caller_id`, `ldap`, `email` y `auth_path` como strings no vacíos, e `is_public` booleano. Los valores nunca se emiten.
- `general_read`: objeto con `documents` como array de objetos.
- `required_document`: metadata mínima con el ID configurado, `title` y `doc_type` no vacíos, y `content_storage: s3`.

`active_context` es siempre `null`: no se infiere contexto activo a partir de instalación, habilitación ni filesystem.

Las llamadas HTTP usan únicamente la configuración central, HTTPS, método `GET`, redirects deshabilitados y temporales privados. Se permite como máximo un retry para errores de transporte o respuestas `5xx`. No se reintentan respuestas `401`, `403`, `404` ni `429`. Un `Retry-After` solo se conserva si es un entero acotado y nunca se usa para dormir o reintentar dentro del checker.

### Reutilización del resultado shell

`--reuse-result FILE` permite reutilizar un resultado shell exitoso. El launcher garantiza que el resultado provenga de la misma invocación de alto nivel al crearlo dentro de su directorio temporal privado; el checker valida el archivo recibido, pero no demuestra por sí solo esa identidad de invocación.

Antes de leerlo, el checker exige:

- path absoluto compuesto solo por caracteres permitidos;
- directorio padre inmediato real, sin symlink, con owner igual al usuario actual y sin permisos para group u other;
- archivo regular, sin symlink, legible, con owner igual al usuario actual y sin permisos para group u other;
- `schema_version: 2` y `scope: "shell"`;
- provider compatible con el solicitado;
- `ok: true`, `exit_code: 0`, `active_context: null` y ausencia de fallos;
- todos los checks shell obligatorios presentes y exitosos;
- antigüedad no negativa y dentro de la ventana definida en la configuración central.

El checker valida primero el directorio padre, abre el archivo, verifica sus atributos sobre el descriptor abierto y crea un snapshot privado desde ese mismo descriptor. Luego sanitiza el objeto antes de volver a emitirlo y conserva su timestamp original; una cadena de reutilizaciones no renueva la vigencia. No confía en una variable de entorno ni en contenido adicional del archivo.

El modo `0700` del directorio impide acceso de otros UID, pero no aísla procesos que ejecutan con el mismo UID. El gate reduce reemplazos desde directorios compartidos; no ofrece una garantía atómica contra procesos del mismo usuario ni contra todas las carreras de resolución de ancestros.

Si el archivo es seguro pero su contenido está vencido, incompleto, malformado o no corresponde al provider, se ignora y se ejecuta un readiness shell nuevo. Si el path, el directorio padre o los atributos del archivo son inseguros, se devuelve `70` sin consumir su contenido.

### Contrato de salida shell

`stdout` contiene siempre exactamente un objeto JSON. Los diagnósticos técnicos seguros se escriben en `stderr`.

Campos estables:

- `schema_version`: exactamente `2`;
- `scope`: exactamente `shell`;
- `provider`;
- `ok`;
- `exit_code`;
- `active_context`;
- `source`: `fresh` o `reused`;
- `checked_at_epoch`;
- `checks`;
- `failures`.

Solo un exit code `0` junto con `schema_version: 2`, `scope: "shell"`, `ok: true` y `exit_code: 0` habilita la fase runtime.

## Fase runtime MCP

Esta fase se ejecuta en el runtime actual después del éxito shell y antes de leer el subcomando, consultar Jira o Slack o realizar escrituras. `setup` la ejecuta como diagnóstico independiente incluso cuando la fase shell falla.

Usar únicamente tools de discovery inequívocamente pertenecientes al server MCP `fury` del provider actual. En Claude Code se prefieren:

- `mcp__plugin_fury-services_fury__list_components`
- `mcp__plugin_fury-services_fury__list_tools`

También se admiten nombres equivalentes exactos expuestos por ese mismo server `fury`. No aceptar tools ambiguas, de otro server o inferidas por similitud.

Aplicar estrictamente este orden:

1. Exigir ambas tools de discovery. Si no están inequívocamente disponibles, fallar sin invocar ninguna.
2. Invocar **solo** `list_components` y sin argumentos. Exigir una respuesta válida que incluya un componente con `name` exactamente igual a `furydocs`.
3. Invocar **solo** `list_tools` con `component="furydocs"`. Exigir una respuesta válida cuyos nombres incluyan exactamente `get_doc_structure` y `get_doc_file`; se permiten tools adicionales.
4. No invocar `get_doc_structure`, `get_doc_file` ni ninguna otra tool documental durante readiness.

### Checks runtime y failure codes

| Check conceptual | Failure code exacto | Condición |
|---|---|---|
| `fury_runtime_discovery_tools` | `FURY_RUNTIME_DISCOVERY_TOOLS_UNAVAILABLE` | Las dos tools de discovery de Fury no están inequívocamente disponibles. |
| `fury_component_discovery` | `FURY_COMPONENT_DISCOVERY_FAILED` | `list_components` falla o devuelve una respuesta inválida. |
| `furydocs_component` | `FURYDOCS_COMPONENT_UNAVAILABLE` | No aparece `name: "furydocs"` de forma exacta. |
| `fury_tool_discovery` | `FURY_TOOL_DISCOVERY_FAILED` | `list_tools(component="furydocs")` falla o devuelve una respuesta inválida. |
| `furydocs_required_tools` | `FURYDOCS_REQUIRED_TOOLS_UNAVAILABLE` | Falta `get_doc_structure` o `get_doc_file`. |

El estado runtime exitoso existe solo en memoria conceptual durante la invocación actual. No tiene schema JSON, archivo de resultado, variable de entorno, timestamp reutilizable ni mecanismo de cache. Al delegar trabajo dentro de la misma invocación, transmitir que el readiness combinado ya fue validado; no repetir discovery.

## Readiness combinado y privacidad

El readiness combinado está listo únicamente cuando la fase shell y todos los checks runtime están listos. Conservarlo durante todo el subcomando y sus delegaciones sin repetir checker ni probes.

No mostrar ni persistir payloads completos de discovery, bodies remotos, headers completos, identidad, tokens, credenciales, configuración sensible ni paths de instalación. Las respuestas orientadas a personas incluyen solo estado, nombres de checks, failure codes seguros y remediaciones en español.

## Exit codes shell y remediaciones

| Exit code | Categoría | Remediación |
|---:|---|---|
| `0` | Shell ready | Ejecutar la fase runtime MCP. |
| `2` | Argumentos o provider | Corregir flags/valores. Para Copilot, usar Claude Code o Codex hasta que exista inventario oficial verificable. |
| `10` | Inventario, plugins, skills o MCP local | Instalar, habilitar o reparar el recurso correcto. No hacerlo sin aprobación explícita. |
| `20` | Red o servicio | Verificar conectividad y disponibilidad de Grid; reintentar cuando el servicio esté accesible. |
| `21` | Versión | Actualizar el plugin con aprobación explícita y volver a ejecutar readiness. |
| `22` | Identidad o VPN | Conectar la VPN corporativa y verificar que el edge pueda resolver la identidad. |
| `23` | Lectura general | Verificar permisos generales de lectura y el contrato de respuesta de Grid. |
| `24` | Documento requerido | Solicitar acceso al documento requerido; un `403` indica ACL insuficiente y un `404` recurso no disponible. |
| `25` | Rate limit | Esperar el valor sanitizado de `retry_after_seconds` cuando esté disponible y ejecutar una nueva invocación. |
| `70` | Dependencia local o contrato interno | Instalar la dependencia faltante o corregir configuración/archivo de reutilización inseguro antes de reintentar. |

Cuando existen varios fallos shell, `failures` los conserva y el exit code se elige con esta precedencia fija:

```text
70 > 2 > 10 > 25 > 20 > 21 > 22 > 23 > 24
```

La precedencia solo decide el exit code del proceso; no oculta los demás failure codes. Los fallos runtime no tienen exit code de proceso propio: bloquean conceptualmente la invocación y se reportan con su failure code exacto.
