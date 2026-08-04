# Entry Point De Comandos

Contrato central para decidir si una invocación puede leer y ejecutar su subcomando. Lo aplican tanto el dispatcher multi-provider como los wrappers de Claude Code.

## Entradas

Recibir conceptualmente:

- el subcomando canónico ya resuelto;
- los argumentos completos de la invocación, conservando sus tokens;
- el provider resuelto por el caller: `claude`, `codex` o `auto`.

Usar como `$SKILL_DIR` el directorio del skill desde el que se leyó este contrato. El dispatcher debe resolver el provider y los aliases antes de aplicarlo; los wrappers Claude deben pasar su subcomando canónico y el provider `claude`.

## Protocolo

Aplicar este orden sin adelantar lecturas, tools ni acciones del subcomando.

### 1. Resolver ayuda

Si cualquier argumento es exactamente `--help` o `-h`:

- No ejecutar el gate, shell, MCP, Jira, Slack ni ninguna acción del subcomando.
- Para `setup`, responder directamente que diagnostica ACLI, integraciones, Grid Sharing y Fury Services/FuryDocs sin inspeccionar settings del provider. Explicar que invocación normal instala o actualiza automáticamente assets conocidos cuando sea necesario y deja OAuth, VPN, `/reload-plugins`, restart, acceso o conflictos ambiguos como pasos humanos. Incluir `/groot-queue:setup` para Claude Code y `/groot-queue setup` para Codex. Incluir frase explícita: `Esta ayuda no ejecuta checker, discovery MCP, Bash, Jira, Slack ni diagnósticos; tampoco modifica el entorno.` No mencionar ni citar archivos, nombres de archivos, paths, anchors, secciones, fuentes internas ni repositorio.
- Para cualquier otro subcomando, leer únicamente `$SKILL_DIR/subcommands/<subcomando-canónico>.md` y responder su ayuda sin ejecutar sus acciones.
- No tratar como ayuda coincidencias parciales como `--help=true` ni texto que solo contenga esas cadenas.
- Deshabilitar la ejecución y detener la invocación después de responder.

### 2. Eximir `setup`

Si el subcomando canónico es `setup`, habilitar su ejecución sin correr el gate global. El subcomando realiza su propio diagnóstico shell y runtime completo y fresco.

### 3. Aplicar la fase shell

Para cualquier otro subcomando, incluido `start`:

1. Antes de leer el archivo del subcomando, usar Jira o Slack o realizar escrituras, leer y aplicar `$SKILL_DIR/knowledge/config/groot-queue-readiness.md`.
2. Ejecutar `$SKILL_DIR/scripts/check-groot-queue-readiness.sh --provider <provider>`. Si existe `GROOT_QUEUE_READINESS_RESULT_FILE`, pasar además `--reuse-result "$GROOT_QUEUE_READINESS_RESULT_FILE"`; nunca confiar directamente en la variable ni leer el archivo por cuenta propia.
3. Continuar solo si el checker termina con exit code `0` y su único objeto JSON contiene simultáneamente `schema_version: 2`, `scope: "shell"`, `ok: true` y `exit_code: 0`.
4. Ante cualquier otro resultado:
   - si subcomando canónico es `start`, leer y ejecutar `subcommands/setup.md` automáticamente con provider resuelto. `setup` aplica reparación allowlisted y diagnóstico fresco. Si termina con shell + runtime completamente listos, no renderizar tabla ni cierre completo de `setup`: conservar estado combinado, continuar `start` y transmitir solo resumen seguro para línea `Reparaciones: ✅ ...`. Si requiere acción humana o sigue bloqueado, mostrar output autocontenido de `setup` sin reemplazar cierre ni comando de revalidación y detener `start`. Para Claude Code debe terminar con `/groot-queue:setup`; para Codex con `/groot-queue setup`;
   - para cualquier otro subcomando, deshabilitar ejecución, detener invocación y presentar remediaciones correspondientes sin exponer payload completo, bodies, identidad, tokens ni paths.
5. Conservar JSON exitoso únicamente como resultado validado de fase shell durante invocación actual.

### 4. Aplicar la fase runtime MCP

Inmediatamente después del éxito shell y todavía antes de leer el archivo del subcomando, usar Jira o Slack o realizar escrituras:

1. Exigir tools de discovery inequívocamente pertenecientes al server MCP `fury` del provider actual. En Claude Code, preferir `mcp__plugin_fury-services_fury__list_components` y `mcp__plugin_fury-services_fury__list_tools`; aceptar solo equivalentes exactos expuestos por ese mismo server.
2. Si ambas tools no están inequívocamente disponibles, fallar con `FURY_RUNTIME_DISCOVERY_TOOLS_UNAVAILABLE` sin invocar ninguna tool.
3. Invocar **solo** `list_components`, sin argumentos. Si la llamada falla o la respuesta es inválida, fallar con `FURY_COMPONENT_DISCOVERY_FAILED`.
4. Exigir un componente cuyo `name` sea exactamente `furydocs`. Si falta, fallar con `FURYDOCS_COMPONENT_UNAVAILABLE`.
5. Invocar **solo** `list_tools` con `component="furydocs"`. Si la llamada falla o la respuesta es inválida, fallar con `FURY_TOOL_DISCOVERY_FAILED`.
6. Exigir los nombres exactos `get_doc_structure` y `get_doc_file`; permitir tools adicionales. Si falta alguno, fallar con `FURYDOCS_REQUIRED_TOOLS_UNAVAILABLE`.
7. No invocar `get_doc_structure`, `get_doc_file` ni ninguna otra tool documental. No mostrar ni persistir payloads completos de discovery.
8. Ante cualquier fallo:
   - si subcomando canónico es `start`, ejecutar `setup` automáticamente. Si reparación + diagnóstico fresco dejan runtime listo, suprimir output completo de `setup`, continuar `start` con estado combinado y mostrar solo línea segura de reparaciones; si requiere `/reload-plugins`, restart u otra acción humana, mostrar output de `setup` sin alterar comando de revalidación (`/groot-queue:setup` en Claude Code o `/groot-queue setup` en Codex) y detener `start`;
   - para cualquier otro subcomando, deshabilitar ejecución, detener invocación y presentar remediación segura.
9. Conservar éxito runtime solo como estado conceptual en memoria durante esta invocación; no serializarlo, guardarlo ni reutilizarlo en otra invocación.

### 5. Habilitar ejecución y conservar continuidad

Solo después de que corresponda la exención de `setup` o ambas fases del gate resulten exitosas, habilitar la lectura y ejecución del subcomando.

Compartir el estado combinado de readiness con el subcomando y cualquier delegación interna. No volver a ejecutar discovery, probes ni el checker dentro de la misma invocación. `setup` no recibe ni reutiliza ese estado global porque ejecuta su propio diagnóstico fresco.
