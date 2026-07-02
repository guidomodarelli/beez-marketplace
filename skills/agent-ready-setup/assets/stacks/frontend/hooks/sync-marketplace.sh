#!/bin/bash
# sync-marketplace.sh
# Downloads the latest Claude Code configs from the central marketplace.
# Runs automatically on every Claude Code session start (SessionStart hook).
# Requires: gh CLI authenticated (gh auth status).
# Never overwrites settings.json — it owns the hook definition.

set -e

REPO="melisource/fury_groot-marketplace"
BRANCH="main"
STACK="frontend"
CLAUDE_DIR=".claude"

fetch() {
  local remote_path="$1"
  local local_path="$2"
  mkdir -p "$(dirname "$local_path")"
  if gh api "repos/$REPO/contents/$remote_path?ref=$BRANCH" --jq '.content' 2>/dev/null | base64 -d > "$local_path"; then
    echo "[claude-sync] OK $local_path"
  else
    echo "[claude-sync] WARN $remote_path not available"
    rm -f "$local_path"
  fi
}

echo "[claude-sync] Syncing configs from $REPO (stack: $STACK)..."

# mcp.json — rebuilt each session, gitignored
fetch "stacks/$STACK/mcp.json" "$CLAUDE_DIR/mcp.json"

# Rules
for file in security frontend-style testing; do
  fetch "stacks/$STACK/rules/$file.md" "$CLAUDE_DIR/rules/$file.md"
done

# Agents
for file in security-scanner a11y-reviewer perf-analyzer test-reviewer lint-reviewer; do
  fetch "stacks/$STACK/agents/$file.md" "$CLAUDE_DIR/agents/$file.md"
done

# Skills
for file in component-creation api-endpoint service; do
  fetch "stacks/$STACK/skills/$file.md" "$CLAUDE_DIR/skills/$file.md"
done

# Commands
for file in review-pr; do
  fetch "stacks/$STACK/commands/$file.md" "$CLAUDE_DIR/commands/$file.md"
done

echo "[claude-sync] Sync complete."
