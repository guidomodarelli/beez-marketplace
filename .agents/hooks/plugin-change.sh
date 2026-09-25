#!/usr/bin/env bash
# PostToolUse hook: nudges context-improver when a file under plugins/<name>/
# changes. Extracts the touched path from Claude/Codex tool_input, or from a
# Codex apply_patch command body when no direct path field is present.

set -u

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

# Candidate paths: the direct tool_input fields first, then EVERY file named
# in a Codex apply_patch body, so multi-file patches are not truncated to the
# first entry.
CANDIDATES="$(printf '%s' "$INPUT" | jq -r '
  .tool_input.file_path
  // .tool_input.path
  // .input.file_path
  // empty
' 2>/dev/null || true)"

[ -n "$CANDIDATES" ] || CANDIDATES="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | sed -nE 's#^\*\*\* (Add|Update|Delete) File: (.+)$#\2#p')"

[ -n "$CANDIDATES" ] || exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

while IFS= read -r FILE_PATH; do
  [ -n "$FILE_PATH" ] || continue
  RELATIVE="${FILE_PATH#"$REPO_ROOT/"}"

  [[ "$RELATIVE" == plugins/*/* ]] || continue

  # Reject traversal in any path component: plugins/<name>/../../x.md resolves
  # outside the plugin, so the nudge would fire for an unrelated change.
  [[ "$RELATIVE" =~ (^|/)\.\.(/|$) ]] && continue

  PLUGIN_NAME="$(printf '%s' "$RELATIVE" | cut -d'/' -f2)"
  [ -n "$PLUGIN_NAME" ] || continue
  [[ "$PLUGIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || continue

  jq -n --arg plugin "$PLUGIN_NAME" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: ("A plugin was modified. Call Skill(skill=\"context-improver:skill-cost-optimizer\", args=\"plugins/\($plugin)\") to audit and optimize the skill token cost.")
    }
  }'
  exit 0
done <<CANDIDATES_EOF
$CANDIDATES
CANDIDATES_EOF

exit 0
