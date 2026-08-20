## What This Repository Is

A multi-provider marketplace of skills and plugins for AI agents at Mercado Libre. No application code — only skill definitions (SKILL.md), reference docs, eval configs, and installer scripts. Supports multiple providers: **Claude Code** and **Codex**.

- `plugins/` — Production-ready plugins for marketplace distribution. Each plugin has provider spec directories (`.claude-plugin/`, `.codex-plugin/`) + `skills/` directory.
- `skills/` — Standalone skills for prototyping. Same internal structure, lighter packaging.
- `skill-eval-runner/` — Central eval runner. Skills only need `evals/eval-config.json`; the runner handles execution, assertions, and reporting. Provider-agnostic.
- `.claude-plugin/marketplace.json` — Claude Code plugin registry. Register plugins here for Claude Code.
- `.agents/plugins/marketplace.json` — Codex plugin registry. Register plugins here for Codex.

For local development, skills symlink into each provider's own skills folder (`~/.claude/skills/` for Claude Code, `~/.codex/skills/` for Codex) — see **Local Testing**.

## Mandatory Rules

1. **Use `/skill-creator`** for all skill creation, modification, validation, and description optimization. Never create skills manually from scratch.
2. **Every skill must have `evals/eval-config.json`** (test cases + assertions). Use the central `run-evals` CLI to execute them — no per-skill `run-evals.sh` needed. Use `/skill-creator` to generate evals. (Legacy skills may use `evals/evals.json` — prefer `eval-config.json` for new work.)
3. **All names in kebab-case** — plugins, skills, directories, commands. Names should convey expertise (e.g., `fury-docs-expert` not `fury-doc-guidelines`).
4. **Pre-commit hooks are mandatory** — websec and datasec (see `.pre-commit-config.yaml`). Do not skip or remove them.

## Conventions

- **SKILL.md frontmatter**: `name`, `description` (max ~100 chars, include trigger keywords), `license`, `metadata` (version, author, category, tags, command). The `description` field drives skill activation — make it count.
- **Branch naming**: `feature/<plugin-or-skill-name>`
- **Commit format**: `feat(marketplace): add <name>` or `feat(skills): add <name>`
- **Reference files are loaded on-demand** — skills declare them but only load when the relevant command executes.
- **Skills EXECUTE actions** — they write files, run installations, produce reports. They don't just show instructions.
- **Start in `skills/`, promote to `plugins/`** when production-ready.
- **Matcher signals must ALWAYS be trilingual (ES + PT + EN)** — any text-matching signal in a skill's knowledge base (e.g. triage rules, classifiers, ticket matchers like `triage-rules.md`) must list the Spanish, Portuguese, **and** English variants of the wording. The support queues (e.g. SSHP) receive tickets in all three languages; a signal written in a single language silently misses real tickets. Before writing or editing any signal, verify it against the real source (e.g. fetch the actual Jira issue) to capture exact wording, language, and status.

## Plugin Structure

A plugin root (`plugins/<name>/`) contains provider-specific spec directories alongside the shared `skills/` directory:

```
plugins/<name>/
  .claude-plugin/plugin.json    ← Claude Code plugin spec (required for Claude)
  .codex-plugin/plugin.json     ← Codex plugin spec (required for Codex)
  skills/                       ← Shared skill implementations
```

**Claude** `.claude-plugin/plugin.json` optional fields:
```json
{
  "agents": "./agents/run.md",
  "mcpServers": "./.mcp.json",
  "hooks": "./hooks/hooks.json"
}
```

**Codex** `.codex-plugin/plugin.json` requires the following minimum schema (validated by the Marketplace Check pipeline — a manifest missing any of these fields will fail CI):

```json
{
  "name": "<kebab-case>",
  "version": "<must match .claude-plugin/plugin.json>",
  "description": "...",
  "author": { "name": "...", "email": "", "url": "" },
  "keywords": ["..."],
  "skills": "./skills/",
  "interface": {
    "displayName": "Human-readable name",
    "shortDescription": "One-line description",
    "category": "Productivity",
    "capabilities": ["Read", "Write", "Bash"]
  }
}
```

Critical points (learned the hard way — see `plugins/prepare-release/.codex-plugin/plugin.json` as the canonical reference):

- **`version` is mandatory** and must match the sibling `.claude-plugin/plugin.json`. This applies even when the plugin is being added to Codex for the first time while already existing on the Claude side — the "shared version" rule trumps "new plugins start at 1.0.0".
- **`skills: "./skills/"`** is required so Codex's loader resolves the skill directory. Without it, the plugin loads but no skills appear.
- **`interface.capabilities`** is required, not optional. Declare it accurately based on what the skill does: `Read` for file reads, `Write` for file writes, `Bash` for shell-outs. Don't copy blindly from another plugin.
- **`author.email` and `author.url`** must be present even as empty strings — match the structure of existing plugins.

Codex plugins **cannot** include: `commands`, `hooks`, or `agents`.

## Multi-Provider Support

### Universal vs Provider-Specific Plugins

**Universal plugin** (same implementation works for all providers):
```
plugins/<name>/
  .claude-plugin/plugin.json
  .codex-plugin/plugin.json
  skills/
```
Both registries reference `"source": "./plugins/<name>"`.

**Provider-specific plugin** (different implementation per provider, optional):
```
plugins/<name>/
  claude/                     ← Claude-specific implementation
    .claude-plugin/plugin.json
    skills/
  codex/                      ← Codex-specific implementation
    .codex-plugin/plugin.json
    skills/
```
Each registry references its provider's subdirectory path.

### Marketplace Registration Rules

- A plugin is only installed for a provider if it appears in that provider's `marketplace.json`.
- **Never add a `version` field to plugin entries in `marketplace.json`** — version is managed by the assets API.
- Plugins must be registered in at least one `marketplace.json`.
- Codex plugin entries in `marketplace.json` must not include `commands`, `hooks`, or `agents`.

### Porting to Codex

Use the `codex-compatibility-analyzer` plugin (available via the assets CLI) to analyze and migrate existing Claude Code plugins to Codex. It validates prerequisites, assesses portability, creates `.codex-plugin/plugin.json`, and registers the plugin in `.agents/plugins/marketplace.json`.

### Subcommands pattern (multi-provider, no duplication)

When a plugin needs multiple discrete actions (e.g. `/myplugin setup`, `/myplugin list`, `/myplugin sync`) and you want it to work in **both** Claude Code and Codex, use the **hybrid subcommands pattern**.

**The problem**:
- Codex cannot use the `commands/` directory — only `skills/` is read.
- Claude Code can use `commands/<name>.md` to enable the nicer `/plugin:name` slash syntax.
- Duplicating subcommand bodies across both is a maintenance trap.

**The pattern**: keep the lógica in **one place** inside the skill, and have Claude's `commands/` be thin wrappers that defer to it.

```
plugins/<name>/
├── .claude-plugin/plugin.json
├── .codex-plugin/plugin.json
├── commands/                              ← Only Claude reads this
│   ├── setup.md          ← 3-line wrapper: defers to subcommands/setup.md
│   ├── list.md
│   └── ...
└── skills/<name>/
    ├── SKILL.md          ← Dispatcher: parses argument, reads subcommands/<arg>.md
    ├── subcommands/      ← SINGLE SOURCE OF TRUTH (read by both providers)
    │   ├── setup.md
    │   ├── list.md
    │   └── ...
    └── knowledge/        ← Shared reference files (read on-demand by subcommands)
```

**Skill dispatcher** (`skills/<name>/SKILL.md`) — at activation, parse the first token after the skill name and read the matching `subcommands/<token>.md`. Without a token, show the help table. This is what makes the plugin work in Codex: the skill is the entry point, the dispatcher routes to subcommand files.

**Claude command wrappers** (`commands/<name>.md`) — keep them to ~3 lines, e.g.:
```markdown
---
description: <same as skill table>
argument-hint: <if applicable>
---

Leé y seguí literalmente las instrucciones de `${CLAUDE_PLUGIN_ROOT}/skills/<plugin>/subcommands/<name>.md`, aplicándolas a `$ARGUMENTS`.
```

**Invocation matrix**:

| Provider | User types | What loads |
|----------|-----------|------------|
| Claude Code | `/myplugin:setup` | `commands/setup.md` → reads `subcommands/setup.md` |
| Claude Code | `/myplugin setup` | Skill activates → dispatcher reads `subcommands/setup.md` |
| Codex | `/myplugin setup` | Skill activates → dispatcher reads `subcommands/setup.md` |

**Reference implementation**: see `plugins/groot-queue/`. Use it as the template when porting any multi-action plugin to be multi-provider.

## Local Testing

Run the canonical shell test commands documented in [`README.md` → “Correr tests shell localmente”](README.md#-correr-tests-shell-localmente). Keep the real setup E2E opt-in.

```bash
# One-time setup: install the eval runner (provider-agnostic)
cd skill-eval-runner && ./install.sh

# Install a skill locally (symlink — edits are live, just restart your agent).
# Point it at the skills folder of whichever provider(s) you run:
SKILL_SRC="$PWD/plugins/<plugin-name>/skills/<skill-name>"
ln -sfn "$SKILL_SRC" ~/.claude/skills/<skill-name>   # Claude Code
ln -sfn "$SKILL_SRC" ~/.codex/skills/<skill-name>    # Codex

# Run evals for a specific skill (JSONL by default)
run-evals plugins/<plugin-name>/skills/<skill-name>

# Run evals for all skills (JSONL by default)
run-evals --all

# Optional human-readable colored report
run-evals plugins/<plugin-name>/skills/<skill-name> --pretty

# Optional provider override (default: auto-detect Codex or Claude)
run-evals plugins/<plugin-name>/skills/<skill-name> --provider codex

# Optional persistent provider override
export GROOT_MARKETPLACE_EVAL_PROVIDER=codex
```

## Bumping a plugin version

```bash
# Interactive: pick a plugin from a numbered menu
npm run create-version

# Target a plugin directly by name
npm run create-version <plugin-name>
```

Updates the `version` field in **both** provider manifests (`.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`) so they stay in sync. Offers a semver bump (`patch`/`minor`/`major`) or a custom exact version, and aborts if the two manifests are not already on the same version. Implemented in `scripts/create-version.js` (zero external deps).

## Identidad del equipo

> Fuente de verdad: `plugins/groot-queue/skills/groot-queue/knowledge/teams/groot-team.md`

- **Nosotros somos el equipo Groot**. Groot se compone de dos células: **Kraken** y **Nexus**. Ver [`groot-team.md`](./plugins/groot-queue/skills/groot-queue/knowledge/teams/groot-team.md) para estructura y ownership, y [`nexus-team.md`, sección `Productos a cargo`](./plugins/groot-queue/skills/groot-queue/knowledge/teams/nexus-team.md#productos-a-cargo) para el catálogo Nexus.
- Nunca referirse al equipo como si fuera externo ("escalar al equipo dev Groot"). Somos nosotros.
- Nunca mencionar ni sugerir `context_id` de Jira en soluciones, runbooks, guías ni respuestas. No es útil para diagnóstico ni resolución — es un dato interno de Jira sin valor operativo.

## Single source of truth

- Toda pieza de información (procedimiento, roster, config, catálogo de IDs, formato, criterio) debe vivir en **un solo archivo** bien organizado con secciones claras.
- El resto de archivos que necesiten esa información deben **referenciar** el archivo + sección, nunca copiar el contenido.
- Antes de escribir un bloque de texto en un subcommand o regla, verificar si ya existe en otro archivo de `knowledge/`. Si existe, referenciar. Si no existe y es reutilizable, crearlo en `knowledge/` y referenciar.
- Cuando se detecte información duplicada entre archivos, consolidarla en el archivo más apropiado y reemplazar las copias por referencias.

## Reglas de contenido para archivos de knowledge base

- **No incluir LDAPs ni identificadores de usuario específicos** en archivos de knowledge base (soluciones, reglas de triage, runbooks). Usar siempre referencias genéricas: `<ldap_usuario>`, `<ldap_externo>`, `<groot_id>`, `<nombre_usuario>`. Los patrones de prefijo sí son válidos (ej. `ext_*` para identificar el tipo de cuenta). El LDAP real pertenece al ticket SSHP, no a la KB.
- **Orden canónico de campos en frontmatter** de archivos `solutions/**/*.md`: `ticket` → `category` → `summary` → `date` → `effectiveness` → `verdict` → `rule` → `destination` → `source`. Omitir campos opcionales que no apliquen. No usar `derived_to` (usar `destination`). No usar `subverdict`.

## Paridad de flujos de resolución

- Todo cambio funcional, fuente de evidencia, fact remoto, runbook o caso reusable agregado a `plugins/groot-queue/skills/groot-queue/subcommands/solve.md` debe evaluarse y reflejarse también en `subcommands/assign-unassigned.md`, porque este subcommand clasifica y genera resolución para tickets antes de asignarlos.
- Revisar además `subcommands/detail.md`, que invoca explícitamente lógica de `solve`, y `subcommands/backfill-guides.md`, que genera guías con mismos runbooks, solutions y evidence. Aplicar cambio cuando corresponda al flujo; si no corresponde, dejar razón explícita en validación final.
- No cerrar cambio relacionado con resolución sin revisar estos cuatro archivos: `solve.md`, `assign-unassigned.md`, `detail.md` y `backfill-guides.md`.
- Mantener diferencias de superficie: `solve` y `detail` son read-only; `assign-unassigned` y `backfill-guides` conservan sus gates, confirmaciones y restricciones de escritura propios.

## Uso de subagentes

- No crear subagentes salvo pedido explícito del usuario.
- Para búsquedas, reviews y análisis multiarchivo, trabajar directamente en la sesión principal.
