#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../run-evals.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

bin_dir="$tmp_dir/bin"
skill_dir="$tmp_dir/contract-skill"
mkdir -p "$bin_dir" "$skill_dir/evals"

cat > "$skill_dir/SKILL.md" <<'SKILL'
---
name: contract-skill
description: Contract skill for eval runner environment tests.
---

# Contract Skill
SKILL

cat > "$skill_dir/evals/eval-config.json" <<'JSON'
{
  "skill": "contract-skill",
  "test_cases": [
    {
      "id": "contract",
      "description": "runner contract",
      "input": "Reply ok",
      "assertions": [
        {
          "type": "contains",
          "value": "ok"
        }
      ]
    }
  ]
}
JSON

cat > "$bin_dir/claude" <<'CLAUDE_STUB'
#!/bin/bash

printf '%s\n' "$*" >> "$CLAUDE_ARGS_LOG"

case "$*" in
  *eval-provider-ready*)
    printf 'eval-provider-ready\n'
    ;;
  *)
    printf 'ok\n'
    ;;
esac
CLAUDE_STUB
chmod +x "$bin_dir/claude"

args_log="$tmp_dir/claude-args.log"

PATH="$bin_dir:$PATH" \
CLAUDE_ARGS_LOG="$args_log" \
GROOT_MARKETPLACE_EVAL_PROVIDER=claude \
"$RUNNER" --jobs 1 "$skill_dir" > "$tmp_dir/default-model-output.jsonl"

if ! grep -q -- '--model haiku' "$args_log"; then
  echo "run-evals should use the Claude default model when GROOT_MARKETPLACE_EVAL_MODEL is unset." >&2
  exit 1
fi

: > "$args_log"

PATH="$bin_dir:$PATH" \
CLAUDE_ARGS_LOG="$args_log" \
GROOT_MARKETPLACE_EVAL_PROVIDER=claude \
GROOT_MARKETPLACE_EVAL_MODEL=prefixed-model \
"$RUNNER" --jobs 1 "$skill_dir" > "$tmp_dir/prefixed-model-output.jsonl"

if ! grep -q -- '--model prefixed-model' "$args_log"; then
  echo "run-evals should pass GROOT_MARKETPLACE_EVAL_MODEL to the provider." >&2
  exit 1
fi
