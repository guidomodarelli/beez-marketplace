#!/bin/bash
# check-harness-consistency.sh
# PostToolUse hook — runs after Write/Edit.
# Checks consistency of harness files when any of them is modified.

set -euo pipefail

STDIN=$(cat)
FILE_PATH=$(echo "$STDIN" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except:
    print('')
" 2>/dev/null || echo "")

if ! echo "$FILE_PATH" | grep -qE "\.claude/(rules/|skills/|CLAUDE\.md)"; then
  exit 0
fi

echo "[harness-check] $FILE_PATH modified — running consistency check..."

claude --print \
  "Read all .md files in .claude/rules/ and all SKILL.md files in .claude/skills/*/. \
Check for contradictions or inconsistencies (conflicting mocking strategies, directory conventions, naming rules, etc). \
Output ONLY the conflicts found as a bullet list, or a single line 'No contradictions found.' if all is consistent. Be concise."
