# 🛒 Fury Plugins Marketplace

> Multi-provider marketplace de skills y plugins para equipos de Mercado Libre.  
> Soporta **Claude Code** y **Codex** 🤖

---

## 🚀 Getting started (primera configuración)

Después de crear tu marketplace desde este template, completá estos pasos antes de agregar plugins:

### 1️⃣ Actualizar `marketplace.json`

Abrí `.claude-plugin/marketplace.json` y `.agents/plugins/marketplace.json` y configurá el campo `name` con algo que describa tu marketplace. No necesita coincidir con el nombre del repo — usá algo corto y significativo:

```json
{
  "name": "fintech-marketplace",
  ...
}
```

> ⚠️ El pipeline de CI bloqueará PRs que aún tengan el nombre por defecto del template (`plugins-marketplace`).

### 2️⃣ Instalar pre-commit hooks

```bash
pip install pre-commit && pre-commit install
```

---

## 📁 Estructura del repositorio

```
├── .claude-plugin/
│   └── marketplace.json        # Registro de plugins para Claude Code
├── .agents/plugins/
│   └── marketplace.json        # Registro de plugins para Codex
├── plugins/
│   └── <plugin-name>/
│       ├── .claude-plugin/
│       │   └── plugin.json     # Manifiesto del plugin para Claude Code
│       ├── .codex-plugin/
│       │   └── plugin.json     # Manifiesto del plugin para Codex (si es compatible)
│       └── skills/
│           └── <skill-name>/
│               ├── SKILL.md    # Definición del skill — requerido para cada skill
│               └── evals/
│                   └── eval-config.json
└── skill-eval-runner/          # CLI para correr evals localmente
```

### 🔀 Implementaciones por proveedor (opcional)

Cuando un plugin requiere una implementación diferente por proveedor, usá subdirectorios en lugar de un `skills/` compartido:

```
plugins/<plugin-name>/
├── claude/
│   ├── .claude-plugin/plugin.json
│   └── skills/
└── codex/
    ├── .codex-plugin/plugin.json
    └── skills/
```

Cada registro luego referencia la ruta del subdirectorio de su proveedor (ej. `./plugins/<name>/codex`).

---

## 🤖 Agent Ready multi-provider

`plugins/groot-kit/skills/agent-ready-setup` prepara siempre los tres planos sin acoplar assets compartidos a un provider:

```text
AGENTS.md                  # instrucciones canónicas
CLAUDE.md                  # raíz: proxy + regla; subdirectorios: @AGENTS.md
.claude/                   # Agent Ready Score y configuración Claude
.agents/hooks/             # scripts de hooks compartidos por ambos providers
.agents/skills/            # skills compartidas y descubribles por Codex
.agents/rules/             # reglas compartidas
.codex/hooks/hooks.json    # configuración de hooks específica Codex
.codex/.mcp.json           # MCP específico Codex
```

Si `CLAUDE.md` ya contiene instrucciones, el setup las promueve a `AGENTS.md` y deja `CLAUDE.md` como `@AGENTS.md`. Si ambos archivos existen y difieren, no sobrescribe ninguno y reporta conflicto para resolución manual. La normalización recursiva respeta `.gitignore` y excluye `node_modules/`; los destinos explícitos `.claude/`, `.agents/` y `.codex/` se siguen preparando aunque estén ignorados. El bootstrap requiere ejecutarse dentro de un worktree Git y actualiza automáticamente `groot-marketplace` para provider activo antes de proyectar assets.

Después de `marketplace upgrade`, la actualización global no reproyecta assets sobre proyectos ya preparados. `bootstrap.sh` combina upgrade y proyección de `.claude/`, `.agents/` y `.codex/`; el hook canónico `.agents/hooks/sync-marketplace.sh` siempre actualiza de forma autónoma el hook común, los hooks de `assets/stacks/<stack>/hooks/`, `.claude/settings.json` y `.codex/hooks/hooks.json`, y ejecuta el merge semántico de `AGENTS.md` sin requerir `bootstrap.sh` dentro del repo consumidor. Muestra diffs, aplica templates sobre archivos regulares modificados y conserva su versión local en un directorio temporal externo al proyecto; output muestra path exacto para revisión o diff. También migra referencias legacy de hooks en settings JSON y normaliza sus flags al comando `.agents/hooks/...` sin flags de fase; symlinks, destinos inseguros y hooks custom bajo `.claude/hooks/` se preservan. El merge IA de `AGENTS.md` conserva cambios compatibles; si falla o queda sin resolución, aplica template y guarda backup temporal. `CLAUDE.md` y pares de instrucciones anidados nunca se reemplazan ciegamente.

El flujo manual y `SessionStart` usan el hook sin flags de confirmación. La resolución IA trata documentos como datos no confiables, aplica cambios compatibles automáticamente y usa fallback template + backup ante salida inválida o conflicto irresoluble. `CLAUDE.md` permanece como proxy.

---

## 📦 Instalar este marketplace

Los nombres disponibles viven en `.claude-plugin/marketplace.json` y `.agents/plugins/marketplace.json`. Instalá el marketplace y reemplazá `<plugin-name>` por el plugin elegido:

```bash
# Claude Code
claude plugin marketplace add --scope user git@github.com:melisource/fury_groot-marketplace.git
claude plugin install --scope user <plugin-name>@groot-marketplace

# Codex
codex plugin marketplace add git@github.com:melisource/fury_groot-marketplace.git
codex plugin add <plugin-name>@groot-marketplace
```

Para `groot-queue`, consultá la [guía completa de instalación, configuración y diagnóstico](plugins/groot-queue/README.md), fuente canónica para sus prerrequisitos, MCPs, Grid Sharing, Fury Services/FuryDocs y troubleshooting.

---

## 🔧 Probar plugins y skills localmente

Usá esta guía para probar cualquier skill standalone, plugin o marketplace sin
publicarlo. Definí variables según el árbol que quieras probar:

```bash
MARKETPLACE_NAME="groot-marketplace"
PLUGIN_NAME="<plugin-name>"
SKILL_NAME="<skill-name>"
PLUGIN_SRC="$PWD/plugins/$PLUGIN_NAME"
SKILL_SRC="$PLUGIN_SRC/skills/$SKILL_NAME"
```

Para una skill standalone, reemplazá `SKILL_SRC` por:

```bash
SKILL_SRC="$PWD/skills/$SKILL_NAME"
```

### 1. Cargar una skill directamente con symlink

Este método valida `SKILL.md`, recursos bundled y ejecución de la skill. No valida
manifests ni discovery del marketplace.

```bash
ln -sfn "$SKILL_SRC" "$HOME/.claude/skills/$SKILL_NAME"   # Claude Code
ln -sfn "$SKILL_SRC" "$HOME/.codex/skills/$SKILL_NAME"    # Codex
```

Reiniciá cada cliente después de crear el symlink. Las ediciones posteriores a
`SKILL.md`, `subcommands/*`, `knowledge/*`, `assets/*` o `scripts/*` quedan
reflejadas desde el repositorio.

### 2. Cargar un plugin en una sesión de Claude Code

Este método valida el plugin Claude sin instalarlo persistentemente:

```bash
claude --plugin-dir "$PLUGIN_SRC"
```

`--plugin-dir` no valida la instalación del marketplace Codex ni el registro de
`marketplace.json`.

### 3. Probar marketplace local completo

Ejecutá estos comandos desde raíz del marketplace, no desde `PLUGIN_SRC`:

```bash
# Claude Code
claude plugin marketplace add --scope local "$PWD"
claude plugin install --scope local "$PLUGIN_NAME@$MARKETPLACE_NAME"

# Codex
codex plugin marketplace add "$PWD"
codex plugin add "$PLUGIN_NAME@$MARKETPLACE_NAME"
```

Verificá instalación y discovery:

```bash
claude plugin list
codex plugin marketplace list
codex plugin list --json
```

Para probar cambios posteriores sin publicar el marketplace, actualizá la fuente
local cuando corresponda. En proyectos preparados con Agent Ready, el hook
SessionStart ejecuta siempre proyección local y merge de instrucciones:

```bash
claude plugin marketplace update "$MARKETPLACE_NAME"
codex plugin marketplace upgrade "$MARKETPLACE_NAME"

# Flujo completo desde hook canónico
bash .agents/hooks/sync-marketplace.sh --provider claude
bash .agents/hooks/sync-marketplace.sh --provider codex
```

### 4. Ejecutar evals de una skill

```bash
run-evals "$SKILL_SRC"
run-evals "$SKILL_SRC" --provider codex
```

Usá `--pretty` para un reporte legible. Las evals validan comportamiento de la
skill; no reemplazan la prueba de instalación del plugin o marketplace.

### ✅ Qué valida cada método

| Método | Valida | No valida |
|---|---|---|
| Symlink en `~/.claude/skills` o `~/.codex/skills` | Carga directa y cambios live de una skill | Manifests y registro del marketplace |
| `claude --plugin-dir` | Plugin Claude en una sesión | Instalación Codex y marketplace persistente |
| Marketplace local + `plugin install` / `plugin add` | Registry, manifests, plugin y skills del provider | Publicación remota |
| `run-evals` | Contrato y comportamiento declarado de una skill | Discovery del plugin instalado |

### 🗑️ Cleanup local

```bash
# Symlinks directos
rm -f "$HOME/.claude/skills/$SKILL_NAME" "$HOME/.codex/skills/$SKILL_NAME"

# Plugins instalados
claude plugin uninstall --scope local "$PLUGIN_NAME@$MARKETPLACE_NAME"
codex plugin remove "$PLUGIN_NAME@$MARKETPLACE_NAME"

# Marketplaces configurados
claude plugin marketplace remove "$MARKETPLACE_NAME"
codex plugin marketplace remove "$MARKETPLACE_NAME"
```

Solo los comandos de cleanup modifican la configuración local de los clientes;
el repositorio no cambia.

---

## ➕ Agregar un plugin

1. 🌿 Creá una feature branch: `feature/<plugin-name>`
2. 📂 Agregá tu plugin en `plugins/<plugin-name>/` siguiendo la estructura de arriba
3. 📋 Registralo en los archivos de registro correspondientes:
   - `.claude-plugin/marketplace.json` para Claude Code
   - `.agents/plugins/marketplace.json` para Codex
4. 🔍 Abrí un PR — el pipeline de CI valida la estructura y las versiones automáticamente

> 📌 Un plugin debe aparecer en al menos un registro. Un plugin solo se instala para un proveedor si está listado en el `marketplace.json` de ese proveedor.
>
> 🔒 Todos los archivos `plugin.json` dentro del mismo plugin (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`) deben compartir la misma versión. El RP lo impone — si cambia cualquier skill, todos los manifiestos de proveedor deben hacer bump juntos.

**Formato de commit:** `feat(marketplace): add <name>`

---

## 🔖 Bumping de versión de un plugin

Usá el script `create-version` para hacer bump a la versión de un plugin. Actualiza el campo `version` en **ambos** manifiestos de proveedor (`.claude-plugin/plugin.json` y `.codex-plugin/plugin.json`) a la vez, manteniéndolos sincronizados.

```bash
npm run create-version              # interactivo: elegí un plugin de un menú numerado
npm run create-version groot-queue  # apuntá a un plugin directamente por nombre
```

El script pregunta cómo establecer la nueva versión — un semver bump (`patch` / `minor` / `major`) calculado desde la versión actual, o una versión exacta personalizada.

> ⚠️ Antes de escribir, valida que ambos manifiestos ya compartan la misma versión y aborta si difieren — nunca vas a hacer bump desde un estado inconsistente.

---

## 🔄 Portar un plugin a Codex

Usá el skill `codex-compatibility-analyzer` (disponible via la CLI de assets) para migrar un plugin de Claude Code existente a Codex:

- ✅ Valida prerrequisitos
- 📊 Evalúa portabilidad
- 📝 Genera `.codex-plugin/plugin.json`
- 📋 Registra el plugin en `.agents/plugins/marketplace.json`

---

## 🛡️ Validación de PRs

Cada pull request es validado automáticamente por el Release Process (RP) usando un pipeline de YaCI custom-check. Los siguientes checks corren en cada PR:

| Check | Cuándo corre | Qué valida |
|-------|-------------|------------|
| 🗂️ **Marketplace registry** | Cuando se toca `marketplace.json` | Sintaxis JSON, nombre no es el default del template, sin entradas duplicadas, plugins eliminados tienen su directorio borrado |
| 🔌 **Plugin validation** | Para PRs que agregan o modifican plugins | Campos requeridos en `plugin.json`, nombre en kebab-case, versión inicia en `1.0.0` para nuevos plugins, versión con bump para plugins modificados, `SKILL.md` presente en cada skill |
| 🔗 **Marketplace sync** | Para PRs que agregan o modifican plugins | Verifica que cada directorio de plugin local esté registrado en `marketplace.json` |

> 🚫 Si cualquier check falla, el PR queda bloqueado hasta resolver el problema.

---

## 🧪 Correr tests shell localmente

Las suites shell usan [bats-core](https://github.com/bats-core/bats-core) con versión y dependencias fijadas en `package-lock.json`.

```bash
# Instalación reproducible
npm ci

# Suites aisladas: Groot Queue y contrato del eval runner
npm test

# E2E real de setup (se reporta como skipped sin el flag)
npm run test:e2e
RUN_GROOT_QUEUE_E2E=1 npm run test:e2e

# Suites aisladas + E2E
npm run test:all
```

El E2E real requiere Claude autenticado, plugins Grid Sharing y Fury Services, MCP Fury operativo y acceso de red correspondiente. No se ejecuta durante `npm test`.

---

## 🧪 Correr evals localmente

```bash
# Configuración inicial (una sola vez)
cd skill-eval-runner && ./install.sh

# Correr evals para un skill específico (JSONL por defecto)
run-evals plugins/<plugin-name>/skills/<skill-name>

# Reporte legible con colores (opcional)
run-evals plugins/<plugin-name>/skills/<skill-name> --pretty

# Override de proveedor (por defecto: auto-detecta Codex o Claude)
run-evals plugins/<plugin-name>/skills/<skill-name> --provider codex

# Override persistente de proveedor
export GROOT_MARKETPLACE_EVAL_PROVIDER=codex
```
