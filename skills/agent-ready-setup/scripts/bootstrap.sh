#!/bin/bash
# bootstrap.sh
# Projects Agent Ready templates into Claude, shared-agent, and Codex trees.
# Existing assets are never overwritten. Root instructions are normalized so
# AGENTS.md is canonical and CLAUDE.md is a proxy with root-only guidance.
#
# Usage:
#   bash bootstrap.sh --stack <frontend|node|java|go> --skill-dir <path>

set -euo pipefail

STACK=""
SKILL_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      [[ $# -ge 2 ]] || { echo "ERROR: --stack requires a value" >&2; exit 1; }
      STACK="$2"
      shift 2
      ;;
    --skill-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --skill-dir requires a value" >&2; exit 1; }
      SKILL_DIR="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$STACK" || -z "$SKILL_DIR" ]]; then
  echo "ERROR: --stack and --skill-dir are required" >&2
  exit 1
fi

case "$STACK" in
  frontend|node|java|go) ;;
  *)
    echo "ERROR: Unsupported stack '$STACK'. Expected frontend, node, java, or go." >&2
    exit 1
    ;;
esac

if [[ ! -d "$SKILL_DIR" ]]; then
  echo "ERROR: --skill-dir must point to an existing directory: $SKILL_DIR" >&2
  exit 1
fi

SRC="$SKILL_DIR/assets/stacks/$STACK"
CODEX_ASSETS="$SKILL_DIR/assets/codex"
ROOT_CLAUDE_TEMPLATE="$SKILL_DIR/assets/root-claude.md"
CENTRALIZATION_TEMPLATE="$SKILL_DIR/assets/instruction-centralization.md"

if [[ ! -d "$SRC" ]]; then
  echo "ERROR: No template found for stack '$STACK' at $SRC" >&2
  exit 1
fi

if [[ ! -f "$SRC/CLAUDE.md" ]]; then
  echo "ERROR: Stack template is missing CLAUDE.md: $SRC/CLAUDE.md" >&2
  exit 1
fi

if [[ ! -f "$CODEX_ASSETS/hooks.json" ]]; then
  echo "ERROR: Codex hook template is missing: $CODEX_ASSETS/hooks.json" >&2
  exit 1
fi

if [[ ! -f "$ROOT_CLAUDE_TEMPLATE" ]]; then
  echo "ERROR: Root CLAUDE.md template is missing: $ROOT_CLAUDE_TEMPLATE" >&2
  exit 1
fi

if [[ ! -f "$CENTRALIZATION_TEMPLATE" ]]; then
  echo "ERROR: Instruction centralization template is missing: $CENTRALIZATION_TEMPLATE" >&2
  exit 1
fi

CLAUDE_DIR=".claude"
SHARED_DIR=".agents"
CODEX_DIR=".codex"
AGENTS_FILE="AGENTS.md"
CLAUDE_FILE="CLAUDE.md"
CLAUDE_PROXY="@AGENTS.md"
CREATED=()
SKIPPED=()
MIGRATED=()
CONFLICTS=()
PROVIDER_ROOT_CONFLICTS=()

validate_provider_roots() {
  local provider_root

  for provider_root in "$CLAUDE_DIR" "$SHARED_DIR" "$CODEX_DIR"; do
    if [[ -L "$provider_root" ]]; then
      PROVIDER_ROOT_CONFLICTS+=("$provider_root is a symlink; neither provider asset was changed")
    elif [[ -e "$provider_root" && ! -d "$provider_root" ]]; then
      PROVIDER_ROOT_CONFLICTS+=("$provider_root is not a directory; neither provider asset was changed")
    fi
  done

  if [[ ${#PROVIDER_ROOT_CONFLICTS[@]} -gt 0 ]]; then
    echo "Provider root conflicts (manual resolution required):" >&2
    for conflict in "${PROVIDER_ROOT_CONFLICTS[@]}"; do
      printf '  ! %s\n' "$conflict" >&2
    done
    exit 1
  fi
}

validate_provider_roots

record_created() {
  CREATED+=("$1")
}

record_skipped() {
  SKIPPED+=("$1")
}

# Copy a file only when destination is absent. Treat symlinks as existing so a
# broken symlink cannot be replaced or redirected by the bootstrap.
copy_if_missing() {
  local src="$1"
  local dst="$2"

  mkdir -p -- "$(dirname -- "$dst")"

  if [[ -e "$dst" || -L "$dst" ]]; then
    record_skipped "$dst"
  else
    cp -- "$src" "$dst"
    record_created "$dst"
  fi
}

is_normalized_root_claude() {
  [[ -f "$CLAUDE_FILE" ]] && cmp -s "$CLAUDE_FILE" "$ROOT_CLAUDE_TEMPLATE"
}

is_plain_claude_proxy() {
  local claude_file="$1"

  [[ -f "$claude_file" ]] && [[ "$(cat -- "$claude_file")" == "$CLAUDE_PROXY" ]]
}

create_root_agents_from_template() {
  mkdir -p -- "$(dirname -- "$AGENTS_FILE")"
  sed -e 's|@\./rules/|@.agents/rules/|g' "$SRC/CLAUDE.md" > "$AGENTS_FILE"
  record_created "$AGENTS_FILE"
}

# Build root instruction files without maintaining two independent templates.
# Existing non-proxy CLAUDE.md is promoted only when AGENTS.md is absent or
# already contains the same bytes. Divergent files remain untouched.
normalize_root_instructions() {
  if [[ -L "$CLAUDE_FILE" || -L "$AGENTS_FILE" ]]; then
    CONFLICTS+=("$CLAUDE_FILE and $AGENTS_FILE include symlinked instructions; neither was followed or overwritten")
    return
  fi

  if [[ -e "$CLAUDE_FILE" && ! -f "$CLAUDE_FILE" ]]; then
    CONFLICTS+=("$CLAUDE_FILE is not a regular file; neither instruction file was changed")
    return
  fi

  if [[ -e "$AGENTS_FILE" && ! -f "$AGENTS_FILE" ]]; then
    CONFLICTS+=("$AGENTS_FILE is not a regular file; neither instruction file was changed")
    return
  fi

  if [[ -e "$CLAUDE_FILE" ]]; then
    if is_normalized_root_claude; then
      record_skipped "$CLAUDE_FILE"
      if [[ -e "$AGENTS_FILE" || -L "$AGENTS_FILE" ]]; then
        record_skipped "$AGENTS_FILE"
      else
        create_root_agents_from_template
      fi
      return
    fi

    if [[ ! -e "$AGENTS_FILE" && ! -L "$AGENTS_FILE" ]]; then
      cp -- "$CLAUDE_FILE" "$AGENTS_FILE"
      cp -- "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
      MIGRATED+=("$CLAUDE_FILE -> $AGENTS_FILE")
      return
    fi

    if [[ -f "$CLAUDE_FILE" && -f "$AGENTS_FILE" ]] && cmp -s "$CLAUDE_FILE" "$AGENTS_FILE"; then
      cp -- "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
      MIGRATED+=("$CLAUDE_FILE -> $AGENTS_FILE")
    elif is_plain_claude_proxy "$CLAUDE_FILE"; then
      cp -- "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
      MIGRATED+=("$CLAUDE_FILE -> root instruction proxy")
    else
      CONFLICTS+=("$CLAUDE_FILE and $AGENTS_FILE differ; neither was overwritten")
    fi
    return
  fi

  if [[ -e "$AGENTS_FILE" || -L "$AGENTS_FILE" ]]; then
    record_skipped "$AGENTS_FILE"
    copy_if_missing "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
    return
  fi

  # The template is the single source. Only path references need adaptation
  # for the neutral shared tree consumed through AGENTS.md.
  create_root_agents_from_template
  cp -- "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
  record_created "$CLAUDE_FILE"
}

normalize_root_instructions

ensure_root_centralization_rule() {
  if [[ ${#CONFLICTS[@]} -gt 0 || ! -f "$AGENTS_FILE" ]]; then
    return 0
  fi

  if grep -Fqx '## Centralización recursiva de instrucciones' "$AGENTS_FILE"; then
    return 0
  fi

  printf '\n' >> "$AGENTS_FILE"
  cat "$CENTRALIZATION_TEMPLATE" >> "$AGENTS_FILE"
  MIGRATED+=("centralization rule -> $AGENTS_FILE")
}

ensure_root_centralization_rule

normalize_nested_instruction_pair() {
  local directory="$1"
  local claude_file="$directory/$CLAUDE_FILE"
  local agents_file="$directory/$AGENTS_FILE"

  if [[ -L "$claude_file" || -L "$agents_file" ]]; then
    CONFLICTS+=("$claude_file and $agents_file include symlinked instructions; neither was followed or overwritten")
    return
  fi

  if [[ -e "$claude_file" && ! -f "$claude_file" ]]; then
    CONFLICTS+=("$claude_file is not a regular file; neither instruction file was changed")
    return
  fi

  if [[ -e "$agents_file" && ! -f "$agents_file" ]]; then
    CONFLICTS+=("$agents_file is not a regular file; neither instruction file was changed")
    return
  fi

  if [[ -e "$claude_file" ]]; then
    if is_plain_claude_proxy "$claude_file"; then
      if [[ -e "$agents_file" ]]; then
        record_skipped "$claude_file"
        record_skipped "$agents_file"
      else
        CONFLICTS+=("$claude_file is an orphaned proxy; $agents_file is missing and neither instruction file was changed")
      fi
      return
    fi

    if [[ ! -e "$agents_file" ]]; then
      cp -- "$claude_file" "$agents_file"
      printf '%s\n' "$CLAUDE_PROXY" > "$claude_file"
      MIGRATED+=("$claude_file -> $agents_file")
    elif cmp -s "$claude_file" "$agents_file"; then
      printf '%s\n' "$CLAUDE_PROXY" > "$claude_file"
      MIGRATED+=("$claude_file -> $agents_file")
    else
      CONFLICTS+=("$claude_file and $agents_file differ; neither was overwritten")
    fi
    return
  fi

  if [[ -e "$agents_file" ]]; then
    printf '%s\n' "$CLAUDE_PROXY" > "$claude_file"
    MIGRATED+=("$agents_file -> $claude_file proxy")
  fi
}

normalize_nested_instructions() {
  local directory

  while IFS= read -r -d '' directory; do
    [[ "$directory" == "." ]] && continue
    if [[ -e "$directory/$CLAUDE_FILE" || -L "$directory/$CLAUDE_FILE" || \
          -e "$directory/$AGENTS_FILE" || -L "$directory/$AGENTS_FILE" ]]; then
      normalize_nested_instruction_pair "$directory"
    fi
  done < <(find . -name .git -prune -o -type d -print0)
}

normalize_nested_instructions

create_skill_adapter() {
  local src="$1"
  local skill_name="$2"
  local dst="$SHARED_DIR/skills/$skill_name/SKILL.md"

  mkdir -p -- "$(dirname -- "$dst")"
  if [[ -e "$dst" || -L "$dst" ]]; then
    record_skipped "$dst"
    return
  fi

  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$skill_name"
    printf 'description: Provider-neutral reusable workflow for %s.\n' "$skill_name"
    printf '%s\n\n' '---'
    awk '
      NR == 1 && $0 == "---" { in_frontmatter = 1; next }
      in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
      !in_frontmatter { print }
    ' "$src"
  } > "$dst"
  record_created "$dst"
}

# Project every template file into Claude and shared-agent trees. CLAUDE.md is
# represented by the root instruction pair; settings.json remains Claude-only.
while IFS= read -r -d '' file; do
  relative="${file#"$SRC/"}"

  if [[ "$relative" == "CLAUDE.md" ]]; then
    continue
  elif [[ "$relative" == "settings.json" ]]; then
    copy_if_missing "$file" "$CLAUDE_DIR/$relative"
  else
    copy_if_missing "$file" "$CLAUDE_DIR/$relative"

    case "$relative" in
      skills/*/SKILL.md)
        skill_name="${relative#skills/}"
        skill_name="${skill_name%/SKILL.md}"
        create_skill_adapter "$file" "$skill_name"
        ;;
      skills/*/*.md)
        copy_if_missing "$file" "$SHARED_DIR/$relative"
        ;;
      agents/*.md|commands/*.md|skills/*.md)
        copy_if_missing "$file" "$SHARED_DIR/$relative"
        skill_name="${relative##*/}"
        skill_name="${skill_name%.md}"
        create_skill_adapter "$file" "$skill_name"
        ;;
      *)
        copy_if_missing "$file" "$SHARED_DIR/$relative"
        ;;
    esac
  fi
done < <(find "$SRC" -type f -print0)

# Codex-specific plugin assets use Codex's supported names while retaining the
# same MCP definitions and shared hook scripts.
if [[ -f "$SRC/mcp.json" ]]; then
  copy_if_missing "$SRC/mcp.json" "$CODEX_DIR/.mcp.json"
fi
copy_if_missing "$CODEX_ASSETS/hooks.json" "$CODEX_DIR/hooks/hooks.json"

# Print report
printf '\nStack: %s\n' "$STACK"
printf 'Providers: Claude Code + Codex-compatible shared tree\n\n'

if [[ ${#CREATED[@]} -gt 0 ]]; then
  echo "Created:"
  for file in "${CREATED[@]}"; do printf '  + %s\n' "$file"; done
fi

if [[ ${#MIGRATED[@]} -gt 0 ]]; then
  echo ""
  echo "Normalized instructions:"
  for file in "${MIGRATED[@]}"; do printf '  ↔ %s\n' "$file"; done
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo ""
  echo "Already existed (skipped):"
  for file in "${SKIPPED[@]}"; do printf '  ~ %s\n' "$file"; done
fi

if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
  echo ""
  echo "Instruction conflicts (manual resolution required):" >&2
  for conflict in "${CONFLICTS[@]}"; do printf '  ! %s\n' "$conflict" >&2; done
fi

echo ""
echo "Done."
