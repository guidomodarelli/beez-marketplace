#!/bin/bash
# sync-marketplace.sh
# Downloads the latest Claude Code configs from the central marketplace.
# Runs automatically on every Claude Code session start (SessionStart hook).
# Never overwrites settings.json — it owns the hook definition.

set -e

BASE="https://raw.githubusercontent.com/meli/claude-marketplace/main"
STACK="frontend"
CLAUDE_DIR=".claude"

echo "[claude-sync] Syncing configs from marketplace (stack: $STACK)..."

mkdir -p "$CLAUDE_DIR/rules" "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/hooks"

# mcp.json — rebuilt each session, gitignored
curl -sf "$BASE/stacks/$STACK/mcp.json" -o "$CLAUDE_DIR/mcp.json" && \
  echo "[claude-sync] OK mcp.json" || \
  echo "[claude-sync] WARN mcp.json not available"

# Rules
for file in security frontend-style testing; do
  curl -sf "$BASE/stacks/$STACK/rules/$file.md" -o "$CLAUDE_DIR/rules/$file.md" && \
    echo "[claude-sync] OK rules/$file.md" || \
    echo "[claude-sync] WARN rules/$file.md not available"
done

# Agents
for file in security-scanner a11y-reviewer perf-analyzer test-reviewer lint-reviewer; do
  curl -sf "$BASE/stacks/$STACK/agents/$file.md" -o "$CLAUDE_DIR/agents/$file.md" && \
    echo "[claude-sync] OK agents/$file.md" || \
    echo "[claude-sync] WARN agents/$file.md not available"
done

# Skills
for file in component-creation api-endpoint service; do
  curl -sf "$BASE/stacks/$STACK/skills/$file.md" -o "$CLAUDE_DIR/skills/$file.md" && \
    echo "[claude-sync] OK skills/$file.md" || \
    echo "[claude-sync] WARN skills/$file.md not available"
done

# Commands
for file in review-pr; do
  curl -sf "$BASE/stacks/$STACK/commands/$file.md" -o "$CLAUDE_DIR/commands/$file.md" && \
    echo "[claude-sync] OK commands/$file.md" || \
    echo "[claude-sync] WARN commands/$file.md not available"
done

echo "[claude-sync] Sync complete."
