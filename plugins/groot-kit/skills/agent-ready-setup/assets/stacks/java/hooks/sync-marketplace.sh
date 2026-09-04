#!/bin/bash
# sync-marketplace.sh
# Upgrades groot-marketplace and optionally projects updated assets locally.
# Runs automatically on session start (SessionStart hook).

set -euo pipefail

readonly MARKETPLACE_NAME="groot-marketplace"
readonly SKILL_NAME="agent-ready-setup"

provider=""
stack_override="${AGENT_READY_SETUP_STACK:-}"
sync_requested=0
instructions_requested=0
auto_confirm="${AGENT_READY_SETUP_SYNC_YES:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider|-p)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        printf 'ERROR: %s requires claude or codex\n' "$1" >&2
        exit 1
      fi
      if [[ -n "$provider" ]]; then
        printf 'ERROR: provider argument was provided more than once\n' >&2
        exit 1
      fi
      provider="$2"
      shift 2
      ;;
    claude|codex)
      if [[ -n "$provider" ]]; then
        printf 'ERROR: provider argument does not accept extra values\n' >&2
        exit 1
      fi
      provider="$1"
      shift
      ;;
    --sync|--update)
      sync_requested=1
      shift
      ;;
    --sync-instructions|--merge-instructions)
      sync_requested=1
      instructions_requested=1
      shift
      ;;
    --stack)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        printf 'ERROR: --stack requires frontend, node, java, or go\n' >&2
        exit 1
      fi
      stack_override="$2"
      shift 2
      ;;
    --yes)
      auto_confirm=1
      shift
      ;;
    *)
      printf 'ERROR: unsupported marketplace sync argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$provider" ]]; then
  case "$0" in
    .agents/hooks/sync-marketplace.sh|*/.agents/hooks/sync-marketplace.sh)
      provider="codex"
      ;;
    *)
      provider="claude"
      ;;
  esac
fi

case "$provider" in
  claude|codex) ;;
  *)
    printf 'ERROR: unsupported marketplace provider: %s\n' "$provider" >&2
    exit 1
    ;;
esac

if [[ "$auto_confirm" != 0 && "$auto_confirm" != 1 ]]; then
  printf 'ERROR: AGENT_READY_SETUP_SYNC_YES must be 0 or 1\n' >&2
  exit 1
fi

if [[ "$auto_confirm" -eq 1 && "$sync_requested" -ne 1 ]]; then
  printf 'ERROR: --yes requires --sync or --update\n' >&2
  exit 1
fi

echo "[marketplace-sync] Upgrading $MARKETPLACE_NAME for $provider..."
fury ai assets marketplace upgrade \
  --name "$MARKETPLACE_NAME" \
  --provider "$provider"
echo "[marketplace-sync] Marketplace upgrade completed."

if [[ "$sync_requested" -eq 0 ]]; then
  echo "[marketplace-sync] Local projection not requested; use --sync to update project assets."
  exit 0
fi

resolve_skill_dir() {
  local candidate
  local provider_root
  local cache_root
  local hook_directory
  local project_root

  if [[ -n "${AGENT_READY_SETUP_SKILL_DIR:-}" ]]; then
    candidate="$AGENT_READY_SETUP_SKILL_DIR"
    if [[ -f "$candidate/SKILL.md" && -f "$candidate/scripts/bootstrap.sh" && -d "$candidate/assets/stacks" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    printf 'ERROR: AGENT_READY_SETUP_SKILL_DIR is not a valid %s source: %s\n' "$SKILL_NAME" "$candidate" >&2
    return 1
  fi

  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    for candidate in \
      "$CLAUDE_PLUGIN_ROOT/skills/$SKILL_NAME" \
      "$CLAUDE_PLUGIN_ROOT"; do
      if [[ -f "$candidate/SKILL.md" && -f "$candidate/scripts/bootstrap.sh" && -d "$candidate/assets/stacks" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi

  hook_directory="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  candidate="$hook_directory/../../../.."
  if [[ -f "$candidate/SKILL.md" && -f "$candidate/scripts/bootstrap.sh" && -d "$candidate/assets/stacks" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ "$provider" == "claude" ]]; then
    provider_root="$HOME/.claude"
  else
    provider_root="$HOME/.codex"
  fi

  candidate="$provider_root/skills/$SKILL_NAME"
  if [[ -f "$candidate/SKILL.md" && -f "$candidate/scripts/bootstrap.sh" && -d "$candidate/assets/stacks" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  cache_root="$provider_root/plugins/cache/$MARKETPLACE_NAME/groot-kit"
  while IFS= read -r candidate; do
    candidate="${candidate%/SKILL.md}"
    if [[ -f "$candidate/scripts/bootstrap.sh" && -d "$candidate/assets/stacks" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$cache_root" -type f -path "*/skills/$SKILL_NAME/SKILL.md" -print 2>/dev/null | sort -r)

  if project_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    candidate="$project_root/plugins/groot-kit/skills/$SKILL_NAME"
    if [[ -f "$candidate/SKILL.md" && -f "$candidate/scripts/bootstrap.sh" && -d "$candidate/assets/stacks" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  return 1
}

detect_stack() {
  if [[ -n "$stack_override" ]]; then
    printf '%s\n' "$stack_override"
  elif [[ -f package.json ]]; then
    if grep -qE '"react"|"nordic"|"@andes/[^" ]+"' package.json 2>/dev/null; then
      printf '%s\n' "frontend"
    else
      printf '%s\n' "node"
    fi
  elif [[ -f pom.xml || -f build.gradle || -f build.gradle.kts ]]; then
    printf '%s\n' "java"
  elif [[ -f go.mod ]]; then
    printf '%s\n' "go"
  fi
}

case "$stack_override" in
  ""|frontend|node|java|go) ;;
  *)
    printf 'ERROR: unsupported stack: %s\n' "$stack_override" >&2
    exit 1
    ;;
esac

if ! skill_dir="$(resolve_skill_dir)"; then
  if [[ -n "${AGENT_READY_SETUP_SKILL_DIR:-}" ]]; then
    exit 1
  fi
  printf 'WARNING: could not resolve updated %s source; local projection skipped.\n' "$SKILL_NAME" >&2
  printf 'Set AGENT_READY_SETUP_SKILL_DIR or rerun this hook after installing the provider plugin.\n' >&2
  exit 0
fi

if [[ "$instructions_requested" -eq 1 && ! -f "$skill_dir/scripts/merge-instructions.sh" ]]; then
  printf 'ERROR: resolved %s source does not include merge-instructions.sh: %s\n' "$SKILL_NAME" "$skill_dir" >&2
  exit 1
fi

stack="$(detect_stack || true)"
if [[ -z "$stack" ]]; then
  printf 'WARNING: could not detect project stack; local projection skipped.\n' >&2
  printf 'Rerun with --stack frontend|node|java|go.\n' >&2
  exit 0
fi

bootstrap_args=(
  --stack "$stack"
  --skill-dir "$skill_dir"
  --provider "$provider"
  --sync
)
if [[ "$auto_confirm" -eq 1 ]]; then
  bootstrap_args+=(--yes)
fi

echo "[marketplace-sync] Projecting updated $SKILL_NAME assets for $stack..."
if ! AGENT_READY_SETUP_MARKETPLACE_UPGRADED=1 \
  bash "$skill_dir/scripts/bootstrap.sh" "${bootstrap_args[@]}"; then
  printf 'ERROR: local asset projection failed for %s.\n' "$skill_dir" >&2
  exit 1
fi
echo "[marketplace-sync] Local projection completed."

if [[ "$instructions_requested" -eq 1 ]]; then
  merge_environment=()
  if [[ "$auto_confirm" -eq 1 ]]; then
    merge_environment+=(AGENT_READY_SETUP_NON_INTERACTIVE=1)
  fi

  merge_status=0
  env "${merge_environment[@]}" bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider "$provider" \
    --stack "$stack" \
    --skill-dir "$skill_dir" || merge_status=$?

  case "$merge_status" in
    0)
      echo "[marketplace-sync] Instruction merge completed."
      ;;
    2)
      echo "[marketplace-sync] Instruction merge requires human review; local file preserved."
      ;;
    *)
      printf 'ERROR: instruction merge failed for %s; local file was preserved.\n' "$skill_dir" >&2
      exit 1
      ;;
  esac
fi
