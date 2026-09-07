#!/bin/bash
# bootstrap.sh
# Projects Agent Ready templates into Claude, shared-agent, and Codex trees.
# Existing assets are never overwritten. Root instructions are normalized so
# AGENTS.md is canonical and CLAUDE.md is a proxy with root-only guidance.
#
# Usage:
#   bash bootstrap.sh --stack <frontend|node|java|go> --skill-dir <path> [--provider <claude|codex>] [--sync] [--yes]

set -euo pipefail

readonly MARKETPLACE_NAME="groot-marketplace"
readonly SKILL_NAME="agent-ready-setup"

STACK=""
REQUESTED_SKILL_DIR=""
SKILL_DIR=""
PROVIDER="${AGENT_READY_SETUP_ACTIVE_PROVIDER:-}"
MARKETPLACE_ALREADY_UPGRADED="${AGENT_READY_SETUP_MARKETPLACE_UPGRADED:-0}"
SYNC_MODE=0
AUTO_CONFIRM=0
readonly SYNC_LOCK_DIRECTORY=".agents/.agent-ready-assets.lock"
readonly SYNC_LOCK_OWNER_FILE="$SYNC_LOCK_DIRECTORY/owner"
readonly SYNC_LOCK_STALE_AFTER_MINUTES=10
SYNC_LOCK_ACQUIRED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      [[ $# -ge 2 ]] || { echo "ERROR: --stack requires a value" >&2; exit 1; }
      STACK="$2"
      shift 2
      ;;
    --skill-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --skill-dir requires a value" >&2; exit 1; }
      REQUESTED_SKILL_DIR="$2"
      shift 2
      ;;
    --provider)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --provider requires claude or codex" >&2; exit 1; }
      PROVIDER="$2"
      shift 2
      ;;
    --sync|--update)
      SYNC_MODE=1
      shift
      ;;
    --yes)
      AUTO_CONFIRM=1
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$AUTO_CONFIRM" -eq 1 && "$SYNC_MODE" -ne 1 ]]; then
  echo "ERROR: --yes requires --sync or --update" >&2
  exit 1
fi

case "$MARKETPLACE_ALREADY_UPGRADED" in
  0|1) ;;
  *)
    echo "ERROR: AGENT_READY_SETUP_MARKETPLACE_UPGRADED must be 0 or 1" >&2
    exit 1
    ;;
esac

if [[ -z "$STACK" || -z "$REQUESTED_SKILL_DIR" ]]; then
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

is_valid_skill_dir() {
  local candidate="$1"

  [[ -f "$candidate/SKILL.md" && \
    -f "$candidate/scripts/bootstrap.sh" && \
    -d "$candidate/assets/stacks" ]]
}

if [[ ! -d "$REQUESTED_SKILL_DIR" ]]; then
  echo "ERROR: --skill-dir must point to an existing directory: $REQUESTED_SKILL_DIR" >&2
  exit 1
fi

SKILL_DIR="$REQUESTED_SKILL_DIR"
if [[ -z "$PROVIDER" ]]; then
  provider_resolver="$SKILL_DIR/scripts/resolve-provider.sh"
  if [[ ! -f "$provider_resolver" ]]; then
    echo "ERROR: provider is not explicit and resolver is missing: $provider_resolver" >&2
    exit 1
  fi
  PROVIDER="$(bash "$provider_resolver" --skill-dir "$SKILL_DIR")"
fi

case "$PROVIDER" in
  claude|codex) ;;
  *)
    echo "ERROR: Unsupported provider '$PROVIDER'. Expected claude or codex." >&2
    exit 1
    ;;
esac

resolve_skill_dir() {
  local candidate
  local provider_root
  local cache_root
  local project_root

  if [[ -n "${AGENT_READY_SETUP_SKILL_DIR:-}" ]]; then
    candidate="$AGENT_READY_SETUP_SKILL_DIR"
    if is_valid_skill_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    printf 'ERROR: AGENT_READY_SETUP_SKILL_DIR is not a valid %s source: %s\n' \
      "$SKILL_NAME" "$candidate" >&2
    return 1
  fi

  if [[ "$MARKETPLACE_ALREADY_UPGRADED" -eq 1 ]]; then
    if is_valid_skill_dir "$REQUESTED_SKILL_DIR"; then
      printf '%s\n' "$REQUESTED_SKILL_DIR"
      return 0
    fi
    return 1
  fi

  if [[ "$REQUESTED_SKILL_DIR" == "$HOME/.codex/plugins/cache/$MARKETPLACE_NAME"/* ]]; then
    provider_root="$HOME/.codex"
  elif [[ "$REQUESTED_SKILL_DIR" == "$HOME/.claude/plugins/cache/$MARKETPLACE_NAME"/* ]]; then
    provider_root="$HOME/.claude"
  elif [[ "$PROVIDER" == "claude" ]]; then
    provider_root="$HOME/.claude"
  else
    provider_root="$HOME/.codex"
  fi
  cache_root="$provider_root/plugins/cache/$MARKETPLACE_NAME"

  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    for candidate in \
      "$CLAUDE_PLUGIN_ROOT/skills/$SKILL_NAME" \
      "$CLAUDE_PLUGIN_ROOT"; do
      if [[ "$candidate" != "$REQUESTED_SKILL_DIR" ]] && is_valid_skill_dir "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi

  if [[ "$REQUESTED_SKILL_DIR" != "$cache_root"/* ]] && \
    is_valid_skill_dir "$REQUESTED_SKILL_DIR"; then
    printf '%s\n' "$REQUESTED_SKILL_DIR"
    return 0
  fi

  candidate="$provider_root/skills/$SKILL_NAME"
  if [[ "$candidate" != "$REQUESTED_SKILL_DIR" ]] && is_valid_skill_dir "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  while IFS= read -r candidate; do
    candidate="${candidate%/SKILL.md}"
    if [[ "$candidate" != "$REQUESTED_SKILL_DIR" ]] && is_valid_skill_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$cache_root" -type f -path "*/skills/$SKILL_NAME/SKILL.md" -print 2>/dev/null | sort -r)

  if project_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    candidate="$project_root/plugins/groot-kit/skills/$SKILL_NAME"
    if [[ "$candidate" != "$REQUESTED_SKILL_DIR" ]] && is_valid_skill_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if is_valid_skill_dir "$REQUESTED_SKILL_DIR"; then
    printf '%s\n' "$REQUESTED_SKILL_DIR"
    return 0
  fi

  return 1
}

validate_skill_source() {
  COMMON_SRC="$SKILL_DIR/assets/common"
  SRC="$SKILL_DIR/assets/stacks/$STACK"
  CODEX_ASSETS="$SKILL_DIR/assets/codex"
  ROOT_CLAUDE_TEMPLATE="$SKILL_DIR/assets/root-claude.md"
  CENTRALIZATION_TEMPLATE="$SKILL_DIR/assets/instruction-centralization.md"
  TEMPLATE_RENDERER="$SKILL_DIR/scripts/render-instruction-template.sh"

  if [[ ! -d "$COMMON_SRC" ]]; then
    echo "ERROR: Common assets directory is missing: $COMMON_SRC" >&2
    exit 1
  fi

  if [[ ! -f "$COMMON_SRC/settings.json" ]]; then
    echo "ERROR: Common Claude settings template is missing: $COMMON_SRC/settings.json" >&2
    exit 1
  fi

  if [[ ! -f "$COMMON_SRC/hooks/sync-marketplace.sh" ]]; then
    echo "ERROR: Common marketplace sync hook is missing: $COMMON_SRC/hooks/sync-marketplace.sh" >&2
    exit 1
  fi

  if [[ ! -d "$SRC" ]]; then
    echo "ERROR: No template found for stack '$STACK' at $SRC" >&2
    exit 1
  fi

  if [[ ! -f "$SRC/CLAUDE.md" ]]; then
    echo "ERROR: Stack template is missing CLAUDE.md: $SRC/CLAUDE.md" >&2
    exit 1
  fi

  if [[ ! -d "$SRC/rules" ]]; then
    echo "ERROR: Stack template is missing rules directory: $SRC/rules" >&2
    exit 1
  fi

  if [[ ! -f "$TEMPLATE_RENDERER" ]]; then
    echo "ERROR: Instruction template renderer is missing: $TEMPLATE_RENDERER" >&2
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
}

CLAUDE_DIR=".claude"
SHARED_DIR=".agents"
CODEX_DIR=".codex"
AGENTS_FILE="AGENTS.md"
CLAUDE_FILE="CLAUDE.md"
CLAUDE_PROXY="@AGENTS.md"
CREATED=()
UPDATED=()
SKIPPED=()
PENDING=()
MIGRATED=()
REMOVED=()
CONFLICTS=()
CLEANUP_CONFLICTS=()
PROVIDER_ROOT_CONFLICTS=()

if ! command -v git >/dev/null 2>&1 || [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != true ]]; then
  echo "ERROR: bootstrap must run inside a Git worktree" >&2
  exit 1
fi

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

upgrade_marketplace() {
  if ! command -v fury >/dev/null 2>&1; then
    printf 'ERROR: fury CLI is required to upgrade %s before bootstrap.\n' "$MARKETPLACE_NAME" >&2
    return 1
  fi

  echo "[marketplace-bootstrap] Upgrading $MARKETPLACE_NAME for $PROVIDER..."
  if ! fury ai assets marketplace upgrade \
    --name "$MARKETPLACE_NAME" \
    --provider "$PROVIDER"; then
    printf 'ERROR: marketplace upgrade failed for %s/%s; no project asset was changed.\n' \
      "$MARKETPLACE_NAME" "$PROVIDER" >&2
    return 1
  fi
  echo "[marketplace-bootstrap] Marketplace upgrade completed."
}

if [[ "$MARKETPLACE_ALREADY_UPGRADED" -eq 0 ]]; then
  if ! upgrade_marketplace; then
    exit 1
  fi
else
  echo "[marketplace-bootstrap] Marketplace upgrade already completed by caller."
fi

if ! SKILL_DIR="$(resolve_skill_dir)"; then
  echo "ERROR: could not resolve updated $SKILL_NAME source after marketplace upgrade" >&2
  exit 1
fi
validate_skill_source

# Serializes sync writers so concurrent invocations cannot replace each other's
# files. Upgrade runs before this lock to keep failed upgrades write-free.
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

# shellcheck disable=SC2329
release_sync_lock() {
  if [[ "$SYNC_LOCK_ACQUIRED" -eq 1 ]]; then
    rm -f -- "$SYNC_LOCK_OWNER_FILE"
    rmdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null || true
  fi
}

acquire_sync_lock() {
  [[ "$SYNC_MODE" -eq 1 ]] || return 0

  mkdir -p -- "$SHARED_DIR"
  if mkdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null; then
    SYNC_LOCK_ACQUIRED=1
    trap release_sync_lock EXIT
    write_sync_lock_owner
    return $?
  fi

  if reclaim_stale_sync_lock && mkdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null; then
    SYNC_LOCK_ACQUIRED=1
    trap release_sync_lock EXIT
    write_sync_lock_owner
    return $?
  fi

  printf 'WARNING: another asset synchronization is running or left an active/ambiguous lock; no asset was changed\n' >&2
  return 1
}

if [[ "$SYNC_MODE" -eq 1 ]] && ! acquire_sync_lock; then
  exit 0
fi

record_created() {
  CREATED+=("$1")
}

record_updated() {
  UPDATED+=("$1")
}

record_skipped() {
  SKIPPED+=("$1")
}

record_pending() {
  PENDING+=("$1")
}

is_ignored_path() {
  local path="$1"
  local check_status

  if git check-ignore -q -- "$path" 2>/dev/null; then
    check_status=0
  else
    check_status=$?
  fi

  case "$check_status" in
    0)
      return 0
      ;;
    1)
      return 1
      ;;
    *)
      return 2
      ;;
  esac
}

# Validate every existing directory component before creating a destination
# parent. This prevents writes from following a pre-existing symlink outside
# the project.
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
      CONFLICTS+=("$destination parent directory contains symlink $current_path; neither was changed")
      return 1
    fi

    if [[ -e "$current_path" && ! -d "$current_path" ]]; then
      CONFLICTS+=("$destination parent directory is not a directory: $current_path; neither was changed")
      return 1
    fi
  done
}

show_sync_diff() {
  local src="$1"
  local dst="$2"
  local source_description="${3:-$src}"

  printf 'Diff for %s (source: %s):\n' "$dst" "$source_description"
  if [[ -f "$dst" ]]; then
    diff -u -- "$dst" "$src" || true
  else
    diff -u -- /dev/null "$src" || true
  fi
}

confirm_sync_replacement() {
  local destination="$1"
  local answer

  if [[ "$AUTO_CONFIRM" -eq 1 ]]; then
    return 0
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'Skipping %s: sync requires interactive confirmation or --yes.\n' "$destination"
    return 1
  fi

  printf 'Replace %s with the template? [y/N] ' "$destination"
  if ! IFS= read -r answer; then
    return 1
  fi

  [[ "$answer" =~ ^([YySs]|[Yy][Ee][Ss])$ ]]
}

sync_file() {
  local src="$1"
  local dst="$2"
  local source_description="${3:-$src}"
  local expected_destination=""
  local temporary_destination

  if [[ ! -f "$src" ]]; then
    CONFLICTS+=("$source_description is not a regular file; $dst was not changed")
    return 0
  fi

  if ! validate_destination_parent "$dst"; then
    return 0
  fi
  mkdir -p -- "$(dirname -- "$dst")"

  if [[ -L "$dst" ]]; then
    CONFLICTS+=("$dst is a symlink; neither it nor its target was changed")
    return 0
  fi

  if [[ -e "$dst" && ! -f "$dst" ]]; then
    CONFLICTS+=("$dst is not a regular file; neither it nor its parent was changed")
    return 0
  fi

  if [[ ! -e "$dst" ]]; then
    if ! temporary_destination="$(mktemp "${dst}.agent-ready-sync.XXXXXX")"; then
      CONFLICTS+=("could not stage new content for $dst; neither was changed")
      return 0
    fi
    if ! cp -p -- "$src" "$temporary_destination"; then
      rm -f -- "$temporary_destination"
      CONFLICTS+=("could not stage new content for $dst; neither was changed")
      return 0
    fi
    if ! mv -f -- "$temporary_destination" "$dst"; then
      rm -f -- "$temporary_destination"
      CONFLICTS+=("could not create $dst atomically; neither was changed")
      return 0
    fi
    record_created "$dst"
    return 0
  fi

  if cmp -s "$dst" "$src"; then
    record_skipped "$dst"
    return 0
  fi

  expected_destination="$(mktemp "${dst}.agent-ready-expected.XXXXXX")"
  if ! cp -p -- "$dst" "$expected_destination"; then
    rm -f -- "$expected_destination"
    CONFLICTS+=("could not snapshot $dst before confirmation; neither was changed")
    return 0
  fi

  show_sync_diff "$src" "$dst" "$source_description"
  if ! confirm_sync_replacement "$dst"; then
    rm -f -- "$expected_destination"
    record_pending "$dst"
    return 0
  fi

  temporary_destination="$(mktemp "${dst}.agent-ready-sync.XXXXXX")"
  if ! cp -p -- "$src" "$temporary_destination"; then
    rm -f -- "$temporary_destination" "$expected_destination"
    CONFLICTS+=("could not stage updated content for $dst; neither was changed")
    return 0
  fi

  if [[ -L "$dst" || ! -f "$dst" ]] || ! cmp -s "$dst" "$expected_destination"; then
    rm -f -- "$temporary_destination" "$expected_destination"
    CONFLICTS+=("$dst changed after confirmation; neither was changed")
    return 0
  fi

  # The sync lock serializes cooperating writers through this final check and
  # atomic rename; changed external content fails the snapshot comparison.
  if ! mv -f -- "$temporary_destination" "$dst"; then
    rm -f -- "$temporary_destination" "$expected_destination"
    CONFLICTS+=("could not replace $dst atomically; neither was changed")
    return 0
  fi
  rm -f -- "$expected_destination"
  record_updated "$dst"
}

# Copy a file only when destination is absent, unless explicit sync mode is
# enabled. Treat symlinks as existing so a broken symlink cannot be replaced.
copy_if_missing() {
  local src="$1"
  local dst="$2"

  if [[ "$SYNC_MODE" -eq 1 ]]; then
    sync_file "$src" "$dst"
    return 0
  fi

  if ! validate_destination_parent "$dst"; then
    return 0
  fi
  mkdir -p -- "$(dirname -- "$dst")"

  if [[ -e "$dst" || -L "$dst" ]]; then
    record_skipped "$dst"
  else
    cp -- "$src" "$dst"
    record_created "$dst"
  fi
}

relative_shared_target() {
  local relative="$1"
  local destination_directory
  local slash_count
  local parent_levels=1
  local prefix=""
  local level

  if [[ "$relative" == */* ]]; then
    destination_directory="${relative%/*}"
    slash_count="${destination_directory//[^\/]/}"
    parent_levels=$(( ${#slash_count} + 2 ))
  fi

  for ((level = 0; level < parent_levels; level++)); do
    prefix+="../"
  done

  printf '%s%s/%s\n' "$prefix" "$SHARED_DIR" "$relative"
}

link_claude_asset() {
  local relative="$1"
  local source="$SHARED_DIR/$relative"
  local destination="$CLAUDE_DIR/$relative"
  local target

  case "$relative" in
    ""|/*|../*|*/../*|*/..)
      echo "ERROR: Invalid shared asset path: $relative" >&2
      return 1
      ;;
  esac

  if [[ ! -e "$source" && ! -L "$source" ]]; then
    echo "ERROR: Canonical shared asset is missing: $source" >&2
    return 1
  fi

  if ! validate_destination_parent "$destination"; then
    return 0
  fi
  mkdir -p -- "$(dirname -- "$destination")"
  target=$(relative_shared_target "$relative")

  if [[ -L "$destination" ]]; then
    record_skipped "$destination"
    return 0
  fi

  if [[ -e "$destination" ]]; then
    if [[ ! -f "$destination" || ! -f "$source" ]] || ! cmp -s "$destination" "$source"; then
      CONFLICTS+=("$destination differs from canonical shared asset $source; neither was overwritten")
      return 0
    fi

    local temporary_link="${destination}.agent-ready-link.$$"
    local backup_file="${destination}.agent-ready-backup.$$"
    if [[ -e "$temporary_link" || -L "$temporary_link" || -e "$backup_file" || -L "$backup_file" ]]; then
      CONFLICTS+=("temporary normalization path already exists for $destination; neither was changed")
      return 0
    fi

    ln -s -- "$target" "$temporary_link"
    mv -- "$destination" "$backup_file"
    if mv -- "$temporary_link" "$destination"; then
      rm -- "$backup_file"
      MIGRATED+=("$destination -> $source")
    else
      mv -- "$backup_file" "$destination"
      rm -f -- "$temporary_link"
      echo "ERROR: Could not normalize shared asset: $destination" >&2
      return 1
    fi
    return 0
  fi

  ln -s -- "$target" "$destination"
  record_created "$destination -> $source"
}

record_removed() {
  REMOVED+=("$1")
}

record_cleanup_conflict() {
  CLEANUP_CONFLICTS+=("$1")
}

cleanup_legacy_claude_hooks() {
  local hooks_directory="$CLAUDE_DIR/hooks"
  local hook_path
  local hook_relative
  local target
  local expected_target

  if [[ -L "$hooks_directory" ]]; then
    record_cleanup_conflict "$hooks_directory is a symlink; preserved"
    return
  fi
  if [[ -e "$hooks_directory" && ! -d "$hooks_directory" ]]; then
    record_cleanup_conflict "$hooks_directory is not a directory; preserved"
    return
  fi
  [[ -d "$hooks_directory" ]] || return 0

  while IFS= read -r -d '' hook_path; do
    hook_relative="${hook_path#"$hooks_directory/"}"

    if [[ ! -L "$hook_path" ]]; then
      record_cleanup_conflict "$hook_path is custom content; preserved"
      continue
    fi

    target="$(readlink -- "$hook_path")"
    expected_target="$(relative_shared_target "hooks/$hook_relative")"
    if [[ "$target" != "$expected_target" ]]; then
      record_cleanup_conflict "$hook_path is a custom symlink; preserved"
      continue
    fi

    if rm -f -- "$hook_path"; then
      record_removed "$hook_path"
    else
      record_cleanup_conflict "could not remove managed symlink $hook_path; preserved"
    fi
  done < <(find "$hooks_directory" -mindepth 1 -maxdepth 1 -print0)

  if [[ -d "$hooks_directory" ]] && rmdir -- "$hooks_directory" 2>/dev/null; then
    record_removed "$hooks_directory"
  fi
}

cleanup_stale_claude_links() {
  local link_path
  local relative
  local target
  local expected_target
  local source_path

  [[ -d "$CLAUDE_DIR" ]] || return 0

  while IFS= read -r -d '' link_path; do
    relative="${link_path#"$CLAUDE_DIR/"}"
    [[ "$relative" == "settings.json" || "$relative" == "hooks" || "$relative" == hooks/* ]] && continue

    if ! target="$(readlink -- "$link_path")"; then
      record_cleanup_conflict "$link_path target could not be read; preserved"
      continue
    fi
    expected_target="$(relative_shared_target "$relative")"
    if [[ "$target" == "$expected_target" ]]; then
      source_path="$SHARED_DIR/$relative"
      if [[ ! -e "$source_path" && ! -L "$source_path" ]]; then
        if rm -f -- "$link_path"; then
          record_removed "$link_path"
        else
          record_cleanup_conflict "could not remove stale managed symlink $link_path; preserved"
        fi
      fi
    elif [[ "$target" == *".agents/"* ]]; then
      record_cleanup_conflict "$link_path points to a non-managed .agents target; preserved"
    fi
  done < <(find "$CLAUDE_DIR" -type l -print0)
}

sync_claude_settings() {
  local template="$1"
  local destination="$CLAUDE_DIR/settings.json"
  local temporary_settings
  local merge_status=0

  if [[ -L "$destination" ]]; then
    record_cleanup_conflict "$destination is a symlink; preserved"
    return 0
  fi
  if [[ -e "$destination" && ! -f "$destination" ]]; then
    record_cleanup_conflict "$destination is not a regular file; preserved"
    return 0
  fi
  if [[ ! -f "$destination" ]]; then
    sync_file "$template" "$destination" "$template"
    return 0
  fi

  temporary_settings="$(mktemp "${TMPDIR:-/tmp}/agent-ready-settings.XXXXXX")"
  python3 - "$template" "$destination" > "$temporary_settings" <<'PY' || merge_status=$?
import json
import sys

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
    if isinstance(value, str) and (
        value.startswith("Bash(.claude/hooks/")
        or value.startswith("bash .claude/hooks/")
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
        if all(
            key in current and matches_managed_template(current[key], value)
            for key, value in expected.items()
        ):
            return True
        return any(
            key in current
            and isinstance(value, (dict, list))
            and matches_managed_template(current[key], value)
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
      sync_file "$temporary_settings" "$destination" "$template"
      ;;
    10)
      cp -- "$template" "$temporary_settings"
      sync_file "$temporary_settings" "$destination" "$template"
      ;;
    *)
      record_cleanup_conflict "$destination contains invalid JSON; preserved"
      ;;
  esac
  rm -f -- "$temporary_settings"
}

is_normalized_root_claude() {
  [[ -f "$CLAUDE_FILE" ]] && cmp -s "$CLAUDE_FILE" "$ROOT_CLAUDE_TEMPLATE"
}

is_plain_claude_proxy() {
  local claude_file="$1"

  [[ -f "$claude_file" ]] && [[ "$(cat -- "$claude_file")" == "$CLAUDE_PROXY" ]]
}

create_root_agents_from_template() {
  local temporary_agents_file

  mkdir -p -- "$(dirname -- "$AGENTS_FILE")"
  temporary_agents_file="$(mktemp "${AGENTS_FILE}.agent-ready-template.XXXXXX")"
  if ! bash "$TEMPLATE_RENDERER" \
    --template "$SRC/CLAUDE.md" \
    --rules-dir "$SRC/rules" > "$temporary_agents_file"; then
    rm -f -- "$temporary_agents_file"
    echo "ERROR: could not render stack instruction template for $AGENTS_FILE" >&2
    return 1
  fi
  chmod 0644 "$temporary_agents_file"
  mv -f -- "$temporary_agents_file" "$AGENTS_FILE"
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
      CONFLICTS+=("$CLAUDE_FILE and $AGENTS_FILE differ; agent must merge compatible instructions before normalizing")
    fi
    return
  fi

  if [[ -e "$AGENTS_FILE" || -L "$AGENTS_FILE" ]]; then
    record_skipped "$AGENTS_FILE"
    copy_if_missing "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
    return
  fi

  # The template is the single source. The renderer materializes its dynamic
  # rule catalog for the neutral shared tree consumed through AGENTS.md.
  create_root_agents_from_template
  cp -- "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
  record_created "$CLAUDE_FILE"
}

if [[ "$SYNC_MODE" -eq 0 ]]; then
  normalize_root_instructions
fi

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

if [[ "$SYNC_MODE" -eq 0 ]]; then
  ensure_root_centralization_rule
fi

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
    if is_ignored_path "$claude_file"; then
      return
    elif [[ "$?" -eq 2 ]]; then
      CONFLICTS+=("could not determine whether $claude_file is ignored; neither instruction file was changed")
      return
    fi
  fi

  if [[ -e "$agents_file" ]]; then
    if is_ignored_path "$agents_file"; then
      return
    elif [[ "$?" -eq 2 ]]; then
      CONFLICTS+=("could not determine whether $agents_file is ignored; neither instruction file was changed")
      return
    fi
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

if [[ "$SYNC_MODE" -eq 0 ]]; then
  normalize_nested_instructions
fi

create_skill_adapter() {
  local src="$1"
  local skill_name="$2"
  local dst="$SHARED_DIR/skills/$skill_name/SKILL.md"
  local temporary_adapter

  if ! validate_destination_parent "$dst"; then
    return 0
  fi
  mkdir -p -- "$(dirname -- "$dst")"

  if [[ "$SYNC_MODE" -eq 0 ]]; then
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
    return
  fi

  temporary_adapter="$(mktemp "${TMPDIR:-/tmp}/agent-ready-adapter.XXXXXX")"
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
  } > "$temporary_adapter"
  chmod 0644 "$temporary_adapter"
  sync_file "$temporary_adapter" "$dst" "$src"
  rm -f -- "$temporary_adapter"
}

# Project shared assets into the canonical .agents tree. Claude-specific
# settings remain copied to .claude; non-hook Claude assets are symlinked views
# of the canonical shared files so providers cannot drift independently. Hooks
# remain only in .agents because both providers execute the canonical scripts.
project_asset_tree() {
  local source_root="$1"
  local file
  local relative
  local skill_name

  while IFS= read -r -d '' file; do
    relative="${file#"$source_root/"}"

    if [[ "$relative" == "CLAUDE.md" ]]; then
      continue
    elif [[ "$relative" == "settings.json" ]]; then
      if [[ "$SYNC_MODE" -eq 1 ]]; then
        sync_claude_settings "$file"
      else
        copy_if_missing "$file" "$CLAUDE_DIR/$relative"
      fi
    else
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

      if [[ "$relative" != hooks/* ]]; then
        link_claude_asset "$relative"
      fi
    fi
  done < <(find "$source_root" -type f -print0)
}

project_asset_tree "$COMMON_SRC"
project_asset_tree "$SRC"

if [[ "$SYNC_MODE" -eq 1 ]]; then
  cleanup_legacy_claude_hooks
  cleanup_stale_claude_links
fi

# Codex-specific plugin assets use Codex's supported names while retaining the
# same MCP definitions and shared hook scripts.
if [[ -f "$SRC/mcp.json" ]]; then
  copy_if_missing "$SRC/mcp.json" "$CODEX_DIR/.mcp.json"
fi
if [[ "$SYNC_MODE" -eq 1 ]]; then
  sync_file "$CODEX_ASSETS/hooks.json" "$CODEX_DIR/hooks/hooks.json" "$CODEX_ASSETS/hooks.json"
else
  copy_if_missing "$CODEX_ASSETS/hooks.json" "$CODEX_DIR/hooks/hooks.json"
fi

# Print report
printf '\nStack: %s\n' "$STACK"
printf 'Providers: Claude Code + Codex-compatible shared tree\n\n'

if [[ ${#CREATED[@]} -gt 0 ]]; then
  echo "Created:"
  for file in "${CREATED[@]}"; do printf '  + %s\n' "$file"; done
fi

if [[ ${#UPDATED[@]} -gt 0 ]]; then
  echo ""
  echo "Updated from templates:"
  for file in "${UPDATED[@]}"; do printf '  ↻ %s\n' "$file"; done
fi

if [[ ${#PENDING[@]} -gt 0 ]]; then
  echo ""
  echo "Pending confirmation (not overwritten):"
  for file in "${PENDING[@]}"; do printf '  ? %s\n' "$file"; done
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

if [[ ${#REMOVED[@]} -gt 0 ]]; then
  echo ""
  echo "Removed stale managed assets:"
  for file in "${REMOVED[@]}"; do printf '  - %s\n' "$file"; done
fi

if [[ ${#CLEANUP_CONFLICTS[@]} -gt 0 ]]; then
  echo ""
  echo "Managed asset cleanup conflicts (preserved):" >&2
  for conflict in "${CLEANUP_CONFLICTS[@]}"; do printf '  ! %s\n' "$conflict" >&2; done
fi

if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
  echo ""
  echo "Instruction conflicts or differences (agent resolution may be required):" >&2
  for conflict in "${CONFLICTS[@]}"; do printf '  ! %s\n' "$conflict" >&2; done
fi

echo ""
echo "Done."
