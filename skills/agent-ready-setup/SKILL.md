---
name: agent-ready-setup
description: >-
  Inspects the current project, detects its stack (frontend, node, java, go),
  and scaffolds the .claude/ directory with all Agent Ready Score dimensions
  using stack-specific templates. Never overwrites existing files — only adds
  what is missing. Use when the user says "configurar agent ready",
  "setup agent ready", "bootstrap claude", "inicializar configuração claude",
  "quiero ser agent ready", "make this repo agent ready", or asks how to pass
  the Agent Ready Score. Also trigger when the user wants to set up Claude Code
  in a project that has no .claude/ directory or is missing some dimensions.
license: MIT
metadata:
  version: "1.0.0"
  author: "guponce"
  category: "developer-experience"
  tags: "agent-ready, claude-code, bootstrap, setup, scaffold"
  command: "/agent-ready-setup"
---

# Agent Ready Setup

Detect the project stack and scaffold `.claude/` with all Agent Ready Score
dimensions. Files that already exist are never overwritten — only missing ones
are added.

Templates live in `assets/stacks/<stack>/` and mirror the `.claude/` structure
exactly. Adding or editing a dimension for a stack is just editing a file there.

---

## Step 1 — Resolve SKILL_DIR

```bash
if [[ -n "$AGENT_READY_SETUP_SKILL_DIR" ]]; then
  SKILL_DIR="$AGENT_READY_SETUP_SKILL_DIR"
elif [[ -f "$HOME/.claude/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$HOME/.claude/skills/agent-ready-setup"
elif [[ -f "$HOME/.codex/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$HOME/.codex/skills/agent-ready-setup"
else
  SKILL_DIR="$(pwd)/skills/agent-ready-setup"
fi
```

---

## Step 2 — Detect stack

Inspect the project root. Use this priority order:

| File present | Stack |
|---|---|
| `package.json` with `react`, `nordic`, or `@andes` in dependencies | `frontend` |
| `package.json` without React/Nordic | `node` |
| `pom.xml` or `build.gradle` | `java` |
| `go.mod` | `go` |

```bash
detect_stack() {
  if [[ -f "go.mod" ]]; then
    echo "go"
  elif [[ -f "pom.xml" || -f "build.gradle" || -f "build.gradle.kts" ]]; then
    echo "java"
  elif [[ -f "package.json" ]]; then
    if grep -qE '"react"|"nordic"|"@andes"' package.json 2>/dev/null; then
      echo "frontend"
    else
      echo "node"
    fi
  else
    echo ""
  fi
}

STACK=$(detect_stack)
```

If detection returns empty, tell the user the stack could not be determined and
ask them to specify one of: `frontend`, `node`, `java`, `go`.

If detection succeeds, confirm before proceeding:
> "Detected stack: **<STACK>**. Running agent-ready-setup — only missing files will be created."

---

## Step 3 — Run bootstrap script

```bash
bash "$SKILL_DIR/scripts/bootstrap.sh" \
  --stack "$STACK" \
  --skill-dir "$SKILL_DIR"
```

The script walks `assets/stacks/<stack>/` and copies each file to `.claude/`,
skipping any that already exist. It prints two lists: **Created** and **Already existed (skipped)**.

---

## Step 4 — Report

Show the script output as-is. Then append:

```
Next steps:
  1. Fill in .claude/CLAUDE.md — add project description, commands, and architecture.
  2. Complete each placeholder file under .claude/rules/, .claude/agents/, etc.
     (Each file has a comment explaining what goes there.)
  3. Verify all dimensions in the Agent Ready Score — all should be green.
```

If any files were skipped, add:
> "Existing files were not modified. Review them to make sure they cover the same dimensions as the templates."
