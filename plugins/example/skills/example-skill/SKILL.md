---
name: example-skill
description: Example skill. Shows how to contribute a skill or plugin. Trigger with /example or when asking how to contribute to the marketplace.
license: MIT
metadata:
  version: "1.0.0"
  author: ""
  category: "example"
  tags: "example, contribute, marketplace"
  command: "/example"
---

# Example Skill

This is a placeholder skill. Replace its contents with your team's first real skill.

## How to contribute a new skill

### 1. Create the skill

Use `/skill-creator` in Claude Code — it scaffolds the SKILL.md, reference docs, and eval config automatically.

### 2. Prototype in `skills/`

```
skills/my-skill-name/
├── SKILL.md           ← frontmatter + instructions (this file)
├── references/        ← optional: extra docs loaded on-demand
└── evals/
    └── eval-config.json
```

### 3. Promote to `plugins/` when ready

```
plugins/my-plugin/
├── .claude-plugin/
│   └── plugin.json    ← plugin metadata + version
└── skills/
    └── my-skill-name/
        └── SKILL.md
```

Register the plugin in `.claude-plugin/marketplace.json` and open a PR. The CI pipeline validates and auto-approves if all checks pass.

### 4. Skill naming conventions

- All names in **kebab-case**: `my-skill-name`, not `MySkillName`
- Description (~100 chars) must include **trigger keywords** — this drives automatic skill activation
- Command in format `/my-command`

### 5. Mandatory checklist before PR

- [ ] `evals/eval-config.json` exists with at least 2 test cases
- [ ] Plugin version starts at `1.0.0` (or bumped if updating existing)
- [ ] Plugin registered in `.claude-plugin/marketplace.json`
- [ ] Pre-commit hooks installed: `pip install pre-commit && pre-commit install`
