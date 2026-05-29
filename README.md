# Fury Plugins Marketplace

Multi-provider skills and plugins marketplace template for Mercado Libre teams. Supports **Claude Code** and **Codex**.

---

## Getting started (first-time setup)

After creating your marketplace from this template, do these steps before adding any plugins:

### 1. Update `marketplace.json`

Open `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json` and set the `name` field to something that describes your marketplace. It doesn't need to match the repository name — use something short and meaningful:

```json
{
  "name": "fintech-marketplace",
  ...
}
```

> The CI pipeline will block PRs that still have the template default name (`plugins-marketplace`).

### 2. Install pre-commit hooks

```bash
pip install pre-commit && pre-commit install
```

---

## Repository structure

```
├── .claude-plugin/
│   └── marketplace.json        # Claude Code plugin registry
├── .agents/plugins/
│   └── marketplace.json        # Codex plugin registry
├── plugins/
│   └── <plugin-name>/
│       ├── .claude-plugin/
│       │   └── plugin.json     # Claude Code plugin manifest
│       ├── .codex-plugin/
│       │   └── plugin.json     # Codex plugin manifest (if Codex-compatible)
│       └── skills/
│           └── <skill-name>/
│               ├── SKILL.md    # Skill definition — required for every skill
│               └── evals/
│                   └── eval-config.json
└── skill-eval-runner/          # CLI to run evals locally
```

### Provider-specific implementations (optional)

When a plugin requires a different implementation per provider, use provider subdirectories instead of a shared `skills/`:

```
plugins/<plugin-name>/
├── claude/
│   ├── .claude-plugin/plugin.json
│   └── skills/
└── codex/
    ├── .codex-plugin/plugin.json
    └── skills/
```

Each registry then references its provider's subdirectory path (e.g. `./plugins/<name>/codex`).

---

## Installing this marketplace

**Claude Code:**
```bash
fury ai assets marketplace install --name <marketplace-slug>
```

Or using the Claude Code plugin command:
```
/plugin marketplace add melisource/<your-repo-name>
```

**Codex:**
```bash
fury ai assets marketplace install --name <marketplace-slug> --codex
```

---

## Local development install (symlink)

While developing a plugin, you can symlink its skill directory directly into your client's local skills folder so edits in the repo are reflected live (no reinstall, no `git pull` cycle through the marketplace cache).

```bash
SKILL_SRC="$PWD/plugins/<plugin-name>/skills/<skill-name>"
ln -sfn "$SKILL_SRC" ~/.claude/skills/<skill-name>   # Claude Code
ln -sfn "$SKILL_SRC" ~/.codex/skills/<skill-name>    # Codex
```

Restart the client after creating the symlink. Any subsequent edit to `SKILL.md`, `subcommands/*.md`, or `knowledge/*` is picked up on the next invocation.

### What works and what doesn't with a symlink

| Invocation | Works | Notes |
|------------|-------|-------|
| `/<plugin-name> <subcommand>` (Claude Code) | ✅ | Skill activates by description; dispatcher in `SKILL.md` routes to `subcommands/<arg>.md` |
| `/<plugin-name> <subcommand>` (Codex) | ✅ | Same flow as above |
| Natural language ("check the X queue") | ✅ | Description match activates the skill |
| `/<plugin-name>:<subcommand>` (Claude Code colon syntax) | ❌ | Requires a real marketplace install — Claude Code only reads `commands/` from plugins registered through its plugin system, not from a symlinked skill |

The colon syntax is purely cosmetic: `/<plugin-name> <subcommand>` enters through the skill dispatcher and produces the same result. Use the marketplace install (next section) only when you need the `:` shorthand or want to test the full plugin install path.

### Uninstall

```bash
rm ~/.claude/skills/<skill-name> ~/.codex/skills/<skill-name>
```

Removes the symlinks only — the repo is untouched.

---

## Adding a plugin

1. Create a feature branch: `feature/<plugin-name>`
2. Add your plugin under `plugins/<plugin-name>/` following the structure above
3. Register it in the applicable registry files:
   - `.claude-plugin/marketplace.json` for Claude Code
   - `.agents/plugins/marketplace.json` for Codex
4. Open a PR — the CI pipeline validates structure and versions automatically

A plugin must appear in at least one registry. A plugin is only installed for a provider if it's listed in that provider's `marketplace.json`.

> All `plugin.json` files within the same plugin (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`) must share the same version. The RP enforces this — if any skill changes, all provider manifests must bump together.

**Commit format:** `feat(marketplace): add <name>`

---

## Bumping a plugin version

Use the `create-version` script to bump a plugin's version. It updates the `version` field in **both** provider manifests (`.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`) at once, keeping them in sync.

```bash
npm run create-version              # interactive: pick a plugin from a numbered menu
npm run create-version groot-queue  # target a plugin directly by name
```

The script then asks how to set the new version — a semver bump (`patch` / `minor` / `major`) computed from the current one, or a custom exact version. Before writing, it validates that both manifests already share the same version and aborts if they differ, so you never bump from an inconsistent state.

---

## Porting a plugin to Codex

Use the `codex-compatibility-analyzer` skill (available via the assets CLI) to migrate an existing Claude Code plugin to Codex. It validates prerequisites, assesses portability, generates `.codex-plugin/plugin.json`, and registers the plugin in `.agents/plugins/marketplace.json`.

---

## PR Validation

Every pull request is validated automatically by the Release Process (RP) using a YaCI custom-check pipeline. The following checks run on each PR:

| Check | When it runs |
|---|---|
| **Marketplace registry** | When `marketplace.json` is touched — validates JSON syntax, name is not the template default, no duplicate entries, removed plugins have their directories deleted too |
| **Plugin validation** | For PRs adding or modifying plugins — checks `plugin.json` required fields, kebab-case name, version starts at `1.0.0` for new plugins, version bumped for modified plugins, `SKILL.md` present in every skill |
| **Marketplace sync** | For PRs adding or modifying plugins — verifies every local plugin directory is registered in `marketplace.json` |

If any check fails, the PR is blocked until the issue is fixed.

---

## Running evals locally

```bash
# One-time setup
cd skill-eval-runner && ./install.sh

# Run evals for a specific skill
run-evals plugins/<plugin-name>/skills/<skill-name>
```
