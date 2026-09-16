#!/bin/bash
# sync-marketplace.sh
# Upgrades groot-marketplace and projects managed Agent Ready assets locally.
# Runs automatically on session start (SessionStart hook).

set -euo pipefail

readonly MARKETPLACE_NAME="groot-marketplace"
readonly SKILL_NAME="agent-ready-setup"
readonly AGENTS_DIRECTORY=".agents"
readonly CLAUDE_DIRECTORY=".claude"
readonly CODEX_DIRECTORY=".codex"
readonly GROOT_UI_HELPER_SCRIPT="scripts/setup-groot-ui.sh"
readonly SYNC_LOCK_DIRECTORY="$AGENTS_DIRECTORY/.agent-ready-assets.lock"
readonly SYNC_LOCK_OWNER_FILE="$SYNC_LOCK_DIRECTORY/owner"
readonly SYNC_LOCK_STALE_AFTER_MINUTES=10

provider=""
stack_override="${AGENT_READY_SETUP_STACK:-}"
marketplace_already_upgraded="${AGENT_READY_SETUP_MARKETPLACE_UPGRADED:-0}"
sync_lock_inherited="${AGENT_READY_SETUP_SYNC_LOCK_HELD:-0}"
backup_directory="${AGENT_READY_SETUP_BACKUP_DIRECTORY:-}"
created_assets=()
updated_assets=()
skipped_assets=()
backups=()
conflicts=()
original_arguments=("$@")

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
    --stack)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        printf 'ERROR: --stack requires frontend, node, java, or go\n' >&2
        exit 1
      fi
      stack_override="$2"
      shift 2
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

if [[ "$marketplace_already_upgraded" != 0 && "$marketplace_already_upgraded" != 1 ]]; then
  printf 'ERROR: AGENT_READY_SETUP_MARKETPLACE_UPGRADED must be 0 or 1\n' >&2
  exit 1
fi

if [[ "$sync_lock_inherited" != 0 && "$sync_lock_inherited" != 1 ]]; then
  printf 'ERROR: AGENT_READY_SETUP_SYNC_LOCK_HELD must be 0 or 1\n' >&2
  exit 1
fi

is_valid_skill_dir() {
  local candidate="$1"

  [[ -f "$candidate/SKILL.md" && \
    -d "$candidate/assets/stacks" && \
    -f "$candidate/assets/common/hooks/sync-marketplace.sh" && \
    -f "$candidate/assets/common/settings.json" && \
    -f "$candidate/assets/codex/hooks.json" ]]
}

if [[ "$marketplace_already_upgraded" -eq 0 ]]; then
  echo "[marketplace-sync] Upgrading $MARKETPLACE_NAME for $provider..."
  fury ai assets marketplace upgrade \
    --name "$MARKETPLACE_NAME" \
    --provider "$provider"
  echo "[marketplace-sync] Marketplace upgrade completed."
else
  echo "[marketplace-sync] Marketplace upgrade already completed by caller."
fi

resolve_skill_dir() {
  local candidate
  local provider_root
  local cache_root
  local hook_directory
  local project_root

  if [[ -n "${AGENT_READY_SETUP_SKILL_DIR:-}" ]]; then
    candidate="$AGENT_READY_SETUP_SKILL_DIR"
    if is_valid_skill_dir "$candidate"; then
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
      if is_valid_skill_dir "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi

  hook_directory="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  for candidate in \
    "$hook_directory/../../../.." \
    "$hook_directory/../../.."; do
    if is_valid_skill_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if [[ "$provider" == "claude" ]]; then
    provider_root="$HOME/.claude"
  else
    provider_root="$HOME/.codex"
  fi

  candidate="$provider_root/skills/$SKILL_NAME"
  if is_valid_skill_dir "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  cache_root="$provider_root/plugins/cache/$MARKETPLACE_NAME/groot-kit"
  while IFS= read -r candidate; do
    candidate="${candidate%/SKILL.md}"
    if is_valid_skill_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$cache_root" -type f -path "*/skills/$SKILL_NAME/SKILL.md" -print 2>/dev/null | sort -r)

  if project_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    candidate="$project_root/plugins/groot-kit/skills/$SKILL_NAME"
    if is_valid_skill_dir "$candidate"; then
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

stack="$(detect_stack || true)"
if [[ -z "$stack" ]]; then
  printf 'WARNING: could not detect project stack; local projection skipped.\n' >&2
  printf 'Rerun with --stack frontend|node|java|go.\n' >&2
  exit 0
fi

report_groot_ui_version() {
  [[ "$stack" == "frontend" ]] || return 0

  if [[ -x "$skill_dir/$GROOT_UI_HELPER_SCRIPT" ]]; then
    bash "$skill_dir/$GROOT_UI_HELPER_SCRIPT" "package.json"
  else
    printf 'WARNING: %s is unavailable; groot-ui version lookup skipped.\n' "$skill_dir/$GROOT_UI_HELPER_SCRIPT" >&2
  fi
}

record_created() {
  created_assets+=("$1")
}

record_updated() {
  updated_assets+=("$1")
}

record_skipped() {
  skipped_assets+=("$1")
}

validate_destination_parent() {
  local destination="$1"
  local parent_directory
  local current_path="."
  local path_component
  local relative_parent
  local -a path_components

  parent_directory="$(dirname -- "$destination")"
  [[ "$parent_directory" == "." ]] && return 0

  relative_parent="${parent_directory#./}"
  IFS='/' read -r -a path_components <<< "$relative_parent"
  for path_component in "${path_components[@]}"; do
    [[ -z "$path_component" || "$path_component" == "." ]] && continue
    current_path="$current_path/$path_component"

    if [[ -L "$current_path" ]]; then
      conflicts+=("$destination parent directory contains symlink $current_path; neither was changed")
      return 1
    fi
    if [[ -e "$current_path" && ! -d "$current_path" ]]; then
      conflicts+=("$destination parent directory is not a directory: $current_path; neither was changed")
      return 1
    fi
  done
}

show_sync_diff() {
  local source="$1"
  local destination="$2"

  printf 'Diff for %s (source: %s):\n' "$destination" "$source"
  if [[ -f "$destination" ]]; then
    diff -u -- "$destination" "$source" || true
  else
    diff -u -- /dev/null "$source" || true
  fi
}

ensure_backup_directory() {
  if [[ -n "$backup_directory" ]]; then
    [[ -d "$backup_directory" && ! -L "$backup_directory" ]]
    return
  fi

  backup_directory="$(mktemp -d "${TMPDIR:-/tmp}/agent-ready-backups.XXXXXX")" || return 1
}

backup_file() {
  local destination="$1"
  local relative_destination
  local backup_destination

  if ! ensure_backup_directory; then
    return 1
  fi
  relative_destination="${destination#./}"
  backup_destination="$backup_directory/$relative_destination"
  if ! mkdir -p -- "$(dirname -- "$backup_destination")"; then
    return 1
  fi
  if ! backup_destination="$(mktemp "${backup_destination}.agent-ready-backup.XXXXXX")"; then
    return 1
  fi
  if ! cp -p -- "$destination" "$backup_destination"; then
    rm -f -- "$backup_destination"
    return 1
  fi
  backups+=("$backup_destination")
}

sync_file() {
  local source="$1"
  local destination="$2"
  local expected_destination
  local temporary_destination

  if [[ ! -f "$source" ]]; then
    conflicts+=("$source is not a regular file; $destination was not changed")
    return 0
  fi
  if ! validate_destination_parent "$destination"; then
    return 0
  fi
  mkdir -p -- "$(dirname -- "$destination")"

  if [[ -L "$destination" ]]; then
    conflicts+=("$destination is a symlink; neither it nor its target was changed")
    return 0
  fi
  if [[ -e "$destination" && ! -f "$destination" ]]; then
    conflicts+=("$destination is not a regular file; neither was changed")
    return 0
  fi
  if [[ ! -e "$destination" ]]; then
    if ! temporary_destination="$(mktemp "${destination}.agent-ready-sync.XXXXXX")"; then
      conflicts+=("could not stage new content for $destination; neither was changed")
      return 0
    fi
    if ! cp -p -- "$source" "$temporary_destination"; then
      rm -f -- "$temporary_destination"
      conflicts+=("could not stage new content for $destination; neither was changed")
      return 0
    fi
    if ! mv -f -- "$temporary_destination" "$destination"; then
      rm -f -- "$temporary_destination"
      conflicts+=("could not create $destination atomically; neither was changed")
      return 0
    fi
    record_created "$destination"
    return 0
  fi
  if cmp -s "$destination" "$source"; then
    record_skipped "$destination"
    return 0
  fi

  expected_destination="$(mktemp "${destination}.agent-ready-expected.XXXXXX")"
  if ! cp -p -- "$destination" "$expected_destination"; then
    rm -f -- "$expected_destination"
    conflicts+=("could not snapshot $destination; neither was changed")
    return 0
  fi

  show_sync_diff "$source" "$destination"
  if ! backup_file "$destination"; then
    rm -f -- "$expected_destination"
    conflicts+=("could not back up $destination; neither was changed")
    return 0
  fi

  temporary_destination="$(mktemp "${destination}.agent-ready-sync.XXXXXX")"
  if ! cp -p -- "$source" "$temporary_destination"; then
    rm -f -- "$temporary_destination" "$expected_destination"
    conflicts+=("could not stage updated content for $destination; neither was changed")
    return 0
  fi
  if [[ -L "$destination" || ! -f "$destination" ]] || \
     ! cmp -s "$destination" "$expected_destination"; then
    rm -f -- "$temporary_destination" "$expected_destination"
    conflicts+=("$destination changed during synchronization; neither was changed")
    return 0
  fi
  if ! mv -f -- "$temporary_destination" "$destination"; then
    rm -f -- "$temporary_destination" "$expected_destination"
    conflicts+=("could not replace $destination atomically; neither was changed")
    return 0
  fi

  rm -f -- "$expected_destination"
  record_updated "$destination"
}

relative_shared_target() {
  local relative="$1"
  local destination_directory
  local slash_count
  local parent_levels=1
  local level
  local prefix=""

  if [[ "$relative" == */* ]]; then
    destination_directory="${relative%/*}"
    slash_count="${destination_directory//[^\/]/}"
    parent_levels=$(( ${#slash_count} + 2 ))
  fi

  for ((level = 0; level < parent_levels; level++)); do
    prefix+="../"
  done

  printf '%s%s/%s\n' "$prefix" "$AGENTS_DIRECTORY" "$relative"
}

link_claude_asset() {
  local relative="$1"
  local source="$AGENTS_DIRECTORY/$relative"
  local destination="$CLAUDE_DIRECTORY/$relative"
  local target
  local temporary_link

  case "$relative" in
    ""|/*|../*|*/../*|*/..)
      conflicts+=("invalid shared asset path: $relative; no Claude view was created")
      return 0
      ;;
  esac

  if [[ ! -e "$source" && ! -L "$source" ]]; then
    conflicts+=("canonical shared asset is missing: $source; no Claude view was created")
    return 0
  fi
  if ! validate_destination_parent "$destination"; then
    return 0
  fi
  mkdir -p -- "$(dirname -- "$destination")"
  target="$(relative_shared_target "$relative")"

  if [[ -L "$destination" ]]; then
    if [[ "$(readlink -- "$destination")" == "$target" ]]; then
      record_skipped "$destination"
    else
      conflicts+=("$destination is a custom symlink; preserved")
    fi
    return 0
  fi
  if [[ -e "$destination" ]]; then
    if [[ ! -f "$destination" || ! -f "$source" ]] || ! cmp -s "$destination" "$source"; then
      conflicts+=("$destination differs from canonical shared asset $source; neither was overwritten")
      return 0
    fi

    temporary_link="${destination}.agent-ready-link.$$"
    if [[ -e "$temporary_link" || -L "$temporary_link" ]]; then
      conflicts+=("temporary normalization path already exists for $destination; neither was changed")
      return 0
    fi
    if ! ln -s -- "$target" "$temporary_link"; then
      rm -f -- "$temporary_link"
      conflicts+=("could not stage Claude view $destination; neither was changed")
      return 0
    fi
    if [[ -L "$destination" || ! -f "$destination" ]] || ! cmp -s "$destination" "$source"; then
      rm -f -- "$temporary_link"
      conflicts+=("$destination changed before normalization; neither was changed")
      return 0
    fi
    if ! mv -f -- "$temporary_link" "$destination"; then
      rm -f -- "$temporary_link"
      conflicts+=("could not normalize Claude view $destination; neither was changed")
      return 0
    fi
    record_updated "$destination -> $source"
    return 0
  fi

  temporary_link="${destination}.agent-ready-link.$$"
  if [[ -e "$temporary_link" || -L "$temporary_link" ]]; then
    conflicts+=("temporary normalization path already exists for $destination; neither was changed")
    return 0
  fi
  if ! ln -s -- "$target" "$temporary_link" || ! mv -- "$temporary_link" "$destination"; then
    rm -f -- "$temporary_link"
    conflicts+=("could not create Claude view $destination; neither was changed")
    return 0
  fi
  record_created "$destination"
}

create_skill_adapter() {
  local source="$1"
  local skill_name="$2"
  local destination="$AGENTS_DIRECTORY/skills/$skill_name/SKILL.md"
  local temporary_adapter

  if ! temporary_adapter="$(mktemp "${TMPDIR:-/tmp}/agent-ready-adapter.XXXXXX")"; then
    conflicts+=("could not stage skill adapter for $source; neither was changed")
    return 0
  fi
  if ! {
    printf '%s\n' '---'
    printf 'name: %s\n' "$skill_name"
    printf 'description: Provider-neutral reusable workflow for %s.\n' "$skill_name"
    printf '%s\n\n' '---'
    awk '
      NR == 1 && $0 == "---" { in_frontmatter = 1; next }
      in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
      !in_frontmatter { print }
    ' "$source"
  } > "$temporary_adapter"; then
    rm -f -- "$temporary_adapter"
    conflicts+=("could not render skill adapter for $source; neither was changed")
    return 0
  fi
  chmod 0644 "$temporary_adapter"

  sync_file "$temporary_adapter" "$destination" "$source"
  rm -f -- "$temporary_adapter"
  link_claude_asset "skills/$skill_name/SKILL.md"
}

project_stack_assets() {
  local source_root="$skill_dir/assets/stacks/$stack"
  local source_asset
  local relative_asset
  local skill_name

  [[ -d "$source_root" ]] || return 0

  while IFS= read -r -d '' source_asset; do
    relative_asset="${source_asset#"$source_root/"}"
    case "$relative_asset" in
      CLAUDE.md|hooks/*)
        continue
        ;;
      mcp.json)
        sync_file "$source_asset" "$AGENTS_DIRECTORY/$relative_asset"
        link_claude_asset "$relative_asset"
        sync_file "$source_asset" "$CODEX_DIRECTORY/.mcp.json"
        ;;
      skills/*/SKILL.md)
        skill_name="${relative_asset#skills/}"
        skill_name="${skill_name%/SKILL.md}"
        create_skill_adapter "$source_asset" "$skill_name"
        ;;
      skills/*/*.md)
        sync_file "$source_asset" "$AGENTS_DIRECTORY/$relative_asset"
        link_claude_asset "$relative_asset"
        ;;
      agents/*.md|commands/*.md|skills/*.md)
        sync_file "$source_asset" "$AGENTS_DIRECTORY/$relative_asset"
        link_claude_asset "$relative_asset"
        skill_name="${relative_asset##*/}"
        skill_name="${skill_name%.md}"
        create_skill_adapter "$source_asset" "$skill_name"
        ;;
      *)
        sync_file "$source_asset" "$AGENTS_DIRECTORY/$relative_asset"
        link_claude_asset "$relative_asset"
        ;;
    esac
  done < <(find "$source_root" -type f -print0)
}

sync_claude_settings() {
  local template="$1"
  local destination="$CLAUDE_DIRECTORY/settings.json"
  local temporary_settings
  local merge_status=0

  if [[ -L "$destination" ]]; then
    conflicts+=("$destination is a symlink; preserved")
    return 0
  fi
  if [[ -e "$destination" && ! -f "$destination" ]]; then
    conflicts+=("$destination is not a regular file; preserved")
    return 0
  fi
  if [[ ! -f "$destination" ]]; then
    sync_file "$template" "$destination"
    return 0
  fi

  temporary_settings="$(mktemp "${TMPDIR:-/tmp}/agent-ready-settings.XXXXXX")"
  python3 - "$template" "$destination" > "$temporary_settings" <<'PY' || merge_status=$?
import json
import re
import sys


def canonical_managed_sync_command(value):
    managed_command_pattern = re.compile(
        r"^(?:Bash\((?:\.claude/hooks|\.agents/hooks)/sync-marketplace\.sh "
        r"--provider claude(?: --(?:sync|update|sync-instructions|merge-instructions))?"
        r"(?: --yes)?\)|bash (?:\.claude/hooks|\.agents/hooks)/sync-marketplace\.sh "
        r"--provider claude(?: --(?:sync|update|sync-instructions|merge-instructions))?"
        r"(?: --yes)?)$"
    )
    if managed_command_pattern.match(value):
        if value.startswith("Bash("):
            return "Bash(.agents/hooks/sync-marketplace.sh --provider claude)"
        return "bash .agents/hooks/sync-marketplace.sh --provider claude"
    return None


template_path, settings_path = sys.argv[1:3]
try:
    with open(template_path, encoding="utf-8") as template_file:
        template = json.load(template_file)
    with open(settings_path, encoding="utf-8") as settings_file:
        settings = json.load(settings_file)
except (OSError, json.JSONDecodeError):
    sys.exit(1)


def migrate(value):
    if isinstance(value, dict):
        return {key: migrate(item) for key, item in value.items()}
    if isinstance(value, list):
        return [migrate(item) for item in value]
    if not isinstance(value, str):
        return value

    canonical_value = canonical_managed_sync_command(value)
    if canonical_value is not None:
        return canonical_value

    if value.startswith("Bash(.claude/hooks/") or value.startswith(
        "bash .claude/hooks/"
    ):
        return value.replace(".claude/hooks/", ".agents/hooks/", 1)

    return value


def has_custom_keys(current, expected):
    if isinstance(current, dict) and isinstance(expected, dict):
        return any(
            key not in expected or has_custom_keys(value, expected[key])
            for key, value in current.items()
        )
    if isinstance(current, list) and isinstance(expected, list):
        return any(entry not in expected for entry in current)
    return False


def matches_managed_template(current, expected):
    if isinstance(current, dict) and isinstance(expected, dict):
        return all(
            key in current and matches_managed_template(current[key], value)
            for key, value in expected.items()
        )
    if isinstance(current, list) and isinstance(expected, list):
        current_index = 0
        for expected_entry in expected:
            matching_index = next(
                (
                    index
                    for index in range(current_index, len(current))
                    if matches_managed_template(current[index], expected_entry)
                ),
                None,
            )
            if matching_index is None:
                return False
            current_index = matching_index + 1
        return True
    return current == expected


def merge_managed_template(current, expected):
    if isinstance(current, dict) and isinstance(expected, dict):
        merged = dict(current)
        for key, value in expected.items():
            if key in current:
                merged[key] = merge_managed_template(current[key], value)
            else:
                merged[key] = value
        return merged
    if isinstance(current, list) and isinstance(expected, list):
        remaining_current = list(current)
        merged = []
        for expected_entry in expected:
            matching_index = next(
                (
                    index
                    for index, current_entry in enumerate(remaining_current)
                    if matches_managed_template(current_entry, expected_entry)
                ),
                None,
            )
            if matching_index is None:
                merged.append(expected_entry)
                continue
            merged.extend(remaining_current[:matching_index])
            merged.append(
                merge_managed_template(
                    remaining_current[matching_index], expected_entry
                )
            )
            remaining_current = remaining_current[matching_index + 1 :]
        return merged + remaining_current
    return expected

migrated_settings = migrate(settings)
if not has_custom_keys(migrated_settings, template):
    sys.exit(10)

json.dump(merge_managed_template(migrated_settings, template), sys.stdout, indent=2)
sys.stdout.write("\n")
PY

  case "$merge_status" in
    0)
      sync_file "$temporary_settings" "$destination"
      ;;
    10)
      cp -- "$template" "$temporary_settings"
      sync_file "$temporary_settings" "$destination"
      ;;
    *)
      conflicts+=("$destination contains invalid JSON; preserved")
      ;;
  esac
  rm -f -- "$temporary_settings"
}

sync_lock_acquired=0

get_process_start_time() {
  local process_id="$1"

  ps -p "$process_id" -o lstart= 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

write_sync_lock_owner() {
  local owner_metadata_temp

  if ! owner_metadata_temp="$(mktemp "${SYNC_LOCK_DIRECTORY}/owner.XXXXXX")"; then
    return 1
  fi
  if ! printf '%s\n%s\n' "$$" "$(get_process_start_time "$$")" > "$owner_metadata_temp"; then
    rm -f -- "$owner_metadata_temp"
    return 1
  fi
  if ! mv -f -- "$owner_metadata_temp" "$SYNC_LOCK_OWNER_FILE"; then
    rm -f -- "$owner_metadata_temp"
    return 1
  fi
}

is_legacy_sync_lock_stale() {
  [[ -d "$SYNC_LOCK_DIRECTORY" && ! -L "$SYNC_LOCK_DIRECTORY" ]] || return 1
  find "$SYNC_LOCK_DIRECTORY" -prune -type d \
    -mmin "+$SYNC_LOCK_STALE_AFTER_MINUTES" -print -quit 2>/dev/null | grep -q .
}

is_sync_lock_stale() {
  local owner_pid
  local owner_start_time=""
  local current_start_time

  [[ -d "$SYNC_LOCK_DIRECTORY" && ! -L "$SYNC_LOCK_DIRECTORY" ]] || return 1

  if [[ -f "$SYNC_LOCK_OWNER_FILE" && ! -L "$SYNC_LOCK_OWNER_FILE" ]]; then
    IFS= read -r owner_pid < "$SYNC_LOCK_OWNER_FILE" || owner_pid=""
    if [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]]; then
      if ! kill -0 "$owner_pid" 2>/dev/null; then
        return 0
      fi

      IFS= read -r owner_start_time < <(sed -n '2p' "$SYNC_LOCK_OWNER_FILE") || true
      if [[ -n "$owner_start_time" ]]; then
        current_start_time="$(get_process_start_time "$owner_pid")"
        [[ -n "$current_start_time" && "$current_start_time" != "$owner_start_time" ]] && return 0
      fi

      return 1
    fi
  fi

  is_legacy_sync_lock_stale
}

reclaim_stale_sync_lock() {
  is_sync_lock_stale || return 1

  rm -f -- "$SYNC_LOCK_OWNER_FILE"
  rmdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null
}

has_current_sync_lock_owner() {
  local owner_pid
  local owner_start_time=""
  local current_start_time

  [[ -f "$SYNC_LOCK_OWNER_FILE" && ! -L "$SYNC_LOCK_OWNER_FILE" ]] || return 1
  IFS= read -r owner_pid < "$SYNC_LOCK_OWNER_FILE" || return 1
  [[ "$owner_pid" == "$$" ]] || return 1

  IFS= read -r owner_start_time < <(sed -n '2p' "$SYNC_LOCK_OWNER_FILE") || true
  [[ -n "$owner_start_time" ]] || return 1
  current_start_time="$(get_process_start_time "$$")"
  [[ -n "$current_start_time" && "$current_start_time" == "$owner_start_time" ]]
}

release_sync_lock() {
  if [[ "$sync_lock_acquired" -eq 1 ]]; then
    rm -f -- "$SYNC_LOCK_OWNER_FILE"
    rmdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null || true
  fi
}

acquire_sync_lock() {
  if [[ "$sync_lock_inherited" -eq 1 ]] && has_current_sync_lock_owner; then
    sync_lock_acquired=1
    trap release_sync_lock EXIT
    return 0
  fi

  if mkdir -p -- "$AGENTS_DIRECTORY" && mkdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null; then
    sync_lock_acquired=1
    trap release_sync_lock EXIT
    write_sync_lock_owner
    return $?
  fi

  if reclaim_stale_sync_lock && mkdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null; then
    sync_lock_acquired=1
    trap release_sync_lock EXIT
    write_sync_lock_owner
    return $?
  fi

  printf 'WARNING: another asset synchronization is running or left an active/ambiguous lock; no asset was changed\n' >&2
  return 1
}

if [[ -L "$AGENTS_DIRECTORY" || ( -e "$AGENTS_DIRECTORY" && ! -d "$AGENTS_DIRECTORY" ) ]]; then
  echo "WARNING: .agents is a symlink or non-directory; no asset was changed" >&2
  exit 0
fi
if ! acquire_sync_lock; then
  exit 0
fi

sync_hook_source="$skill_dir/assets/common/hooks/sync-marketplace.sh"
sync_hook_destination="$AGENTS_DIRECTORY/hooks/sync-marketplace.sh"
sync_hook_destination_was_different=1
current_hook_needs_restart=0

if [[ -f "$sync_hook_destination" && ! -L "$sync_hook_destination" ]] && \
  cmp -s "$sync_hook_destination" "$sync_hook_source"; then
  sync_hook_destination_was_different=0
fi
if [[ -f "${BASH_SOURCE[0]}" ]] && ! cmp -s "${BASH_SOURCE[0]}" "$sync_hook_source"; then
  current_hook_needs_restart=1
fi

sync_file "$sync_hook_source" "$sync_hook_destination"

if [[ "$sync_hook_destination_was_different" -eq 1 || "$current_hook_needs_restart" -eq 1 ]] && \
  [[ -f "$sync_hook_destination" && ! -L "$sync_hook_destination" ]] && \
  cmp -s "$sync_hook_destination" "$sync_hook_source"; then
  echo "[marketplace-sync] Sync hook updated; restarting with latest version."
  export AGENT_READY_SETUP_MARKETPLACE_UPGRADED=1
  export AGENT_READY_SETUP_SYNC_LOCK_HELD=1
  if [[ -n "$backup_directory" ]]; then
    export AGENT_READY_SETUP_BACKUP_DIRECTORY="$backup_directory"
  fi
  exec bash "$sync_hook_destination" "${original_arguments[@]}"
fi

report_groot_ui_version

stack_hooks_directory="$skill_dir/assets/stacks/$stack/hooks"
if [[ -d "$stack_hooks_directory" ]]; then
  while IFS= read -r -d '' source_hook; do
    relative_hook="${source_hook#"$stack_hooks_directory/"}"
    [[ "$relative_hook" == "sync-marketplace.sh" ]] && continue
    sync_file "$source_hook" "$AGENTS_DIRECTORY/hooks/$relative_hook"
  done < <(find "$stack_hooks_directory" -type f -print0)
fi

# Project all non-hook stack assets before merging instruction references. The
# shared tree remains canonical, while Claude and Codex receive provider views.
project_stack_assets

sync_claude_settings "$skill_dir/assets/common/settings.json"
sync_file "$skill_dir/assets/codex/hooks.json" "$CODEX_DIRECTORY/hooks/hooks.json"

echo "[marketplace-sync] Local managed asset projection completed for $stack."

if [[ ${#created_assets[@]} -gt 0 ]]; then
  echo "Created:"
  printf '  + %s\n' "${created_assets[@]}"
fi
if [[ ${#updated_assets[@]} -gt 0 ]]; then
  echo "Updated from templates:"
  printf '  ↻ %s\n' "${updated_assets[@]}"
fi
if [[ ${#backups[@]} -gt 0 ]]; then
  echo "Local backups directory: $backup_directory"
  printf '  ↩ %s\n' "${backups[@]}"
fi
if [[ ${#conflicts[@]} -gt 0 ]]; then
  echo "Managed asset conflicts (preserved):" >&2
  printf '  ! %s\n' "${conflicts[@]}" >&2
fi

if [[ ! -f "$skill_dir/scripts/merge-instructions.sh" ]]; then
  echo "WARNING: merge-instructions.sh is unavailable; managed assets were synchronized without instruction merge." >&2
else
  merge_environment=(AGENT_READY_SETUP_NON_INTERACTIVE=1)
  if [[ -n "$backup_directory" ]]; then
    merge_environment+=(AGENT_READY_SETUP_BACKUP_DIRECTORY="$backup_directory")
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
