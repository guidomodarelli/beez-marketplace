#!/bin/bash
# render-instruction-template.sh
# Materializes the stack template's dynamic rule-reference section and validates
# provider-neutral references returned in AGENTS.md.

set -euo pipefail

readonly RULE_REFERENCE_PLACEHOLDER='{{AGENT_READY_RULE_REFERENCES}}'
readonly RULE_REFERENCE_START='<!-- BEGIN AGENT-READY RULE REFERENCES -->'
readonly RULE_REFERENCE_END='<!-- END AGENT-READY RULE REFERENCES -->'

TEMPLATE_FILE=""
RULES_DIRECTORY=""
VALIDATE_FILE=""

usage() {
  cat >&2 <<'EOF'
Usage:
  render-instruction-template.sh --template <file> --rules-dir <directory>
  render-instruction-template.sh --validate <file> --rules-dir <directory>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)
      [[ $# -ge 2 ]] || { echo "ERROR: --template requires a value" >&2; exit 1; }
      TEMPLATE_FILE="$2"
      shift 2
      ;;
    --rules-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --rules-dir requires a value" >&2; exit 1; }
      RULES_DIRECTORY="${2%/}"
      shift 2
      ;;
    --validate)
      [[ $# -ge 2 ]] || { echo "ERROR: --validate requires a value" >&2; exit 1; }
      VALIDATE_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$RULES_DIRECTORY" || ! -d "$RULES_DIRECTORY" ]]; then
  echo "ERROR: --rules-dir must point to an existing directory: $RULES_DIRECTORY" >&2
  exit 1
fi

if [[ -n "$TEMPLATE_FILE" && -n "$VALIDATE_FILE" ]]; then
  echo "ERROR: --template and --validate are mutually exclusive" >&2
  exit 1
fi

if [[ -z "$TEMPLATE_FILE" && -z "$VALIDATE_FILE" ]]; then
  echo "ERROR: provide --template or --validate" >&2
  usage
  exit 1
fi

if [[ -n "$TEMPLATE_FILE" && ! -f "$TEMPLATE_FILE" ]]; then
  echo "ERROR: --template must point to a regular file: $TEMPLATE_FILE" >&2
  exit 1
fi

if [[ -n "$VALIDATE_FILE" && (! -f "$VALIDATE_FILE" || -L "$VALIDATE_FILE") ]]; then
  echo "ERROR: --validate must point to a non-symlink regular file: $VALIDATE_FILE" >&2
  exit 1
fi

if [[ -L "$RULES_DIRECTORY" ]]; then
  echo "ERROR: --rules-dir must not be a symlink: $RULES_DIRECTORY" >&2
  exit 1
fi

first_symlink="$(find "$RULES_DIRECTORY" -type l -print -quit 2>/dev/null || true)"
if [[ -n "$first_symlink" ]]; then
  echo "ERROR: rule files must not be symlinks: $first_symlink" >&2
  exit 1
fi

list_rule_paths() {
  local rule_file
  local relative_path

  while IFS= read -r rule_file; do
    relative_path="${rule_file#"$RULES_DIRECTORY"/}"
    case "$relative_path" in
      ""|/*|../*|*/../*|*/..)
        echo "ERROR: unsafe rule path: $relative_path" >&2
        return 1
        ;;
    esac
    printf '%s\n' "$relative_path"
  done < <(find "$RULES_DIRECTORY" -type f -print | LC_ALL=C sort)
}

render_rule_references() {
  local relative_path

  printf '%s\n' "$RULE_REFERENCE_START"
  while IFS= read -r relative_path; do
    printf '%s\n' "- Read and follow \`.agents/rules/$relative_path\`."
  done < <(list_rule_paths)
  printf '%s\n' "$RULE_REFERENCE_END"
}

if [[ -n "$TEMPLATE_FILE" ]]; then
  placeholder_count="$(grep -Fxc "$RULE_REFERENCE_PLACEHOLDER" "$TEMPLATE_FILE" || true)"
  if [[ "$placeholder_count" -ne 1 ]]; then
    echo "ERROR: template must contain exactly one $RULE_REFERENCE_PLACEHOLDER placeholder" >&2
    exit 1
  fi

  temporary_block="$(mktemp "${TMPDIR:-/tmp}/agent-ready-rule-references.XXXXXX")"
  trap 'rm -f -- "$temporary_block"' EXIT
  render_rule_references > "$temporary_block"

  awk -v placeholder="$RULE_REFERENCE_PLACEHOLDER" -v block_file="$temporary_block" '
    BEGIN {
      rendered_block = ""
      while ((getline line < block_file) > 0) {
        rendered_block = rendered_block line ORS
      }
      close(block_file)
    }
    $0 == placeholder {
      printf "%s", rendered_block
      next
    }
    { print }
  ' "$TEMPLATE_FILE"
  exit 0
fi

start_count="$(grep -Fxc "$RULE_REFERENCE_START" "$VALIDATE_FILE" || true)"
end_count="$(grep -Fxc "$RULE_REFERENCE_END" "$VALIDATE_FILE" || true)"
if [[ "$start_count" -ne 1 || "$end_count" -ne 1 ]]; then
  echo "ERROR: AGENTS.md must contain exactly one managed rule-reference block" >&2
  exit 1
fi

if grep -Fq "$RULE_REFERENCE_PLACEHOLDER" "$VALIDATE_FILE"; then
  echo "ERROR: AGENTS.md contains an unrendered rule-reference placeholder" >&2
  exit 1
fi

if grep -Eq '@[^[:space:]]*rules/|@path/to/folder' "$VALIDATE_FILE"; then
  echo "ERROR: AGENTS.md contains Claude-only or placeholder @ references" >&2
  exit 1
fi

rule_path_is_current() {
  local candidate_path="$1"
  local relative_path

  while IFS= read -r relative_path; do
    [[ ".agents/rules/$relative_path" == "$candidate_path" ]] && return 0
  done < <(list_rule_paths)
  return 1
}

missing_references=0
while IFS= read -r relative_path; do
  reference_path=".agents/rules/$relative_path"
  if ! grep -Fq "$reference_path" "$VALIDATE_FILE"; then
    echo "ERROR: AGENTS.md is missing rule reference: $reference_path" >&2
    missing_references=1
  fi
done < <(list_rule_paths)

stale_references=0
while IFS= read -r reference_path; do
  [[ "$reference_path" == *. ]] && reference_path="${reference_path%.}"
  if ! rule_path_is_current "$reference_path"; then
    echo "ERROR: AGENTS.md contains stale rule reference: $reference_path" >&2
    stale_references=1
  fi
done < <(grep -Eo '\.agents/rules/[[:alnum:]_.\/-]+' "$VALIDATE_FILE" | LC_ALL=C sort -u || true)

if [[ "$missing_references" -ne 0 || "$stale_references" -ne 0 ]]; then
  exit 1
fi
