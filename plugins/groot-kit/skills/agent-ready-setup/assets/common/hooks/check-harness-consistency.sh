#!/bin/bash
# PostToolUse hook for Claude file inputs and Codex apply_patch commands.
set -euo pipefail

# Extract only roots from file paths or patch headers, never execute patch text.
harness_roots=$(python3 -c '
import json
import re
import sys

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(0)
if not isinstance(payload, dict):
    sys.exit(0)
tool_input = payload.get("tool_input")
if not isinstance(tool_input, dict):
    sys.exit(0)
paths = []
file_path = tool_input.get("file_path")
if isinstance(file_path, str):
    paths.append(file_path)
command = tool_input.get("command")
if payload.get("tool_name") == "apply_patch" and isinstance(command, str):
    for line in command.splitlines():
        header = re.match(r"^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$", line)
        if header:
            paths.append(header.group(1))
roots = set()
for path in paths:
    if re.search(r"(^|/)\.claude/(rules/|skills/|CLAUDE\.md$)", path):
        roots.add(".claude")
    if re.search(r"(^|/)\.agents/(rules/|skills/)", path):
        roots.add(".agents")
for root in sorted(roots):
    print(root)
')
[[ -n "$harness_roots" ]] || exit 0

project_root=$(git rev-parse --show-toplevel)
while IFS= read -r harness_root; do
  printf '[harness-check] %s modified — running consistency check...\n' "$harness_root"
  (
    cd -- "$project_root/$harness_root"
    claude --print \
      'Read all .md files in rules/ and all SKILL.md files in skills/*/. \
Check for contradictions or inconsistencies (conflicting mocking strategies, directory conventions, naming rules, etc). \
Output ONLY the conflicts found as a bullet list, or a single line '\''No contradictions found.'\'' if all is consistent. Be concise.'
  )
done <<< "$harness_roots"
