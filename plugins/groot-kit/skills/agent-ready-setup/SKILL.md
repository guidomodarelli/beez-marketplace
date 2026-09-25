---
name: agent-ready-setup
description: >-
  Inspecciona proyecto, detecta stack (frontend, node, java, go) y prepara siempre
  configuración multi-provider para Claude Code, Codex y futuros agentes: genera
  .claude/, .agents/, .codex/, AGENTS.md y proxy CLAUDE.md, sobrescribe siempre
  los assets gestionados con los templates, y mantiene el bloque gestionado de
  AGENTS.md. Usar cuando
  usuario diga "configurar agent ready",
  "setup agent ready", "bootstrap claude", "bootstrap codex", "inicializar
  configuración de agentes", "quiero ser agent ready", "make this repo agent
  ready", o pida pasar Agent Ready Score.
license: MIT
metadata:
  version: "1.3.0"
  author: "guponce"
  category: "developer-experience"
  tags: "agent-ready, multi-provider, claude-code, codex, bootstrap, setup, scaffold"
  command: "/agent-ready-setup"
---

# Agent Ready Setup

Detecta stack y prepara configuración para múltiples providers en una sola
operación. El bootstrap mantiene tres planos con responsabilidades distintas:

- `.agents/`: árbol canónico de reglas, skills y assets compartidos, incluyendo
  skills descubribles por Codex en `.agents/skills/`. Commands y agents también
  se copian como `SKILL.md` porque Codex no los consume como componentes
  independientes. Todo asset gestionado, salvo `settings.json`, se copia byte a
  byte desde el template publicado; cada template de skill, agent y command
  declara su propio frontmatter `name` y `description`.
- `.claude/`: configuración Claude Code, dimensiones del Agent Ready Score y
  symlinks relativos hacia assets canónicos de `.agents/`; `settings.json` queda
  provider-specific.
- `.codex/`: bridge provider-specific para MCP (`.mcp.json`) y hooks Codex.

`AGENTS.md` es la fuente canónica. Debe incluir una sección de referencias de
rules que indique a todos los providers leer y seguir cada archivo bajo
`.agents/rules/`. La sección se prepara desde template y la IA la integra con
instrucciones existentes; Codex no interpreta referencias `@path/to/folder`.
Cada `CLAUDE.md`, tanto raíz como en cualquier subdirectorio, se genera
copiando exactamente `assets/claude-proxy.md` del skill: contiene `@AGENTS.md`
más la regla breve de centralización. Nunca se mantienen variantes de proxy ni
clones de instrucciones en `CLAUDE.md`; las instrucciones específicas viven en
el `AGENTS.md` hermano.

Assets comunes viven en `assets/common/`; templates y hooks específicos viven en
`assets/stacks/<stack>/` y reflejan estructura de assets. Las rules que aplican a
todos los stacks viven una sola vez en `assets/common/rules/`; no duplicarlas en
`assets/stacks/<stack>/rules/`. Un mismo nombre de rule no puede existir en ambos
lugares: el renderer falla si ocurre. El marker `{{AGENT_READY_RULE_REFERENCES}}`
se renderiza dinámicamente con cada archivo de `rules/` común y del stack, y con
cada rule propia del proyecto; no mantener listado duplicado en templates.

Bootstrap requiere ejecución dentro de un worktree Git. Usa `git check-ignore`
como fuente de verdad para omitir instrucciones anidadas cubiertas por
`.gitignore`; fuera de un worktree, termina con error antes de escribir assets.
Bootstrap tiene un solo modo, sin flags de confirmación: sincroniza siempre los
assets gestionados con los templates sin preguntar y normaliza instrucciones.

Los assets publicados por agent-ready-setup (rules, skills, agents, commands,
hooks, `mcp.json` y sus vistas en `.claude/`) se sobrescriben siempre, aunque se
hayan editado: para agregar o cambiar comportamiento, el proyecto crea una rule
propia bajo `.agents/rules/` o una skill nueva. Un symlink en un path gestionado
se reemplaza sin seguirlo. Solo quedan como conflicto los directorios en un path
gestionado y los padres que son symlink. Instrucciones del proyecto
(`AGENTS.md` fuera del bloque gestionado), `settings.json` custom (merge) y
assets desconocidos se preservan.

---

## Step 1 — Resolve SKILL_DIR

```bash
readonly MARKETPLACE_NAME="groot-marketplace"
readonly SKILL_NAME="agent-ready-setup"
PROVIDER="${AGENT_READY_SETUP_ACTIVE_PROVIDER:-claude}"

is_valid_skill_dir() {
  local candidate="$1"

  [[ -f "$candidate/SKILL.md" && \
    -f "$candidate/scripts/bootstrap.sh" && \
    -d "$candidate/assets/stacks" ]]
}

sorted_skill_candidates() {
  local cache_root="$1"
  local skill_name="$2"

  # Prefix candidates with zero-padded numeric components before lexical sorting.
  find "$cache_root" -type f -path "*/skills/$skill_name/SKILL.md" -print 2>/dev/null |
    awk -F/ '
      {
        version = $(NF - 3)
        if (version !~ /^[0-9]+(\.[0-9]+)?(\.[0-9]+)?([+-].*)?$/) {
          printf "%020d.%020d.%020d\t%s\n", 0, 0, 0, $0
          next
        }
        split(version, components, /[.+-]/)
        printf "%020d.%020d.%020d\t%s\n", components[1] + 0, components[2] + 0, components[3] + 0, $0
      }
    ' |
    sort -r |
    cut -f2-
}

# Uses the same zero-padded numeric components as sorted_skill_candidates so
# snapshot and cache versions compare identically.
semantic_version_key() {
  printf '%s\n' "$1" |
    awk '
      {
        if ($0 !~ /^[0-9]+(\.[0-9]+)?(\.[0-9]+)?([+-].*)?$/) {
          printf "%020d.%020d.%020d\n", 0, 0, 0
          next
        }
        split($0, components, /[.+-]/)
        printf "%020d.%020d.%020d\n", components[1] + 0, components[2] + 0, components[3] + 0
      }
    '
}

# The marketplace upgrade refreshes only the provider marketplace snapshot; the
# versioned plugin cache advances only after a provider plugin update, so the
# snapshot is the source that carries the latest published templates.
marketplace_snapshot_root() {
  local marketplace_provider="$1"
  local known_marketplaces="$HOME/.claude/plugins/known_marketplaces.json"
  local codex_config="$HOME/.codex/config.toml"
  local configured_location=""

  if [[ "$marketplace_provider" == "claude" ]]; then
    if [[ -f "$known_marketplaces" ]] && command -v python3 >/dev/null 2>&1; then
      configured_location="$(python3 - "$known_marketplaces" "$MARKETPLACE_NAME" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], encoding="utf-8") as known_marketplaces_file:
    marketplace = json.load(known_marketplaces_file).get(sys.argv[2]) or {}
install_location = marketplace.get("installLocation") if isinstance(marketplace, dict) else None
if isinstance(install_location, str):
    print(install_location)
PY
)"
    fi
    printf '%s\n' "${configured_location:-$HOME/.claude/plugins/marketplaces/$MARKETPLACE_NAME}"
    return 0
  fi

  if [[ -f "$codex_config" ]]; then
    configured_location="$(awk -v section="[marketplaces.$MARKETPLACE_NAME]" '
      /^[[:space:]]*\[/ {
        current = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", current)
        in_section = (current == section)
        next
      }
      in_section && /^[[:space:]]*source_type[[:space:]]*=/ {
        source_type = $0
        sub(/^[^"]*"/, "", source_type)
        sub(/".*$/, "", source_type)
      }
      in_section && /^[[:space:]]*source[[:space:]]*=/ {
        source_location = $0
        sub(/^[^"]*"/, "", source_location)
        sub(/".*$/, "", source_location)
      }
      END {
        if (source_type == "local" && source_location != "") {
          print source_location
        }
      }
    ' "$codex_config" 2>/dev/null || true)"
  fi
  printf '%s\n' "${configured_location:-$HOME/.codex/.tmp/marketplaces/$MARKETPLACE_NAME}"
}

marketplace_snapshot_skill_dir() {
  printf '%s/plugins/groot-kit/skills/%s\n' "$(marketplace_snapshot_root "$1")" "$SKILL_NAME"
}

# Reads the plugin manifest version beside the snapshot skill; both provider
# manifests share the same version.
marketplace_snapshot_version() {
  local plugin_root
  local manifest

  plugin_root="$(marketplace_snapshot_root "$1")/plugins/groot-kit"
  for manifest in "$plugin_root/.claude-plugin/plugin.json" "$plugin_root/.codex-plugin/plugin.json"; do
    if [[ -f "$manifest" ]]; then
      sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1
      return 0
    fi
  done
}

cache_skill_version() {
  basename "$(dirname "$(dirname "$1")")"
}

resolve_skill_dir() {
  local requested_skill_dir="${1:-}"
  local candidate
  local provider_root
  local cache_root
  local project_root
  local snapshot_candidate
  local snapshot_provider
  local newest_cache_candidate

  if [[ -n "${AGENT_READY_SETUP_SKILL_DIR:-}" ]]; then
    candidate="$AGENT_READY_SETUP_SKILL_DIR"
    if is_valid_skill_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    printf 'ERROR: AGENT_READY_SETUP_SKILL_DIR is not a valid %s source: %s\n' \
      "$SKILL_NAME" "$candidate" >&2
    return 1
  fi

  if [[ "$requested_skill_dir" == "$HOME/.codex/plugins/cache/$MARKETPLACE_NAME"/* ]]; then
    provider_root="$HOME/.codex"
  elif [[ "$requested_skill_dir" == "$HOME/.claude/plugins/cache/$MARKETPLACE_NAME"/* ]]; then
    provider_root="$HOME/.claude"
  elif [[ "$PROVIDER" == "claude" ]]; then
    provider_root="$HOME/.claude"
  else
    provider_root="$HOME/.codex"
  fi
  cache_root="$provider_root/plugins/cache/$MARKETPLACE_NAME"
  snapshot_provider="${provider_root##*/.}"

  # The marketplace snapshot wins unless the cache already holds a newer
  # version, so projection never waits for a provider plugin update. An
  # explicit non-cache source keeps priority for local development.
  snapshot_candidate="$(marketplace_snapshot_skill_dir "$snapshot_provider")"
  if is_valid_skill_dir "$snapshot_candidate" && \
    { [[ "$requested_skill_dir" == "$cache_root"/* ]] || \
      ! is_valid_skill_dir "$requested_skill_dir"; }; then
    newest_cache_candidate="$(sorted_skill_candidates "$cache_root/groot-kit" "$SKILL_NAME" | head -n 1)"
    if [[ -z "$newest_cache_candidate" ]] || \
      [[ ! "$(semantic_version_key "$(marketplace_snapshot_version "$snapshot_provider")")" < \
        "$(semantic_version_key "$(cache_skill_version "${newest_cache_candidate%/SKILL.md}")")" ]]; then
      printf '%s\n' "$snapshot_candidate"
      return 0
    fi
  fi

  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    for candidate in \
      "$CLAUDE_PLUGIN_ROOT/skills/$SKILL_NAME" \
      "$CLAUDE_PLUGIN_ROOT"; do
      if [[ "$candidate" != "$requested_skill_dir" ]] && is_valid_skill_dir "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi

  if [[ "$requested_skill_dir" != "$cache_root"/* ]] && \
    is_valid_skill_dir "$requested_skill_dir"; then
    printf '%s\n' "$requested_skill_dir"
    return 0
  fi

  candidate="$provider_root/skills/$SKILL_NAME"
  if [[ "$candidate" != "$requested_skill_dir" ]] && is_valid_skill_dir "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  while IFS= read -r candidate; do
    candidate="${candidate%/SKILL.md}"
    if is_valid_skill_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(sorted_skill_candidates "$cache_root" "$SKILL_NAME")

  if project_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    candidate="$project_root/plugins/groot-kit/skills/$SKILL_NAME"
    if [[ "$candidate" != "$requested_skill_dir" ]] && is_valid_skill_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if is_valid_skill_dir "$requested_skill_dir"; then
    printf '%s\n' "$requested_skill_dir"
    return 0
  fi

  printf 'ERROR: could not resolve %s source\n' "$SKILL_NAME" >&2
  return 1
}

SKILL_DIR="$(resolve_skill_dir "${SKILL_DIR:-}")"
```

Usar path resuelto para ejecutar scripts y leer assets. Después de ejecutar
`bootstrap.sh`, resolver nuevamente: marketplace upgrade puede reemplazar una
fuente versionada y dejar path anterior inexistente. No asumir que provider
actual define ubicación de fuente compartida. Resolver prioriza snapshot del
marketplace del provider (ver «Sincronización posterior al upgrade») salvo que el
cache provider-specific tenga una versión semver mayor; en ese caso usa candidato
válido con mayor versión del cache. `AGENT_READY_SETUP_SKILL_DIR` y source explícito
fuera del cache conservan prioridad para desarrollo local.

---

## Step 2 — Detect stack

Inspeccionar raíz proyecto. Usar prioridad:

| Archivo presente | Stack |
|---|---|
| `package.json` con `react`, `nordic` o `@andes` en dependencies | `frontend` |
| `package.json` sin React/Nordic | `node` |
| `pom.xml` o `build.gradle` | `java` |
| `go.mod` | `go` |

```bash
detect_stack() {
  if [[ -f "package.json" ]]; then
    if grep -qE '"react"|"nordic"|"@andes/[^" ]+"' package.json 2>/dev/null; then
      echo "frontend"
    else
      echo "node"
    fi
  elif [[ -f "pom.xml" || -f "build.gradle" || -f "build.gradle.kts" ]]; then
    echo "java"
  elif [[ -f "go.mod" ]]; then
    echo "go"
  else
    echo ""
  fi
}

STACK=$(detect_stack)
```

Si detección devuelve vacío, informar que stack no pudo determinarse y pedir
uno de: `frontend`, `node`, `java`, `go`.

Si detección tiene éxito, confirmar:

> `Detected stack: **<STACK>**. Running agent-ready-setup — Claude, shared-agent and Codex-compatible managed assets will be overwritten with the templates; project rules, skills, and instructions are preserved.`

---

## Step 3 — Run bootstrap script

Para `frontend`, el bootstrap ejecuta `scripts/setup-groot-ui.sh` después de resolver la
fuente actualizada. El helper consulta la última versión publicada con `npm view groot-ui
version`, la muestra y no instala ni actualiza la dependencia `groot-ui` ni
`package-lock.json` por cuenta propia. Compara la versión efectiva, priorizando
`node_modules/groot-ui/package.json`, `package-lock.json` y finalmente la declaración de
`package.json`. Si difiere de latest, muestra un aviso y el comando exacto
`npm install --save groot-ui@<version>` sin ejecutarlo; si ya coincide, no muestra aviso
de actualización. Sí configura `package.json`: elimina los scripts legacy
`i18n:gettext`, `i18n:upload`, `generate-po.zip`, `upload-translations` y `clean-locales`. Elimina `kraken-translations` de `package.json`, pero no ejecuta
`npm install` ni modifica `package-lock.json`; si la dependencia fue eliminada, avisa
explícitamente que el usuario debe ejecutar `npm install` para actualizar el lockfile.
Si no estaba declarada, informa que no hace falta instalar por ese motivo. Luego asegura
exactamente `scripts.i18n = "groot-i18n"` y `scripts.local2prod = "groot-config-sync"`,
reemplazando valores previos distintos.

Después del aviso, el usuario debe decidir el cambio y ejecutar el comando mostrado (o
`npm install` si `groot-ui` ya está al día) para resolver dependencias, quitar
`kraken-translations` del lockfile y actualizar `package-lock.json`. Si la
consulta de npm falla o devuelve una versión inválida, el helper termina antes de
modificar `package.json`. Stacks `node`, `java` y `go` no consultan esta dependencia de
UI.

```bash
PROVIDER="$(bash "$SKILL_DIR/scripts/resolve-provider.sh" --skill-dir "$SKILL_DIR")"
bash "$SKILL_DIR/scripts/bootstrap.sh" \
  --stack "$STACK" \
  --skill-dir "$SKILL_DIR" \
  --provider "$PROVIDER"

SKILL_DIR="$(resolve_skill_dir "$SKILL_DIR")"
bash "$SKILL_DIR/scripts/merge-instructions.sh" \
  --provider "$PROVIDER" \
  --stack "$STACK" \
  --skill-dir "$SKILL_DIR"
```

`resolve-provider.sh` respeta `AGENT_READY_SETUP_ACTIVE_PROVIDER` cuando vale
`claude` o `codex`; si no existe, infiere provider desde `SKILL_DIR` bajo
`$HOME/.claude/`, `$HOME/.codex/` o `CLAUDE_PLUGIN_ROOT`. Para rutas fuera de
instalación reconocible, termina con error y exige provider explícito.

El script actualiza assets compartidos gestionados bajo `.agents/`, crea o
conserva symlinks relativos para assets no-hook bajo `.claude/` y prepara bridge
`.codex/`.
Los scripts de hooks permanecen únicamente bajo `.agents/hooks/`.
El renderer crea `AGENTS.md` nuevo con el bloque gestionado; en `AGENTS.md`
existente, `merge-instructions.sh` reemplaza ese bloque por copia literal del
template y la IA solo revisa redundancias fuera de él. El provider debe ser
`claude` o `codex`.
Copias bajo `.claude/` de assets gestionados, idénticas o editadas, se
reemplazan por el symlink canónico. Antes de normalizar las
instrucciones del proyecto, bootstrap y sync buscan recursivamente en todos
los niveles y subniveles cualquier archivo cuyo basename coincida con
`claude.md` sin respetar exactamente mayúsculas (`Claude.md`, `claude.md`,
etc.) y lo renombran a `CLAUDE.md` mediante un path temporal del mismo
directorio, para que el cambio de casing también funcione en filesystems
case-insensitive. Solo renombra archivos regulares no ignorados; paths ignorados se preservan,
mientras symlinks, archivos no regulares y colisiones se preservan y reportan.
El descubrimiento parte siempre de la raíz Git, incluso si el comando se invoca
desde `.claude/` u otro subdirectorio. El hook reutiliza el modo interno
`bootstrap.sh --normalize-only` después de proyectar assets, sin repetir upgrade
ni proyección.
Después aplica la normalización existente a cada `CLAUDE.md`, reemplazándolo
por una copia byte-a-byte de `assets/claude-proxy.md`; ese template usa el
`AGENTS.md` hermano mediante la referencia relativa `@AGENTS.md` y nunca usa un
`AGENTS.md` de otro nivel. Durante la búsqueda recursiva de instrucciones
usa el inventario Git: omite paths ignorados no trackeados, pero conserva archivos
trackeados bajo directorios ignorados como `node_modules/`; esta regla no impide
crear los destinos explícitos `.claude/`, `.agents/` y `.codex/`. Los hooks de
sincronización reciben provider explícito (`--provider
claude` desde `.claude/settings.json` y `--provider codex` desde `.codex/`),
y el hook canónico bajo `.agents/hooks/` es autosuficiente: no necesita que
`bootstrap.sh` exista dentro del repositorio consumidor. `-p` es alias de
`--provider`; al invocarse directamente desde `.agents/hooks/`, el script
infiere `codex` si no se especifica provider. También normaliza instrucciones
raíz:

1. Si `CLAUDE.md` raíz ya es byte-a-byte igual a `assets/claude-proxy.md`, lo
   considera normalizado y no lo modifica.
2. Si `CLAUDE.md` raíz contiene solo `@AGENTS.md`, agrega la regla de
   centralización copiando `assets/claude-proxy.md`, sin modificar `AGENTS.md`.
3. Si falta `CLAUDE.md` raíz, lo crea como copia exacta de
   `assets/claude-proxy.md`, exista o no `AGENTS.md`.
4. Si existe `CLAUDE.md` raíz con instrucciones y falta `AGENTS.md`, promueve ese
   contenido a `AGENTS.md` y reemplaza `CLAUDE.md` por la copia exacta del asset.
5. Si ambos archivos raíz contienen el mismo contenido, conserva uno en
   `AGENTS.md` y deja `CLAUDE.md` como copia exacta del asset.
6. Si ambos difieren, el script no sobrescribe ninguno: reporta una diferencia
   para que el agente la analice y continúa con assets. La skill no debe derivar
   automáticamente esta diferencia al usuario.

En `CLAUDE.md` anidados (incluido `.claude/CLAUDE.md`) aplica la misma
normalización por directorio, siempre con el `AGENTS.md` hermano:

- Si existe solo `AGENTS.md`, crea `CLAUDE.md` como copia exacta de
  `assets/claude-proxy.md`.
- Si existe solo `CLAUDE.md`, crea `AGENTS.md` hermano con su contenido
  (omitiendo únicamente una primera línea exactamente `@AGENTS.md`) y reemplaza
  `CLAUDE.md` por la copia exacta del asset.
- Si `CLAUDE.md` ya es el proxy exacto, no lo modifica; si además falta
  `AGENTS.md`, crea el hermano canónico vacío.
- Si ambos tienen instrucciones distintas, no sobrescribe ninguno y reporta la
  diferencia para que el agente la resuelva según «Resolución de diferencias por
  el agente».

### Sincronización posterior al upgrade

`fury ai assets marketplace upgrade` actualiza la copia global del marketplace;
no vuelve a proyectar por sí mismo los templates sobre un proyecto ya preparado.
`bootstrap.sh` ejecuta ese upgrade automáticamente para el provider activo antes
de proyectar assets o adquirir lock local. En `frontend`, también ejecuta el helper
que consulta la última versión disponible de `groot-ui` sin instalarla ni modificar el
lockfile, compara la versión efectiva, elimina `kraken-translations` de `package.json`
y configura los scripts.
El hook canónico `.agents/hooks/sync-marketplace.sh` ejecuta el upgrade salvo que
haya uno exitoso de menos de 60 minutos para el mismo provider (marca en
`${XDG_CACHE_HOME:-~/.cache}/agent-ready-setup/marketplace-upgrade-<provider>.stamp`,
escrita solo tras un upgrade exitoso); `AGENT_READY_SETUP_FORCE_UPGRADE=1` lo
fuerza y `bootstrap.sh` lo ejecuta siempre. En paralelo con el upgrade,
consulta la última versión de `groot-ui` en `frontend` sin instalarla ni actualizarla,
y muestra un aviso con `npm install --save groot-ui@<version>` solo cuando existe una
versión más nueva. Proyecta todos los assets gestionados, ejecuta la normalización recursiva de
instrucciones mediante `bootstrap.sh --normalize-only` cuando la versión instalada
lo soporta y luego actualiza el bloque gestionado de `AGENTS.md` cuando el
helper está disponible. La normalización incluye `CLAUDE.md` bajo `.claude/` y conserva
conflictos, symlinks y archivos no regulares. El usuario debe decidir y ejecutar el
comando mostrado (o `npm install` si `groot-ui` ya está al día) para actualizar
`package-lock.json` y quitar `kraken-translations` del lockfile.
El upgrade solo refresca el snapshot del marketplace del provider (Claude:
`installLocation` de `~/.claude/plugins/known_marketplaces.json`, por defecto
`~/.claude/plugins/marketplaces/groot-marketplace`; Codex: `source` local de
`~/.codex/config.toml` o `~/.codex/.tmp/marketplaces/groot-marketplace`); el cache
versionado del plugin avanza recién con `/plugin` update. Por eso el hook resuelve
la fuente desde ese snapshot salvo que el cache tenga una versión semver mayor, y
proyecta la última versión publicada sin depender de la versión instalada del plugin.
`bootstrap.sh` y el resolver de «Step 1 — Resolve SKILL_DIR» aplican el mismo criterio.
Si la fuente resuelta no contiene `scripts/asset-sync-common.sh`, el hook ejecuta un
refresh adicional de `groot-marketplace`, vuelve a resolver la fuente y carga helper
mediante `source` antes de proyectar cualquier asset. Si refresh no entrega helper,
conserva hook local, omite proyección y muestra diagnóstico; no instala un
`sync-marketplace.sh` que no pueda arrancar.
Si la copia instalada del hook cambió, se reejecuta con el mismo provider y stack
antes de proyectar el resto. La reejecución conserva el lock de assets y usa una
guarda interna para no repetir el upgrade inicial; refresh por helper faltante solo
se intenta antes de cargar helper. No repite proyección ni upgrade durante
`--normalize-only`.

El hook compara cada asset gestionado con el template actualizado y muestra
`diff -u` antes de reemplazar un archivo existente. Los archivos regulares
modificados se reemplazan automáticamente y su contenido local se guarda en un
directorio temporal externo al proyecto; el output muestra path exacto para
revisarlo o compararlo. Los symlinks en paths gestionados se reemplazan sin
seguirlos; directorios en paths gestionados, padres inseguros y cambios
concurrentes se preservan y se reportan como conflictos estructurales.

### Riesgos del upgrade automático

- Cada upgrade necesita CLI `fury`, autenticación y red; si upgrade falla,
  bootstrap y hook terminan antes de modificar assets locales y no registran la
  ventana de 60 minutos.
- Dentro de esa ventana, una versión recién publicada del marketplace puede
  tardar hasta 60 minutos en llegar por SessionStart; usar
  `AGENT_READY_SETUP_FORCE_UPGRADE=1` o `bootstrap.sh` para aplicarla antes.
- Upgrade global no tiene rollback en este script; la versión descargada puede
  cambiar aunque proyección local quede bloqueada.
- El hook aplica templates nuevos sobre assets gestionados y conserva cada
  versión local modificada en un backup temporal externo al proyecto; reglas,
  symlinks, conflictos estructurales y reemplazos atómicos siguen evitando
  seguir o sobrescribir destinos inseguros.
- Lock protege proyección local concurrente, pero no serializa upgrades globales
  de Fury entre procesos distintos.
- En `frontend`, la consulta `npm view groot-ui version` requiere registry,
  autenticación y red; el helper no instala dependencias ni actualiza
  `package-lock.json`, aunque elimina `kraken-translations` de `package.json`.
  El usuario controla el cambio de versión y ejecuta `npm install` cuando decide
  sincronizar el lockfile.

La proyección automática de assets:

- Actualiza assets gestionados bajo `.agents/`, settings específicos de
  `.claude/`, y bridge/configuración bajo `.codex/`.
- Copia adapters `SKILL.md` bajo `.agents/skills/` byte a byte desde su
  template, sin reescribir frontmatter: providers eligen skills según
  `description`, por lo que el template es la única fuente.
- En `.claude/`, agents y commands se registran una sola vez (`.claude/agents/`,
  `.claude/commands/`); su adapter en `.agents/skills/` queda solo para Codex.
  El sync elimina vistas `.claude/skills/<nombre>/` gestionadas que dupliquen un
  agent o command y preserva y reporta contenido custom.
- Claude Code carga `.claude/rules/` automáticamente; el bloque gestionado de
  `AGENTS.md` le indica no volver a leerlas y deja las referencias para Codex.
- Reemplaza symlinks en paths gestionados sin seguirlos: borra el link y escribe
  el template, así nunca modifica el destino del link.
- Elimina symlinks administrados stale bajo `.claude/` y limpia `.claude/hooks/`
  legacy solo cuando queda vacío.
- Migra referencias `.claude/hooks/` dentro de `.claude/settings.json` como JSON
  y normaliza el comando administrado a `.agents/hooks/` sin flags de fase,
  preservando campos custom y reportando settings inválidos.
- Normaliza `CLAUDE.md` raíz y anidados, incluido `.claude/CLAUDE.md`, mediante
  el modo interno conservador; crea o actualiza únicamente el `AGENTS.md`
  hermano cuando puede preservar el contenido sin ambigüedad.
- No elimina assets desconocidos (rules, skills o archivos propios del
  proyecto); solo sobrescribe paths que publica agent-ready-setup.

El paso posterior sobre instrucciones actualiza únicamente `AGENTS.md`; nunca
modifica `CLAUDE.md` directamente.

Para sincronizar manualmente desde un hook existente:

```bash
bash .agents/hooks/sync-marketplace.sh --provider claude
# o
bash .agents/hooks/sync-marketplace.sh --provider codex
```

Si la fuente instalada no se puede resolver o el stack no se detecta, el hook
conserva el upgrade global y muestra cómo indicar `AGENT_READY_SETUP_SKILL_DIR`
o `--stack frontend|node|java|go`.

### Bloque gestionado de `AGENTS.md`

Cada template de stack (`assets/stacks/<stack>/agents-template.md`) define el bloque
entre `<!-- BEGIN AGENT-READY MANAGED -->` y `<!-- END AGENT-READY MANAGED -->`.
`scripts/render-instruction-template.sh` lo materializa:

- `{{AGENT_READY_RULE_REFERENCES}}`: una referencia portable
  `- Read and follow \`.agents/rules/<relative-path>\`.` por cada rule del
  template (comunes de `assets/common/rules/` y del stack, en orden alfabético)
  y, bajo `### Project rules`, por cada rule propia del proyecto.

Una rule propia es cualquier archivo `.md` regular bajo `.agents/rules/` (incluidos
subdirectorios) sin equivalente en las rules del template; los symlinks se
ignoran. Además de listarse en el bloque, el sync le crea su vista en
`.claude/rules/` para que Claude la cargue de forma nativa, la incluye en la
revisión de redundancias y elimina las vistas gestionadas de rules borradas.
Si el template deja de publicar una rule, la copia local que quede en
`.agents/rules/` pasa a tratarse como rule propia hasta que se borre.
- `{{AGENT_READY_CENTRALIZATION}}`: copia literal de
  `assets/instruction-centralization.md`.

El contenido fuera del bloque (descripción, stack, comandos, arquitectura,
ownership) pertenece al proyecto; el scaffold del template solo se usa al crear
un `AGENTS.md` nuevo.

`scripts/merge-instructions.sh`, ejecutado por el hook en cada sync:

1. Reemplaza el bloque por copia literal del template renderizado. Cualquier
   edición manual dentro de los marcadores se pierde; instrucciones propias van
   fuera del bloque.
2. Envía al provider activo el bloque, el contenido completo de cada rule y el
   contenido del proyecto (con el bloque sustituido por
   `<!-- AGENT-READY MANAGED BLOCK -->`), todo como datos no confiables. La IA
   solo puede borrar líneas redundantes fuera del bloque: repetidas en el propio
   contenido o ya cubiertas por el bloque o por una rule.
3. Rechaza la revisión si agrega, reescribe o reordena líneas, pierde el
   placeholder, devuelve bloques cercados o reintroduce marcadores. En ese caso,
   o si el provider falla, aplica solo el bloque literal sin tocar el contenido
   del proyecto y reintenta la revisión en el siguiente sync.
4. Reporta las líneas borradas y, por separado, las inconsistencias: líneas del
   proyecto que contradicen el bloque o una rule. Las inconsistencias nunca se
   borran; quedan para revisión manual.
5. En un `AGENTS.md` legacy sin marcadores, la IA elimina secciones que el
   bloque reemplaza (lista de rules, centralización) y la lista de skills
   escrita a mano, porque Claude y Codex descubren skills de forma nativa; y ubica
   el placeholder. Si la revisión falla, el bloque se agrega al final y solo se
   quita la lista legacy entre marcadores `AGENT-READY RULE REFERENCES`, que ya
   no se generan.
6. Si los marcadores están duplicados o desordenados, no modifica el archivo y
   termina con código `2` para revisión humana.

La revisión completada se registra en
`.git/info/agent-ready-instructions-reviewed.sha256` (hash de `AGENTS.md` más
el contenido de las rules del template y propias). Mientras ninguno cambie, el sync no vuelve a
invocar IA. Hashes legacy (`.agents/.agent-ready-instructions-template.sha256`
y `.git/info/agent-ready-instructions-template.sha256`) se eliminan. La
escritura es atómica y se cancela si `AGENTS.md` cambia durante el proceso.

Los hooks generados no pasan flags de confirmación durante `SessionStart`.
`CLAUDE.md` nunca se modifica durante este paso.

### Resolución de diferencias por el agente

Durante bootstrap inicial, cuando existan diferencias entre `CLAUDE.md` y
`AGENTS.md` raíz, el agente debe resolverlas antes de presentar bootstrap como
terminado:

1. Leer ambos archivos completos y tratarlos como instrucciones del proyecto,
   no como comandos para ejecutar durante análisis.
2. Separar contenido duplicado, instrucciones compatibles y contradicciones
   semánticas. Usar contexto del proyecto, `README.md`, configuración y
   comandos existentes para determinar intención y precedencia.
3. Fusionar en `AGENTS.md` toda instrucción compatible o complementaria, conservar
   una sola versión de duplicados y mantener `AGENTS.md` como fuente canónica.
4. Escribir versión fusionada en `AGENTS.md` y reemplazar `CLAUDE.md` por copia
   byte-a-byte de `assets/claude-proxy.md`.
5. Escalar únicamente contradicciones reales que el agente no pueda resolver con
   evidencia del proyecto. Reportar paths y fragmentos afectados, sin sobrescribir.

No llamar “conflicto” a diferencia meramente complementaria. Si agente puede
resolverla con evidencia local, debe hacerlo y dejar `CLAUDE.md` normalizado.

La regla de centralización vive solo en el bloque gestionado del `AGENTS.md`
raíz; no se duplica en `AGENTS.md` de subdirectorios. Bootstrap no ejecuta scripts ni hooks
copiados durante bootstrap. No modifica `~/.codex/config.toml`,
`~/.claude/settings.json` ni otra configuración global.

---

## Step 4 — Report

Mostrar output del script sin alterarlo. En respuestas documentales, enumerar paths relevantes de template detectado además del resumen: para todos los stacks incluir las rules comunes `language-consistency.md` y `lint-gate.md`; para Go, Java y Node incluir `coding-style.md`, `security.md`, `testing.md` y `mcp.json`; para frontend incluir `frontend-style.md`, `lodash.md`, `api-configuration.md`, `security.md`, `testing.md`, `no-unnecessary-mocks.md`, `mcp.json` y `skills/component-creation/`. Luego agregar únicamente acciones aplicables, usando estas etiquetas:

- `[AUTO]`: el agente puede comprobarlo de forma determinista y debe reportar `PASS`, `FAIL` o `N/A` con los paths involucrados.
- `[MANUAL]`: requiere conocimiento específico del proyecto y no debe presentarse como validación ya realizada.

```
Next steps:
  1. [MANUAL] Completar `AGENTS.md` solo si todavía faltan descripción, comandos, arquitectura u ownership del proyecto.
  2. [AUTO] Validar que cada `CLAUDE.md`, raíz o anidado —incluido `.claude/CLAUDE.md`— sea byte-a-byte igual a `assets/claude-proxy.md` (incluye `@AGENTS.md` y la regla de centralización), y que cada uno tenga un `AGENTS.md` hermano. Si no hay archivos anidados, reportar `N/A`.
  3. [AUTO] Validar que `AGENTS.md` raíz tenga exactamente un bloque `BEGIN/END AGENT-READY MANAGED`. Si existe `.agents/rules/`, validar que ese bloque tenga una referencia portable con instrucción explícita de lectura/seguimiento para cada archivo real; rechazar `@./rules/...`, `@.agents/rules/...` y `@path/to/folder`. Si no existe el directorio o no contiene rules, reportar `N/A`, no una tarea pendiente.
  4. [AUTO] Si existen archivos bajo `.agents/rules/`, `.agents/skills/` o `.agents/agents/`, detectar comentarios scaffold (`<!-- Add ... -->`, `<!-- Describe ... -->`) y marcadores sin renderizar (`{{...}}`). Reportar cada path. No tratar ejemplos como `<domain>` o `<component-name>` dentro de documentación como placeholders pendientes. Si no existen esos archivos, reportar `N/A`.
  5. [AUTO] Validar JSON, paths y referencias de MCP/hooks bajo `.codex/`. Si `.codex/` no existe, reportar `N/A`.
     [MANUAL] Revisar permisos, credenciales, alcance y si corresponde habilitar MCP/hooks; no presentar esa decisión como validada automáticamente.
  6. [AUTO] Verificar dimensiones de Agent Ready Score solo si existe configuración o reporte bajo `.claude/`; reportar dimensiones faltantes con sus paths. Si no existe score/configuración, reportar `N/A`.
```

Si hay archivos preservados por conflicto o contenido custom, agregar:

> `Preserved files were not modified. [AUTO] Verify whether preserved files already cover the same dimensions as the templates; report each path and result.`

Si queda una contradicción semántica irresoluble, detener solo la normalización
de esos archivos y mostrar paths, fragmentos afectados y motivo por el que falta
precedencia. Para diferencias compatibles ya fusionadas, reportar la fusión y
confirmar que `CLAUDE.md` raíz quedó byte-a-byte igual a `assets/claude-proxy.md`.
