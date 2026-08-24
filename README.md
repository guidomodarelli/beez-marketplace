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

`skills/agent-ready-setup` prepara siempre los tres planos sin acoplar assets compartidos a un provider:

```text
AGENTS.md                  # instrucciones canónicas
CLAUDE.md                  # raíz: proxy + regla; subdirectorios: @AGENTS.md
.claude/                   # Agent Ready Score y configuración Claude
.agents/skills/            # skills compartidas y descubribles por Codex
.agents/rules/             # reglas compartidas
.codex/hooks/hooks.json    # hooks específicos Codex
.codex/.mcp.json           # MCP específico Codex
```

Si `CLAUDE.md` ya contiene instrucciones, el setup las promueve a `AGENTS.md` y deja `CLAUDE.md` como `@AGENTS.md`. Si ambos archivos existen y difieren, no sobrescribe ninguno y reporta conflicto para resolución manual. La normalización recursiva respeta `.gitignore` y excluye `node_modules/`; los destinos explícitos `.claude/`, `.agents/` y `.codex/` se siguen preparando aunque estén ignorados.

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

## 🔧 Desarrollo local (symlink)

Mientras desarrollás un plugin, podés enlazar su directorio de skills directamente en la carpeta local del cliente para que los cambios en el repo se reflejen en vivo (sin reinstalar ni hacer `git pull` a través del caché del marketplace).

```bash
SKILL_SRC="$PWD/plugins/<plugin-name>/skills/<skill-name>"
ln -sfn "$SKILL_SRC" ~/.claude/skills/<skill-name>   # Claude Code
ln -sfn "$SKILL_SRC" ~/.codex/skills/<skill-name>    # Codex
```

Reiniciá el cliente después de crear el symlink. Cualquier edición posterior a `SKILL.md`, `subcommands/*.md` o `knowledge/*` se aplica en la siguiente invocación.

### ✅ Qué funciona y qué no con un symlink

| Invocación | Funciona | Notas |
|------------|:--------:|-------|
| `/<plugin-name> <subcommand>` (Claude Code) | ✅ | El skill se activa por descripción; el dispatcher en `SKILL.md` enruta a `subcommands/<arg>.md` |
| `/<plugin-name> <subcommand>` (Codex) | ✅ | Mismo flujo que el anterior |
| Lenguaje natural ("check the X queue") | ✅ | La coincidencia de descripción activa el skill |
| `/<plugin-name>:<subcommand>` (sintaxis con dos puntos de Claude Code) | ❌ | Requiere instalación real del marketplace — Claude Code solo lee `commands/` de plugins registrados en su sistema de plugins, no de un skill enlazado |

> 💡 La sintaxis con `:` es puramente cosmética: `/<plugin-name> <subcommand>` entra por el dispatcher del skill y produce el mismo resultado. Usá la instalación del marketplace solo cuando necesités el atajo `:` o querés testear el flujo completo de instalación.

### 🗑️ Desinstalar

```bash
rm ~/.claude/skills/<skill-name> ~/.codex/skills/<skill-name>
```

Solo elimina los symlinks — el repo no se modifica.

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
