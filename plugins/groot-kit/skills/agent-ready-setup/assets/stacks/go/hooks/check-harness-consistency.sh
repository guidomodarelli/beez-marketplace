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

HARNESS_ROOT=""
if [[ "$FILE_PATH" =~ (^|/)\.claude/(rules/|skills/|CLAUDE\.md) ]]; then
  HARNESS_ROOT=".claude"
elif [[ "$FILE_PATH" =~ (^|/)\.agents/(rules/|skills/) ]]; then
  HARNESS_ROOT=".agents"
else
  exit 0
fi

run_consistency_check() {
  local harness_root="$1"

  (
    cd -- "$harness_root" || exit 1
    claude --print \
      'Read all .md files in rules/ and all SKILL.md files in skills/*/. \
Check for contradictions or inconsistencies (conflicting mocking strategies, directory conventions, naming rules, etc). \
Output ONLY the conflicts found as a bullet list, or a single line '\''No contradictions found.'\'' if all is consistent. Be concise.'
  )
}

echo "[harness-check] $FILE_PATH modified — running consistency check..."
run_consistency_check "$HARNESS_ROOT"
