# 🚀 Groot Queue — Guía de instalación

Guía canónica para instalar, configurar, diagnosticar, actualizar y desinstalar `groot-queue`.

`groot-queue` monitorea y gestiona la cola de soporte de Groot en Jira: lista y clasifica tickets, sugiere soluciones, revisa SLA, genera alertas, asigna tickets y ejecuta acciones controladas. Algunos subcomandos son read-only y otros pueden modificar Jira, Slack o la knowledge base; revisá siempre la acción antes de aprobarla.

<a id="alcance-y-providers"></a>
## 🎯 Alcance y providers

| Provider | Estado | Uso recomendado |
|---|---|---|
| Claude Code | Operacional y principal | Seguí esta guía de principio a fin. |
| Codex | Operacional | Instalá con los comandos del [anexo Codex](#anexo-codex) y aplicá el mismo contrato de readiness. |

El subcomando `setup` **diagnostica y repara automáticamente** dependencias y AI assets conocidos cuando detecta evidencia inequívoca de instalación o update necesario. Invocar `setup` autoriza esas remediaciones acotadas. OAuth, VPN, `/reload-plugins`, reinicio del provider, solicitudes de acceso y decisiones ante conflictos siguen requiriendo intervención de la persona.

<a id="recuperacion-conversacional-de-ai-assets"></a>
## 🧭 Recuperación conversacional de AI assets

Cuando `setup` detecte un plugin, skill, MCP, CLI o acceso faltante, esta guía funciona como fuente interna para construir respuesta. Persona que usa plugin puede no tener repositorio disponible: **no mostrar paths, nombres de archivos, anchors ni instrucciones como “consultá guía”**. Tampoco citar documentos internos, secciones, fuentes ni contratos aunque prompt pida explicar fundamento. Leer procedimiento aplicable y reproducir directamente en chat comandos y pasos necesarios; respuesta debe parecer conocimiento operativo nativo, no resumen de archivos.

### Formato obligatorio de la remediación

Agrupar failures que compartan causa y responder una sola vez por recurso con este orden:

- `### <Recurso> — <estado o failure code seguro>`
- `Acción automática`: comando ejecutado, resultado real y verificación posterior.
- `Tenés que hacer vos`: OAuth, VPN, `/reload-plugins`, restart, acceso o decisión ambigua, si aplica.
- `Comandos para copiar y pegar`: bloque `bash` con comandos exactos para provider activo.
- `Validación`: bloque `text` o `bash` con slash command o comando read-only.

Omitir bloques vacíos. Si una acción no puede automatizarse desde la sesión actual, decirlo de forma directa y mantener comando copiable. No afirmar que recurso quedó listo hasta verificarlo.

### Política de automatización

Invocar `setup` otorga autorización permanente para ejecutar remediaciones idempotentes de allowlist cuando estado observado demuestra que son necesarias:

- instalar dependencias locales documentadas mediante Homebrew (`bash`, `jq`, `curl`, `acli`);
- agregar marketplaces oficiales conocidos de Groot o Tech Plugins cuando falten;
- instalar, habilitar o actualizar plugins conocidos: `groot-queue`, `grid-sharing`, `fury-services`, `atlassian` y `slack`;
- actualizar ACLI cuando propia CLI reporte versión nueva;
- actualizar Grid Sharing cuando check `skill_version` reporte `update_required: true`;
- ejecutar inventarios y checks read-only después de cada bloque mutable.

Aplicar límites:

- Inspeccionar estado antes de mutar y ejecutar solo acción mínima necesaria. No reinstalar ni actualizar un asset listo sin evidencia de update.
- Usar exclusivamente IDs, scopes y repositorios oficiales documentados. Para tap ACLI no confiable, verificar origen exacto `https://github.com/atlassian/homebrew-acli.git` antes de confiarlo; cualquier otro origen requiere decisión humana.
- Reintentar diagnóstico una sola vez después de reparaciones locales. No crear loops de instalación/update.
- Si runtime activo conserva inventario anterior, pedir `/reload-plugins`; si sigue stale, pedir cerrar y abrir provider.
- No intentar ejecutar slash commands desde Bash. Presentarlos como paso manual dentro de sesión activa.
- No automatizar login OAuth, selección de workspace, conexión VPN, solicitud de ACL ni reinicio del provider. Se puede iniciar CLI de login solo si persona lo pidió explícitamente y está disponible interacción necesaria.
- No desinstalar, reemplazar configuración existente, resolver inventarios ambiguos, elegir entre integraciones duplicadas ni ampliar permisos automáticamente. Mostrar conflicto y pedir decisión.
- No crear conexión MCP `fury` manual: `fury-services` es propietario de esa declaración.

### Matriz de recuperación

| Failure o síntoma | Causa agrupada | Acción que debe aparecer inline |
|---|---|---|
| `LOCAL_DEPENDENCY_UNAVAILABLE` | Dependencia local | Mostrar checks y comando Homebrew específico para herramienta faltante. |
| `PROVIDER_CLI_UNAVAILABLE` | Provider ausente | Mostrar instalación de Claude Code o indicar instalación/actualización de Codex según provider activo. |
| `PLUGIN_NOT_INSTALLED`, `REQUIRED_SKILL_UNAVAILABLE` | Grid Sharing incompleto | Agregar marketplace técnico si falta, instalar o actualizar `grid-sharing`, recargar plugins y revalidar. Nunca copiar skill ni crear symlink manual. |
| `PLUGIN_DISABLED` | Grid Sharing deshabilitado | Mostrar comando oficial de habilitación si CLI lo soporta; si no, indicar gestión desde `/plugin`. Recargar y revalidar. |
| `FURY_PLUGIN_NOT_INSTALLED`, `FURY_REQUIRED_SKILL_UNAVAILABLE`, `FURY_MANIFEST_UNAVAILABLE`, `FURY_MCP_DECLARATION_UNAVAILABLE`, `FURY_MCP_NOT_CONFIGURED` | Fury Services incompleto | Instalar o actualizar `fury-services` desde marketplace técnico. No crear otro MCP `fury`; plugin es propietario de declaración. Recargar/reiniciar y revalidar. |
| `FURY_PLUGIN_DISABLED` | Fury Services deshabilitado | Habilitar plugin existente, recargar y revalidar; no agregar segunda instalación. |
| `FURY_MCP_CONNECTION_UNAVAILABLE`, `FURY_RUNTIME_DISCOVERY_TOOLS_UNAVAILABLE`, `FURY_COMPONENT_DISCOVERY_FAILED`, `FURYDOCS_COMPONENT_UNAVAILABLE`, `FURY_TOOL_DISCOVERY_FAILED`, `FURYDOCS_REQUIRED_TOOLS_UNAVAILABLE` | Runtime Fury stale o incompleto | Verificar plugin y MCP, ejecutar `/reload-plugins`, reiniciar si persiste y repetir `setup`. No reconstruir transporte ni invocar tools documentales como probe. |
| `GRID_TRANSPORT_FAILED`, `GRID_SERVICE_UNAVAILABLE`, `GRID_PING_FAILED` | Red o servicio Grid | Confirmar VPN/conectividad, esperar si servicio no está disponible y repetir invocación. |
| `GRID_RATE_LIMITED` | Rate limit | Mostrar espera segura sanitizada cuando exista; no hacer loop ni reintento agresivo. |
| `PLUGIN_VERSION_INCOMPATIBLE` | Grid desactualizado | Actualizar automáticamente `grid-sharing`, verificar inventario y pedir reload/restart cuando runtime lo requiera. |
| `GRID_IDENTITY_UNAVAILABLE`, `GRID_IDENTITY_FORBIDDEN` | VPN o identidad edge | Pedir conectar/reconectar VPN aprobada. No sugerir tokens, cookies ni headers manuales. |
| `GENERAL_READ_FORBIDDEN`, `REQUIRED_DOCUMENT_FORBIDDEN`, `REQUIRED_DOCUMENT_NOT_FOUND` | ACL o recurso requerido | Pedir acceso autorizado al recurso indicado por nombre seguro. No mostrar IDs internos ni probar otros recursos. |
| ACLI ausente o no autenticado | Jira CLI | Mostrar instalación Homebrew, login web, status y revalidación. Login queda como paso humano. |
| Atlassian MCP ausente o no autenticado | Integración Atlassian | Recomendar plugin oficial, OAuth desde `/mcp`, una única integración y validación. No hardcodear `cloudId`. |
| Slack MCP ausente o no autenticado | Integración Slack | Recomendar plugin oficial, OAuth desde `/mcp` y validar solo con `alerts --dry-run`. |

### Comandos por provider

Para **Claude Code**, tomar comandos exactos de secciones de instalación, actualización, recarga y troubleshooting de esta misma guía. Mostrar solo comandos necesarios para failures presentes. Cuando falten Grid y Fury, agregar marketplace técnico una sola vez y luego instalar ambos plugins.

Para **Codex**, tomar comandos exactos de anexo Codex. Codex requiere reinicio después de cambios de plugins o MCP; no presentar `/reload-plugins` como disponible. Si una capacidad de instalación/update no está documentada para recurso, no inventar comando: explicar paso manual verificable.

### Cierre de recuperación

Después de diagnosticar recursos:

1. Ejecutar automáticamente acciones de allowlist necesarias y agruparlas por asset.
2. Reportar comando, éxito/falla real y verificación read-only; no afirmar reparación sin evidencia.
3. Repetir diagnóstico local una sola vez.
4. Mostrar pasos humanos pendientes en orden mínimo.
5. Terminar con comando de revalidación del provider activo:

```text
/groot-queue:setup
```

Para Codex:

```text
/groot-queue setup
```

Si revalidación vuelve a fallar, responder solo con failures actuales; no repetir recursos ya verificados ni afirmar éxito parcial como setup completo. Detener respuesta después de revalidación u oferta de ejecución: no agregar postscript, explicación de fuentes, “qué hice y por qué” ni detalles internos del checker.

<a id="fuentes-de-verdad"></a>
## 🧭 Fuentes de verdad

Esta guía es la fuente humana de onboarding. Los detalles técnicos permanecen en sus fuentes canónicas:

| Tema | Fuente de verdad |
|---|---|
| Configuración máquina-legible de readiness | [`groot-queue-readiness.json`](groot-queue-readiness.json) |
| Contrato, checks, failure codes y remediaciones técnicas | [`groot-queue-readiness.md`](groot-queue-readiness.md) |
| Checker shell read-only | [`check-groot-queue-readiness.sh`](../../scripts/check-groot-queue-readiness.sh) |
| Precondiciones y seguridad de Atlassian MCP | [`atlassian-mcp.md`](atlassian-mcp.md) |
| Configuración de Slack MCP | [`slack-mcp.md`](slack-mcp.md) |
| Roster operativo `TEAM` | [`SKILL.md` — Equipo para asignación](../../SKILL.md#equipo-para-asignación) |

No copies IDs de documentos, endpoints internos, argumentos MCP, timeouts ni el catálogo completo de failure codes a otros archivos. Consultá las fuentes anteriores cuando necesites ese nivel de detalle.

<a id="1-prerrequisitos-en-macos"></a>
## 🧰 1. Prerrequisitos en macOS

Necesitás acceso corporativo, GitHub por SSH y una cuenta autorizada para los servicios que uses. Verificá primero; instalá solo lo que falte.

### 🤖 Claude Code

```bash
claude --version
claude doctor
```

Instalación estable con Homebrew:

```bash
brew install --cask claude-code
```

Después ejecutá `claude` y completá el login en el browser. La instalación nativa oficial también está documentada en [Claude Code setup](https://code.claude.com/docs/en/setup).

### 🔐 Git y acceso SSH

```bash
git --version
ssh -T git@github.com
```

Si Git falta:

```bash
brew install git
```

`ssh -T` puede terminar con un código distinto de cero aunque la autenticación sea válida; verificá el mensaje, no publiques su salida si contiene datos de identidad.

### 🌐 VPN corporativa

Conectate a la VPN corporativa mediante el cliente aprobado para macOS. No hay un instalador público que esta guía deba ejecutar. Grid depende de que el edge corporativo resuelva tu identidad; estar conectado a internet no alcanza.

La validación segura se realiza más adelante con `setup`. No agregues headers, cookies ni tokens manuales para intentar reemplazar la VPN o la identidad del edge.

### 🐚 Bash, `jq` y `curl`

```bash
bash --version
jq --version
curl --version
```

Si falta alguna herramienta:

```bash
brew install bash jq curl
```

`groot-queue` reutiliza `curl` + `jq` para consultar hechos mínimos de usuario Kraken y evidencia read-only de Labour Share cuando diagnóstico lo requiere. Esas consultas dependen de Fury Access Groups y de identidad resuelta por edge corporativo; no forman parte del gate global de readiness porque comandos y tickets sin contexto deben seguir funcionando.

Un `401`/`403` deja verificación como indeterminada. No agregar `Authorization`, cookies, `x-tiger-token` ni otros headers manuales. Solicitar acceso autorizado para endpoints definidos en [`kraken-user-data.json`](kraken-user-data.json) o [`labor-share-data.json`](labor-share-data.json), y seguir procedimientos de [`kraken-user-data.md`](kraken-user-data.md) o [`labor-share-data.md`](labor-share-data.md). Integración Labour Share admite únicamente operaciones GET `execution` y `processes`; nunca creación ni sink.

### 🎫 ACLI

```bash
acli --version
```

Si no está instalado:

```bash
brew tap atlassian/homebrew-acli
brew install acli
```

Autenticá por OAuth en el browser:

```bash
acli jira auth login --web
```

Seleccioná el sitio corporativo correcto y verificá el estado con:

```bash
acli jira auth status
```

Usá `acli jira auth status` como único check de autenticación para este onboarding.

## 📦 2. Instalar `groot-queue` en Claude Code

Agregá el marketplace y el plugin en scope `user`:

```bash
claude plugin marketplace add --scope user git@github.com:melisource/fury_groot-marketplace.git
claude plugin install --scope user groot-queue@groot-marketplace
```

Verificá el inventario sin exponer configuración sensible:

```bash
claude plugin list --json
```

La entrada `groot-queue@groot-marketplace` debe estar instalada y habilitada.

<a id="3-permisos-acli-en-claude-code"></a>
## 🔒 3. Autorización ACLI en Claude Code

No hace falta configurar permisos persistentes para instalar, diagnosticar ni completar `groot-queue setup`. Claude Code puede solicitar autorización cuando un comando necesite ejecutar ACLI; las operaciones mutables siempre quedan sujetas a la política activa del provider.

Los allowlists persistentes son una optimización opcional para reducir prompts en proyectos confiables, no una condición de readiness. Si decidís configurarlos, preferí permisos read-only acotados para autenticación, búsqueda y lectura; aprobá asignaciones, transiciones y ediciones caso por caso. No amplíes el patrón a todo `acli` ni a todo `Bash` sin aceptar explícitamente ese alcance.

<a id="4-atlassian-mcp"></a>
## 🔗 4. Atlassian MCP

### ⭐ Opción recomendada: plugin oficial

```bash
claude plugin install --scope user atlassian@claude-plugins-official
```

En una sesión de Claude Code, abrí `/mcp` y completá OAuth para el workspace corporativo correcto. Podés revisar el inventario con `claude plugin list --json` y el estado de las conexiones con `claude mcp list`.

### 🛠️ Alternativa manual: endpoint `authv2`

Usá esta alternativa solo si no podés instalar el plugin oficial:

```bash
claude mcp add --scope user --transport http atlassian https://mcp.atlassian.com/v1/mcp/authv2
claude mcp login atlassian
```

**Elegí una sola opción.** No combines el plugin oficial y la conexión manual: dos conexiones Atlassian pueden inyectar tools duplicadas o ambiguas. Antes de continuar, revisá `claude plugin list --json` y `claude mcp list`, y dejá activa una única integración.

### 🛡️ Reglas de seguridad Atlassian

- Usá OAuth; no pegues API tokens, cookies ni headers en prompts, settings o comandos.
- Resolvé el `cloudId` dinámicamente desde los recursos que devuelve Atlassian MCP. Nunca lo hardcodees ni publiques su valor.
- Para acciones que escriben notas internas de Jira Service Management, el MCP debe ofrecer capacidad real de **internal note**. Un comentario público no es un fallback seguro.
- Si no puede garantizarse visibilidad interna, abortá la automatización y completá la acción manualmente en Jira.
- La regla exacta de visibilidad y los modos ABORTAR/DEGRADAR viven en [`atlassian-mcp.md`](atlassian-mcp.md).

<a id="5-slack-mcp"></a>
## 💬 5. Slack MCP

Instalá el plugin oficial en scope `user`:

```bash
claude plugin install --scope user slack@claude-plugins-official
```

Completá OAuth para el workspace correcto cuando Claude Code lo solicite. Verificá que el plugin esté instalado y que Slack aparezca conectado en `/mcp`; no envíes un mensaje de prueba real.

La verificación funcional segura es:

```text
/groot-queue:alerts --dry-run
```

`--dry-run` debe preparar el resumen sin enviar DMs. Si el runtime no ofrece las capacidades necesarias de Slack, mantené el flujo en dry-run y repará OAuth antes de habilitar envíos.

<a id="6-grid-sharing-y-vpn"></a>
## 🧩 6. Grid Sharing y VPN

Grid Sharing y Fury Services se distribuyen desde el mismo marketplace técnico. Agregalo **una sola vez**:

```bash
claude plugin marketplace add --scope user git@github.com:melisource/fury_tech-plugins-marketplace.git
```

Instalá Grid Sharing:

```bash
claude plugin install --scope user grid-sharing@tech-plugins-marketplace
```

Grid requiere:

- plugin instalado y habilitado;
- skill requerida disponible;
- VPN corporativa conectada;
- identidad resuelta por el edge corporativo;
- versión compatible y permisos de lectura sobre el documento requerido.

Usá `/groot-queue:setup` como probe seguro. El checker realiza únicamente lecturas configuradas en el contrato técnico, no emite la identidad y no necesita headers o tokens manuales.

Nunca intentes reparar un `401`/`403` agregando `Authorization`, cookies, headers de identidad o tokens a `curl`. Eso puede exponer credenciales y no sustituye la autenticación del edge. Para detalles de red, versión y acceso, consultá [Troubleshooting](#troubleshooting) y el [contrato técnico de readiness](groot-queue-readiness.md).

<a id="7-fury-services-y-furydocs"></a>
## 📚 7. Fury Services y FuryDocs

Instalá Fury Services desde el marketplace técnico ya agregado:

```bash
claude plugin install --scope user fury-services@tech-plugins-marketplace
```

El plugin declara el MCP `fury` mediante `mcp-remote-proxy`; no copies ni reconstruyas manualmente sus argumentos, endpoint o headers. Verificá las capas locales y la conexión con:

```bash
command -v mcp-remote-proxy
claude mcp get plugin:fury-services:fury
```

No compartas la salida completa si incluye paths o configuración del transporte. Si `mcp-remote-proxy` no aparece o `fury` no conecta, recargá primero los plugins y, si persiste, reiniciá Claude Code. Luego ejecutá `setup` para obtener la remediación correspondiente; no agregues una segunda declaración MCP manual.

En runtime, el server `fury` debe exponer el componente y las tools documentales definidos en el [contrato técnico de readiness](groot-queue-readiness.md#fase-runtime-mcp). El diagnóstico solo descubre capacidades; no lee documentación. Las tools documentales se usan después, únicamente cuando un comando operativo las necesita.

## 👥 8. Configurar el TEAM

El roster se mantiene exclusivamente en [`SKILL.md` — Equipo para asignación](../../SKILL.md#equipo-para-asignación). No lo copies a esta guía.

Un `TEAM` vacío impide que `assign-unassigned` reparta tickets, pero no redefine ni reemplaza el readiness de Grid/FuryDocs para los demás comandos.

<a id="9-recargar-y-validar"></a>
## 🔄 9. Recargar y validar

Después de instalar o cambiar plugins, dentro de una sesión activa ejecutá:

```text
/reload-plugins
```

Reiniciá Claude Code si:

- actualizaste un plugin: la CLI indica que el restart es necesario para aplicar la nueva versión;
- `/reload-plugins` no incorpora skills o MCP nuevos;
- `fury`, Atlassian o Slack siguen mostrando una conexión stale después de completar OAuth.

Validá en este orden:

```text
/groot-queue:setup --help
/groot-queue:setup
/groot-queue:list
```

1. `setup --help` explica el diagnóstico sin ejecutar tools.
2. `setup` verifica ACLI, integraciones, TEAM y readiness completo; auto-instala/actualiza assets allowlisted cuando sea necesario y no inspecciona ni modifica settings del provider.
3. Ejecutá un comando operativo solo cuando `setup` indique que las fases obligatorias están listas. No omitas ni fuerces el gate de readiness.

## 🖥️ 10. Launcher opcional

El launcher `run-groot-queue` es una conveniencia para iniciar un provider en un proceso hijo. **No es un prerrequisito** y no instala `groot-queue`, ACLI, plugins, MCPs ni credenciales.

Desde el directorio del plugin:

```bash
./scripts/install.sh
```

El instalador publica un wrapper ejecutable en `~/.local/bin/run-groot-queue` con el source absoluto de la copia actual. Puede pedir confirmación si existe otro destino. Cada proceso queda anclado a una sola copia, incluso si reinstalás el wrapper mientras está corriendo. Volvé a ejecutar `./scripts/install.sh` después de actualizar o mover el plugin y revisá la interfaz con `run-groot-queue --help`.

El launcher usa un directorio temporal y no depende de settings locales del proyecto llamador. `setup` valida ACLI, integraciones y readiness desde ese proceso sin exigir configuración persistente del provider.

Antes de usarlo, revisá [`run-groot-queue.sh`](../../../../scripts/run-groot-queue.sh): el launcher inicia procesos hijos con permisos amplios de tools para poder operar. Usalo solo desde una copia confiable y no lo tomes como bypass del readiness ni de las confirmaciones de acciones mutables.

<a id="troubleshooting"></a>
## 🩺 Troubleshooting

Empezá siempre por `/groot-queue:setup`; reportá solo estados, nombres de checks y failure codes seguros. No pegues payloads completos, identidad, headers, tokens, paths privados ni datos de tickets.

### 🤖 Claude, inventario o dependencias locales

**Síntomas:** CLI ausente, JSON inválido, plugin no instalado/deshabilitado, skill faltante o MCP local no declarado.

1. Verificá `claude --version`, `claude doctor`, `jq --version` y `curl --version`.
2. Revisá `claude plugin list --json` y `claude mcp list`.
3. Ejecutá `/reload-plugins`; reiniciá si el inventario sigue stale.
4. Seguí las familias `dependencies`, `configuration`, `provider_inventory`, `grid_*` y `fury_*` del [readiness técnico](groot-queue-readiness.md#fase-shell).

### 🌐 Grid: red, servicio o rate limit

**Síntomas:** transport failure, servicio no disponible, timeout o rate limit.

1. Confirmá la VPN y reintentá en una invocación nueva.
2. No agregues headers ni reintentos manuales agresivos.
3. Si `setup` informa espera segura, respetala.
4. Consultá las remediaciones de [exit codes shell](groot-queue-readiness.md#exit-codes-shell-y-remediaciones).

### 🔐 Grid: versión, identidad o acceso

**Síntomas:** plugin desactualizado, edge sin identidad, lectura general prohibida o documento requerido inaccesible.

1. Para identidad, reconectá la VPN y verificá que usás el acceso corporativo correcto.
2. Para versión, `setup` actualiza automáticamente cuando check confirma update requerido; después reiniciá Claude Code si runtime sigue stale.
3. Para permisos, solicitá acceso por el canal corporativo; no pruebes otros IDs ni copies el ID requerido desde la configuración.
4. No interpretes un plugin instalado como readiness exitoso: todas las capas deben pasar.

### 📚 Fury Services o FuryDocs

**Síntomas:** `mcp-remote-proxy` ausente, MCP `fury` desconectado o capacidades runtime requeridas no visibles.

1. Verificá `command -v mcp-remote-proxy` y `claude mcp get plugin:fury-services:fury`.
2. Ejecutá `/reload-plugins` y después reiniciá si el transporte sigue stale.
3. No crees otra entrada `fury` ni copies argumentos internos del manifiesto.
4. Revisá la [fase runtime MCP](groot-queue-readiness.md#fase-runtime-mcp).

### 🎫 ACLI o Atlassian

**Síntomas:** `acli jira auth status` falla, OAuth expiró, workspace incorrecto, tools duplicadas o no existe capacidad de internal note.

1. Repetí `acli jira auth login --web` si ACLI perdió autenticación.
2. En `/mcp`, completá de nuevo OAuth para la única integración Atlassian elegida.
3. Eliminá la ambigüedad entre plugin oficial y conexión manual antes de reintentar.
4. No hardcodees `cloudId` ni conviertas una nota interna en comentario público.
5. Consultá [`atlassian-mcp.md`](atlassian-mcp.md).

### 💬 Slack

**Síntomas:** Slack no aparece en `/mcp`, OAuth expiró o faltan tools de búsqueda/envío.

1. Verificá el plugin oficial en `claude plugin list --json`.
2. Completá OAuth nuevamente desde `/mcp`.
3. Probá solo `/groot-queue:alerts --dry-run` hasta que el diagnóstico esté listo.
4. Consultá [`slack-mcp.md`](slack-mcp.md).

## 💾 Preservar conocimiento local antes del lifecycle

`save`, `add-rule` y los flujos de auditoría pueden escribir soluciones, reglas y logs dentro del directorio activo de la skill. Antes de actualizar o desinstalar, exportá ese estado a una ubicación privada:

```bash
set -euo pipefail
umask 077

PLUGIN_ROOT="$(claude plugin list --json | jq -er '
  [.[] | select(.id == "groot-queue@groot-marketplace")]
  | if length == 1 and (.[0].installPath | type == "string") and (.[0].installPath | length > 0)
    then .[0].installPath
    else error("groot-queue installPath missing or ambiguous")
    end
')"
SKILL_ROOT="$PLUGIN_ROOT/skills/groot-queue"
[ -d "$SKILL_ROOT/knowledge" ]
[ -f "$SKILL_ROOT/SKILL.md" ]

BACKUP_ROOT="$(mktemp -d "$HOME/groot-queue-backup.XXXXXX")"
cp -R "$SKILL_ROOT/knowledge" "$BACKUP_ROOT/"
cp "$SKILL_ROOT/SKILL.md" "$BACKUP_ROOT/"
chmod -R go-rwx "$BACKUP_ROOT"
printf 'Backup created at %s\n' "$BACKUP_ROOT"
```

No continúes con update/uninstall si el bloque falla o si el backup no contiene `knowledge/` y `SKILL.md`. El backup puede contener datos internos de tickets: mantenelo fuera de repositorios y almacenamiento público. Después de actualizar, compará y fusioná el contenido revisado; no sobrescribas automáticamente reglas o soluciones nuevas del plugin.

En Codex, obtené el `source.path` del plugin instalado con `codex plugin list --json` y preservá los mismos recursos antes de `marketplace upgrade` o `plugin remove`.

## ⬆️ Actualizar de forma segura

Primero revisá el estado actual:

```bash
claude plugin list --json
claude plugin marketplace list
```

Luego actualizá únicamente los componentes que correspondan:

```bash
claude plugin marketplace update groot-marketplace
claude plugin update --scope user groot-queue@groot-marketplace

claude plugin marketplace update tech-plugins-marketplace
claude plugin update --scope user grid-sharing@tech-plugins-marketplace
claude plugin update --scope user fury-services@tech-plugins-marketplace

claude plugin update --scope user atlassian@claude-plugins-official
claude plugin update --scope user slack@claude-plugins-official
```

Reiniciá Claude Code y repetí la [secuencia de validación](#9-recargar-y-validar). Si usás launcher opcional, ejecutá de nuevo `./scripts/install.sh` desde copia actualizada para refrescar wrapper. `setup` aplica updates allowlisted solo con evidencia; esta sección conserva comandos manuales para lifecycle deliberado.

## 🗑️ Desinstalar de forma conservadora

Antes de desinstalar, verificá qué plugins y marketplaces siguen usando cada dependencia:

```bash
claude plugin list --json
claude plugin marketplace list
```

Para retirar solo `groot-queue` del scope `user`:

```bash
claude plugin uninstall --scope user --keep-data groot-queue@groot-marketplace
```

No uses `--prune` por defecto. Grid Sharing, Fury Services, Atlassian y Slack pueden ser dependencias compartidas por otros plugins o flujos; no las borres automáticamente. Eliminá un plugin compartido o un marketplace únicamente después de confirmar que ninguna otra instalación lo necesita.

Si el launcher opcional está instalado, verificá primero que sea el wrapper esperado y retiralo como acción separada:

```bash
grep -F 'run-groot-queue.sh' ~/.local/bin/run-groot-queue
rm ~/.local/bin/run-groot-queue
```

No ejecutes `rm` si el wrapper no contiene el source `scripts/run-groot-queue.sh` que esperás. La desinstalación del plugin no debe borrar `.claude/settings.local.json`, credenciales OAuth, configuración MCP ni datos compartidos sin una decisión explícita y separada.

<a id="anexo-codex"></a>
## 🧰 Anexo Codex

Codex usa el mismo plugin y contrato técnico, pero sus comandos no llevan `--scope user`. Instalación:

```bash
codex plugin marketplace add git@github.com:melisource/fury_groot-marketplace.git
codex plugin add groot-queue@groot-marketplace

codex plugin marketplace add git@github.com:melisource/fury_tech-plugins-marketplace.git
codex plugin add grid-sharing@tech-plugins-marketplace
codex plugin add fury-services@tech-plugins-marketplace
```

Configurá Atlassian y Slack con OAuth antes de validar la skill:

```bash
codex mcp add atlassian --url https://mcp.atlassian.com/v1/mcp/authv2
codex mcp login atlassian

# Slack no soporta Dynamic Client Registration: pedí un client ID aprobado al admin.
export SLACK_MCP_CLIENT_ID='<client-id-aprobado>'
codex mcp add slack --url https://mcp.slack.com/mcp --oauth-client-id "$SLACK_MCP_CLIENT_ID"
codex mcp login slack
```

Sin client ID registrado, no intentes un login genérico: mantené `alerts` en `--dry-run` hasta que el workspace admin provea la configuración OAuth.

Verificá inventario y conexiones:

```bash
codex plugin marketplace list
codex plugin list --json
codex mcp list
```

No hardcodees `cloudId`, tokens ni headers; los contratos operativos específicos siguen en las referencias de [Fuentes de verdad](#fuentes-de-verdad). El banner `start` puede mostrar checks MCP opcionales como no verificables bajo Codex; usá `codex mcp list` y `/groot-queue setup` como diagnóstico autoritativo.

Actualización del snapshot de cada marketplace:

```bash
codex plugin marketplace upgrade groot-marketplace
codex plugin marketplace upgrade tech-plugins-marketplace
```

Reiniciá Codex después de cambios de plugins o MCP y, ya con las tools cargadas, ejecutá:

```text
/groot-queue setup --help
/groot-queue setup
/groot-queue list
```

Para retirar únicamente Groot Queue de Codex:

```bash
codex plugin remove groot-queue@groot-marketplace
```

No retires Grid Sharing, Fury Services ni marketplaces compartidos sin comprobar antes que otros plugins no los necesiten.
