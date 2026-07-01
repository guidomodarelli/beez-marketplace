#!/bin/bash
# bootstrap.sh
# Copies the Agent Ready stack templates into .claude/, skipping files that already exist.
# Never overwrites — only complements.
#
# Usage:
#   bash bootstrap.sh --stack <frontend|node|java|go> --skill-dir <path>

set -e

STACK=""
SKILL_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)     STACK="$2"; shift 2 ;;
    --skill-dir) SKILL_DIR="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$STACK" || -z "$SKILL_DIR" ]]; then
  echo "ERROR: --stack and --skill-dir are required"
  exit 1
fi

SRC="$SKILL_DIR/assets/stacks/$STACK"

if [[ ! -d "$SRC" ]]; then
  echo "ERROR: No template found for stack '$STACK' at $SRC"
  exit 1
fi

CLAUDE_DIR=".claude"
CREATED=()
SKIPPED=()

# Copy a file only if the destination does not already exist
copy_if_missing() {
  local src="$1"
  local dst="$2"

  mkdir -p "$(dirname "$dst")"

  if [[ -f "$dst" ]]; then
    SKIPPED+=("$dst")
  else
    cp "$src" "$dst"
    CREATED+=("$dst")
  fi
}

# Walk every file in the stack template and mirror it under .claude/
# (preserving subdirectory structure)
while IFS= read -r -d '' file; do
  relative="${file#$SRC/}"

  # CLAUDE.md lives at .claude/CLAUDE.md
  if [[ "$relative" == "CLAUDE.md" ]]; then
    copy_if_missing "$file" "$CLAUDE_DIR/CLAUDE.md"
  # settings.json and mcp.json live at .claude/ root
  elif [[ "$relative" == "settings.json" || "$relative" == "mcp.json" ]]; then
    copy_if_missing "$file" "$CLAUDE_DIR/$relative"
  # Everything else (rules/, commands/, agents/, skills/, hooks/) keeps its path
  else
    copy_if_missing "$file" "$CLAUDE_DIR/$relative"
  fi
done < <(find "$SRC" -type f -print0)

# Print report
echo ""
echo "Stack: $STACK"
echo ""

if [[ ${#CREATED[@]} -gt 0 ]]; then
  echo "Created:"
  for f in "${CREATED[@]}"; do echo "  + $f"; done
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo ""
  echo "Already existed (skipped):"
  for f in "${SKIPPED[@]}"; do echo "  ~ $f"; done
fi

echo ""
echo "Done."
