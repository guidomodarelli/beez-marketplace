# Preflight de Grid Sharing

Contrato central para verificar que `groot-queue` puede usar Grid Sharing antes de cualquier operación.

La configuración máquina-legible es `knowledge/config/grid-sharing.json`. El checker es `scripts/check-groot-queue-readiness.sh`. Este documento no replica endpoints, identificadores, URLs ni timeouts: esos valores se leen siempre desde el JSON.

## Gate global

El preflight es un gate global, read-only y bloqueante. Debe ejecutarse antes de Jira, Slack, escritura local persistente o cualquier otra acción de un comando operativo.

Quedan exentos:

- `setup`, porque debe permanecer disponible para diagnosticar y remediar el entorno.
- Cualquier invocación que contenga el token exacto `--help` o `-h`, porque la ayuda no debe depender de Grid.

La entrada vacía y los comandos desconocidos que el dispatcher resuelva a `start` no están exentos.

Solo se continúa cuando el checker termina con exit code `0` y el objeto de `stdout` contiene `ok: true`. Una variable de entorno, la presencia textual de una skill o la disponibilidad aparente de un tool no sustituyen este resultado.

## Provider handling

El checker acepta exclusivamente:

```text
--provider claude|codex|copilot|auto
[--reuse-result FILE]
```

No acepta flags repetidos, valores faltantes ni argumentos adicionales.

- `claude`: usa el inventario JSON oficial de Claude Code.
- `codex`: usa el inventario JSON oficial de Codex para `tech-plugins-marketplace`.
- `copilot`: falla de forma cerrada porque actualmente no existe un inventario oficial que permita verificar instalación, estado, versión y path.
- `auto`: intenta primero `codex` y luego `claude`, y selecciona el primer provider cuyo inventario, plugin, versión y skill local sean verificables. No selecciona Copilot por mera presencia del ejecutable.

Un provider explícito nunca hace fallback a otro provider.

## Checks

El checker conserva el resultado de cada capa en `checks` y los fallos en `failures`, sin incluir bodies remotos, headers completos, identidad, tokens ni paths de instalación.

1. Dependencias locales: `jq` y `curl`.
2. Contrato de `knowledge/config/grid-sharing.json`.
3. Inventario oficial del provider, plugin instalado y habilitado.
4. Skill requerida legible dentro del install path resuelto por el inventario.
5. Versión del plugin con SemVer estricto.
6. Transporte read-only de Grid.
7. Compatibilidad de versión.
8. Identidad resuelta por el edge y acceso mediante VPN.
9. Lectura general mínima de documentos propios.
10. Lectura del documento requerido.

Los responses exitosos también deben cumplir su contrato mínimo:

- `ping`: body normalizado exactamente igual a `pong`.
- `skill_version`: `up_to_date` y `update_required` booleanos; si existe `version`, debe ser SemVer estricto. Solo pasa con `up_to_date: true` y `update_required: false`; cualquier indicación de update produce `PLUGIN_VERSION_INCOMPATIBLE`.
- `identity`: `caller_id`, `ldap`, `email` y `auth_path` como strings no vacíos, e `is_public` booleano. Los valores nunca se emiten.
- `general_read`: objeto con `documents` como array de objetos.
- `required_document`: metadata mínima con `doc_id` igual al ID configurado, `title` y `doc_type` no vacíos, y `content_storage: s3`.

`active_context` es siempre `null`: no se infiere contexto activo a partir de instalación, habilitación ni filesystem.

Las llamadas HTTP usan únicamente la configuración central, HTTPS, método `GET`, redirects deshabilitados y temporales privados. Se permite como máximo un retry para errores de transporte o respuestas `5xx`. No se reintentan respuestas `401`, `403`, `404` ni `429`. Un `Retry-After` solo se conserva si es un entero acotado y nunca se usa para dormir o reintentar dentro del checker.

## Reutilización del resultado

`--reuse-result FILE` permite reutilizar exclusivamente un resultado exitoso producido durante la misma invocación de alto nivel.

Antes de leerlo, el checker exige:

- path absoluto compuesto solo por caracteres permitidos;
- archivo regular, sin symlink y legible;
- owner igual al usuario actual cuando `stat` permite verificarlo;
- ningún permiso de lectura para group u other;
- schema version compatible;
- provider compatible con el solicitado;
- `ok: true`, `exit_code: 0`, `active_context: null` y ausencia de fallos;
- todos los checks obligatorios presentes y exitosos;
- antigüedad no negativa y dentro de la ventana definida en la configuración central.

El checker sanitiza el objeto antes de volver a emitirlo y conserva su timestamp original; una cadena de reutilizaciones no renueva la vigencia. No confía en una variable de entorno ni en contenido adicional del archivo.

Si el archivo es seguro pero su contenido está vencido, incompleto, malformado o no corresponde al provider, se ignora y se ejecuta un preflight nuevo. Si el path o los atributos del archivo son inseguros, se devuelve `70` sin leer su contenido.

## Contrato de salida

`stdout` contiene siempre exactamente un objeto JSON. Los diagnósticos técnicos seguros se escriben en `stderr`.

Campos estables:

- `schema_version`
- `provider`
- `ok`
- `exit_code`
- `active_context`
- `source`: `fresh` o `reused`
- `checked_at_epoch`
- `checks`
- `failures`

Los nombres de checks, estados y failure codes son identificadores técnicos en inglés. Las remediaciones orientadas a personas se presentan en español según este contrato.

## Exit codes y precedencia

| Exit code | Categoría | Remediación |
|---:|---|---|
| `0` | Ready | Continuar con el comando operativo y reutilizar el resultado dentro de la misma invocación. |
| `2` | Argumentos o provider | Corregir flags/valores. Para Copilot, usar Claude Code o Codex hasta que exista inventario oficial verificable. |
| `10` | Inventario, plugin o skill | Instalar o habilitar el plugin correcto, o reparar su instalación. No instalar, habilitar ni actualizar sin aprobación explícita. |
| `20` | Red o servicio | Verificar conectividad y disponibilidad de Grid; reintentar la invocación cuando el servicio esté accesible. |
| `21` | Versión | Actualizar el plugin con aprobación explícita y volver a ejecutar el preflight. |
| `22` | Identidad o VPN | Conectar la VPN corporativa y verificar que el edge pueda resolver la identidad. |
| `23` | Lectura general | Verificar permisos generales de lectura y el contrato de respuesta de Grid. |
| `24` | Documento requerido | Solicitar acceso al documento requerido; un `403` indica ACL insuficiente y un `404` recurso no disponible. |
| `25` | Rate limit | Esperar el valor sanitizado de `retry_after_seconds` cuando esté disponible y ejecutar una nueva invocación. |
| `70` | Dependencia local o contrato interno | Instalar la dependencia faltante o corregir configuración/archivo de reutilización inseguro antes de reintentar. |

Cuando existen varios fallos, `failures` los conserva y el exit code se elige con esta precedencia fija:

```text
70 > 2 > 10 > 25 > 20 > 21 > 22 > 23 > 24
```

La precedencia solo decide el exit code del proceso; no oculta los demás failure codes.
