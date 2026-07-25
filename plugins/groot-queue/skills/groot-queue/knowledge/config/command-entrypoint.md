# Entry Point De Comandos

Contrato central para decidir si una invocación puede leer y ejecutar su subcomando. Lo aplican tanto el dispatcher multi-provider como los wrappers de Claude Code.

## Entradas

Recibir conceptualmente:

- el subcomando canónico ya resuelto;
- los argumentos completos de la invocación, conservando sus tokens;
- el provider resuelto por el caller: `claude`, `codex`, `copilot` o `auto`.

Usar como `$SKILL_DIR` el directorio del skill desde el que se leyó este contrato. El dispatcher debe resolver el provider y los aliases antes de aplicarlo; los wrappers Claude deben pasar su subcomando canónico y el provider `claude`.

## Protocolo

Aplicar este orden sin adelantar lecturas, tools ni acciones del subcomando.

### 1. Resolver ayuda

Si cualquier argumento es exactamente `--help` o `-h`:

- No ejecutar el gate, shell, Jira, Slack ni ninguna acción del subcomando.
- Para `setup`, responder directamente: `setup` verifica ACLI, MCPs, permisos, TEAM y el preflight completo de Grid Sharing; no instala ni modifica nada sin autorización explícita.
- Para cualquier otro subcomando, leer únicamente `$SKILL_DIR/subcommands/<subcomando-canónico>.md` y responder su ayuda sin ejecutar sus acciones.
- No tratar como ayuda coincidencias parciales como `--help=true` ni texto que solo contenga esas cadenas.
- Deshabilitar la ejecución y detener la invocación después de responder.

### 2. Eximir `setup`

Si el subcomando canónico es `setup`, habilitar su ejecución sin correr el gate global. El subcomando realiza su propio diagnóstico completo y fresco.

### 3. Aplicar el gate global

Para cualquier otro subcomando, incluido `start`:

1. Antes de leer el archivo del subcomando, Jira, Slack o realizar escrituras, leer y aplicar `$SKILL_DIR/knowledge/config/grid-sharing-preflight.md`.
2. Ejecutar `$SKILL_DIR/scripts/check-groot-queue-readiness.sh --provider <provider>`. Si existe `GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE`, pasar además `--reuse-result "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE"`; nunca confiar directamente en la variable ni leer el archivo por cuenta propia.
3. Continuar solo si el checker termina con exit code `0` y su JSON contiene `ok: true`.
4. Ante cualquier otro resultado, deshabilitar la ejecución, detener la invocación y presentar en español las remediaciones correspondientes a sus failure codes según `grid-sharing-preflight.md`, sin exponer bodies, identidad, tokens ni paths de instalación.
5. Conservar el JSON exitoso como resultado validado de Grid durante toda la invocación.

### 4. Habilitar ejecución y conservar continuidad

Solo después de que corresponda la exención de `setup` o el gate resulte exitoso, habilitar la lectura y ejecución del subcomando.

Compartir el resultado validado de Grid con el subcomando y cualquier delegación interna. No volver a ejecutar probes ni el checker dentro de la misma invocación. `setup` no recibe ni reutiliza ese estado global porque ejecuta su propio preflight fresco.
