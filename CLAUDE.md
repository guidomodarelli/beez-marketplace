# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A multi-provider marketplace of skills and plugins for AI agents at Mercado Libre. No application code — only skill definitions (SKILL.md), reference docs, eval configs, and installer scripts. Supports multiple providers: **Claude Code** and **Codex**.

- `plugins/` — Production-ready plugins for marketplace distribution. Each plugin has provider spec directories (`.claude-plugin/`, `.codex-plugin/`) + `skills/` directory.
- `skills/` — Standalone skills for prototyping. Same internal structure, lighter packaging.
- `skill-installer/` — CLI tool that symlinks skills to `~/.claude/skills/` for local use.
- `skill-eval-runner/` — Central eval runner. Skills only need `evals/eval-config.json`; the runner handles execution, assertions, and reporting.
- `.claude-plugin/marketplace.json` — Claude Code plugin registry. New plugins must be registered here.
- `.agents/plugins/marketplace.json` — Codex plugin registry. Add Codex-compatible plugins here.

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

Leé y seguí literalmente las instrucciones de `~/.claude/skills/<plugin>/subcommands/<name>.md`, aplicándolas a `$ARGUMENTS`.
```

**Invocation matrix**:

| Provider | User types | What loads |
|----------|-----------|------------|
| Claude Code | `/myplugin:setup` | `commands/setup.md` → reads `subcommands/setup.md` |
| Claude Code | `/myplugin setup` | Skill activates → dispatcher reads `subcommands/setup.md` |
| Codex | `/myplugin setup` | Skill activates → dispatcher reads `subcommands/setup.md` |

**Reference implementation**: see `plugins/groot-queue/`. Use it as the template when porting any multi-action plugin to be multi-provider.

## Local Testing

```bash
# One-time setup: install both CLI tools
cd skill-installer && ./install.sh
cd ../skill-eval-runner && ./install.sh

# Install a skill locally (symlink — edits are live, just restart Claude Code)
cd plugins/my-plugin/skills/my-skill && install-skill

# Run evals for a specific skill
run-evals skills/my-skill

# Run evals for all skills
run-evals --all
```

## Bumping a plugin version

```bash
# Interactive: pick a plugin from a numbered menu
npm run create-version

# Target a plugin directly by name
npm run create-version <plugin-name>
```

Updates the `version` field in **both** provider manifests (`.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`) so they stay in sync. Offers a semver bump (`patch`/`minor`/`major`) or a custom exact version, and aborts if the two manifests are not already on the same version. Implemented in `scripts/create-version.js` (zero external deps).
