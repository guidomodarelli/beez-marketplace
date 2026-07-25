# Groot Queue

Guía canónica para instalar, configurar, diagnosticar, actualizar y desinstalar `groot-queue`.

`groot-queue` monitorea y gestiona la cola de soporte de Groot en Jira: lista y clasifica tickets, sugiere soluciones, revisa SLA, genera alertas, asigna tickets y ejecuta acciones controladas. Algunos subcomandos son read-only y otros pueden modificar Jira, Slack o la knowledge base; revisá siempre la acción antes de aprobarla.

## Alcance y providers

| Provider | Estado | Uso recomendado |
|---|---|---|
| Claude Code | Operacional y principal | Seguí esta guía de principio a fin. |
| Codex | Operacional | Instalá con los comandos del [anexo Codex](#anexo-codex) y aplicá el mismo contrato de readiness. |
| GitHub Copilot CLI | No operacional | El readiness técnico todavía no puede verificar su inventario. No intentes omitir el gate; consultá el contrato enlazado en [Fuentes de verdad](#fuentes-de-verdad). |

El subcomando `setup` **diagnostica** el entorno y muestra remediaciones. No instala, autentica, habilita, actualiza ni modifica componentes automáticamente. Toda acción mutable requiere aprobación explícita.

## Fuentes de verdad

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

## 1. Prerrequisitos en macOS

Necesitás acceso corporativo, GitHub por SSH y una cuenta autorizada para los servicios que uses. Verificá primero; instalá solo lo que falte.

### Claude Code

```bash
claude --version
claude doctor
```

Instalación estable con Homebrew:

```bash
brew install --cask claude-code
```

Después ejecutá `claude` y completá el login en el browser. La instalación nativa oficial también está documentada en [Claude Code setup](https://code.claude.com/docs/en/setup).

### Git y acceso SSH

```bash
git --version
ssh -T git@github.com
```

Si Git falta:

```bash
brew install git
```

`ssh -T` puede terminar con un código distinto de cero aunque la autenticación sea válida; verificá el mensaje, no publiques su salida si contiene datos de identidad.

### VPN corporativa

Conectate a la VPN corporativa mediante el cliente aprobado para macOS. No hay un instalador público que esta guía deba ejecutar. Grid depende de que el edge corporativo resuelva tu identidad; estar conectado a internet no alcanza.

La validación segura se realiza más adelante con `setup`. No agregues headers, cookies ni tokens manuales para intentar reemplazar la VPN o la identidad del edge.

### Bash, `jq` y `curl`

```bash
bash --version
jq --version
curl --version
```

Si falta alguna herramienta:

```bash
brew install bash jq curl
```

### ACLI

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

## 2. Instalar `groot-queue` en Claude Code

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

## 3. Permisos ACLI en Claude Code

`Bash(acli jira *)` habilita todo el subárbol Jira de ACLI, incluidas operaciones mutables y masivas. Usalo solo si necesitás automatización completa y aceptás explícitamente esa capacidad:

```json
{
  "permissions": {
    "allow": [
      "Bash(acli jira *)"
    ]
  }
}
```

Para una instalación read-only inicial, preferí reglas granulares y aprobá las mutaciones caso por caso:

```json
{
  "permissions": {
    "allow": [
      "Bash(acli jira auth status)",
      "Bash(acli jira workitem search *)",
      "Bash(acli jira workitem view *)"
    ]
  }
}
```

Guardá el perfil elegido en `.claude/settings.local.json`. El perfil granular permite diagnóstico, listado y lectura; comandos como asignación, transición o edición seguirán solicitando autorización.

**Fusioná valores; no reemplaces el archivo completo.** Conservá sus claves y entradas existentes, validá el JSON con `jq empty .claude/settings.local.json` y hacé una copia local si contiene configuración relevante. Otorgá permisos solo en proyectos confiables y no amplíes el patrón a todo `acli` ni a todo `Bash`.

## 4. Atlassian MCP

### Opción recomendada: plugin oficial

```bash
claude plugin install --scope user atlassian@claude-plugins-official
```

En una sesión de Claude Code, abrí `/mcp` y completá OAuth para el workspace corporativo correcto. Podés revisar el inventario con `claude plugin list --json` y el estado de las conexiones con `claude mcp list`.

### Alternativa manual: endpoint `authv2`

Usá esta alternativa solo si no podés instalar el plugin oficial:

```bash
claude mcp add --scope user --transport http atlassian https://mcp.atlassian.com/v1/mcp/authv2
claude mcp login atlassian
```

**Elegí una sola opción.** No combines el plugin oficial y la conexión manual: dos conexiones Atlassian pueden inyectar tools duplicadas o ambiguas. Antes de continuar, revisá `claude plugin list --json` y `claude mcp list`, y dejá activa una única integración.

### Reglas de seguridad Atlassian

- Usá OAuth; no pegues API tokens, cookies ni headers en prompts, settings o comandos.
- Resolvé el `cloudId` dinámicamente desde los recursos que devuelve Atlassian MCP. Nunca lo hardcodees ni publiques su valor.
- Para acciones que escriben notas internas de Jira Service Management, el MCP debe ofrecer capacidad real de **internal note**. Un comentario público no es un fallback seguro.
- Si no puede garantizarse visibilidad interna, abortá la automatización y completá la acción manualmente en Jira.
- La regla exacta de visibilidad y los modos ABORTAR/DEGRADAR viven en [`atlassian-mcp.md`](atlassian-mcp.md).

## 5. Slack MCP

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

## 6. Grid Sharing y VPN

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

## 7. Fury Services y FuryDocs

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

## 8. Configurar el TEAM

El roster se mantiene exclusivamente en [`SKILL.md` — Equipo para asignación](../../SKILL.md#equipo-para-asignación). No lo copies a esta guía.

Un `TEAM` vacío impide que `assign-unassigned` reparta tickets, pero no redefine ni reemplaza el readiness de Grid/FuryDocs para los demás comandos.

## 9. Recargar y validar

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
2. `setup` verifica ACLI, permisos, integraciones, TEAM y readiness completo; no instala ni modifica nada.
3. Ejecutá un comando operativo solo cuando `setup` indique que las fases obligatorias están listas. No omitas ni fuerces el gate de readiness.

## 10. Launcher opcional

El launcher `run-groot-queue` es una conveniencia para iniciar un provider en un proceso hijo. **No es un prerrequisito** y no instala `groot-queue`, ACLI, plugins, MCPs ni credenciales.

Desde el directorio del plugin:

```bash
./scripts/install.sh
```

El instalador publica un wrapper ejecutable en `~/.local/bin/run-groot-queue` con el source absoluto de la copia actual. Puede pedir confirmación si existe otro destino. Cada proceso queda anclado a una sola copia, incluso si reinstalás el wrapper mientras está corriendo. Volvé a ejecutar `./scripts/install.sh` después de actualizar o mover el plugin y revisá la interfaz con `run-groot-queue --help`.

El launcher usa un directorio temporal y no conserva `.claude/settings.local.json` del proyecto llamador. Ejecutá `/groot-queue:setup` desde la sesión Claude abierta en tu proyecto para validar ese permiso local; no uses el launcher para ese check.

Antes de usarlo, revisá [`run-groot-queue.sh`](../../../../scripts/run-groot-queue.sh): el launcher inicia procesos hijos con permisos amplios de tools para poder operar. Usalo solo desde una copia confiable y no lo tomes como bypass del readiness ni de las confirmaciones de acciones mutables.

## Troubleshooting

Empezá siempre por `/groot-queue:setup`; reportá solo estados, nombres de checks y failure codes seguros. No pegues payloads completos, identidad, headers, tokens, paths privados ni datos de tickets.

### Claude, inventario o dependencias locales

**Síntomas:** CLI ausente, JSON inválido, plugin no instalado/deshabilitado, skill faltante o MCP local no declarado.

1. Verificá `claude --version`, `claude doctor`, `jq --version` y `curl --version`.
2. Revisá `claude plugin list --json` y `claude mcp list`.
3. Ejecutá `/reload-plugins`; reiniciá si el inventario sigue stale.
4. Seguí las familias `dependencies`, `configuration`, `provider_inventory`, `grid_*` y `fury_*` del [readiness técnico](groot-queue-readiness.md#fase-shell).

### Grid: red, servicio o rate limit

**Síntomas:** transport failure, servicio no disponible, timeout o rate limit.

1. Confirmá la VPN y reintentá en una invocación nueva.
2. No agregues headers ni reintentos manuales agresivos.
3. Si `setup` informa espera segura, respetala.
4. Consultá las remediaciones de [exit codes shell](groot-queue-readiness.md#exit-codes-shell-y-remediaciones).

### Grid: versión, identidad o acceso

**Síntomas:** plugin desactualizado, edge sin identidad, lectura general prohibida o documento requerido inaccesible.

1. Para identidad, reconectá la VPN y verificá que usás el acceso corporativo correcto.
2. Para versión, actualizá solo con aprobación explícita y reiniciá Claude Code.
3. Para permisos, solicitá acceso por el canal corporativo; no pruebes otros IDs ni copies el ID requerido desde la configuración.
4. No interpretes un plugin instalado como readiness exitoso: todas las capas deben pasar.

### Fury Services o FuryDocs

**Síntomas:** `mcp-remote-proxy` ausente, MCP `fury` desconectado o capacidades runtime requeridas no visibles.

1. Verificá `command -v mcp-remote-proxy` y `claude mcp get plugin:fury-services:fury`.
2. Ejecutá `/reload-plugins` y después reiniciá si el transporte sigue stale.
3. No crees otra entrada `fury` ni copies argumentos internos del manifiesto.
4. Revisá la [fase runtime MCP](groot-queue-readiness.md#fase-runtime-mcp).

### ACLI o Atlassian

**Síntomas:** `acli jira auth status` falla, OAuth expiró, workspace incorrecto, tools duplicadas o no existe capacidad de internal note.

1. Repetí `acli jira auth login --web` si ACLI perdió autenticación.
2. En `/mcp`, completá de nuevo OAuth para la única integración Atlassian elegida.
3. Eliminá la ambigüedad entre plugin oficial y conexión manual antes de reintentar.
4. No hardcodees `cloudId` ni conviertas una nota interna en comentario público.
5. Consultá [`atlassian-mcp.md`](atlassian-mcp.md).

### Slack

**Síntomas:** Slack no aparece en `/mcp`, OAuth expiró o faltan tools de búsqueda/envío.

1. Verificá el plugin oficial en `claude plugin list --json`.
2. Completá OAuth nuevamente desde `/mcp`.
3. Probá solo `/groot-queue:alerts --dry-run` hasta que el diagnóstico esté listo.
4. Consultá [`slack-mcp.md`](slack-mcp.md).

## Preservar conocimiento local antes del lifecycle

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

## Actualizar de forma segura

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

Reiniciá Claude Code y repetí la [secuencia de validación](#9-recargar-y-validar). Si usás el launcher opcional, ejecutá de nuevo `./scripts/install.sh` desde la copia actualizada para refrescar su wrapper. No actualices componentes automáticamente desde `setup`.

## Desinstalar de forma conservadora

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

## Anexo Codex

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

GitHub Copilot CLI no tiene una secuencia operacional equivalente porque readiness aún no puede verificar su inventario. Hasta que el contrato técnico indique soporte, usá Claude Code o Codex para comandos operativos.
