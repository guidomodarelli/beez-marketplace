#!/bin/bash
# resolve-provider.sh
# Resolves active provider from an explicit override or installed skill path.

set -euo pipefail

skill_dir=""
provider_override="${AGENT_READY_SETUP_ACTIVE_PROVIDER:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-dir)
      [[ $# -ge 2 && -n "${2:-}" ]] || {
        printf 'ERROR: --skill-dir requires a value\n' >&2
        exit 1
      }
      skill_dir="$2"
      shift 2
      ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$skill_dir" ]]; then
  printf 'ERROR: --skill-dir is required\n' >&2
  exit 1
fi

if [[ -n "$provider_override" ]]; then
  case "$provider_override" in
    claude|codex)
      printf '%s\n' "$provider_override"
      exit 0
      ;;
    *)
      printf 'ERROR: AGENT_READY_SETUP_ACTIVE_PROVIDER must be claude or codex\n' >&2
      exit 1
      ;;
  esac
fi

if [[ "$skill_dir" == "$HOME/.codex" || "$skill_dir" == "$HOME/.codex/"* ]]; then
  printf '%s\n' "codex"
elif [[ "$skill_dir" == "$HOME/.claude" || "$skill_dir" == "$HOME/.claude/"* ]]; then
  printf '%s\n' "claude"
elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && ( "$skill_dir" == "$CLAUDE_PLUGIN_ROOT" || "$skill_dir" == "$CLAUDE_PLUGIN_ROOT/"* ) ]]; then
  printf '%s\n' "claude"
else
  printf 'ERROR: could not infer provider from skill directory: %s; set AGENT_READY_SETUP_ACTIVE_PROVIDER or pass --provider\n' "$skill_dir" >&2
  exit 1
fi
