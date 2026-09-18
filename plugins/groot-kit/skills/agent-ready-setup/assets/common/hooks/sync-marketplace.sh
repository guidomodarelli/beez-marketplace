#!/bin/bash
# sync-marketplace.sh
# Upgrades groot-marketplace and projects managed Agent Ready assets locally.
# Runs automatically on session start (SessionStart hook).

set -euo pipefail

# shellcheck disable=SC2034
readonly MARKETPLACE_NAME="groot-marketplace"
readonly SKILL_NAME="agent-ready-setup"
readonly SHARED_DIR=".agents"
readonly CLAUDE_DIR=".claude"
readonly CODEX_DIR=".codex"
readonly GROOT_UI_HELPER_SCRIPT="scripts/setup-groot-ui.sh"
readonly ASSET_SYNC_HELPER_PATH="scripts/asset-sync-common.sh"
readonly SYNC_LOCK_DIRECTORY="$SHARED_DIR/.agent-ready-assets.lock"
# shellcheck disable=SC2034
readonly SYNC_LOCK_OWNER_FILE="$SYNC_LOCK_DIRECTORY/owner"
# shellcheck disable=SC2034
readonly SYNC_LOCK_STALE_AFTER_MINUTES=10
# shellcheck disable=SC2034
SYNC_LOCK_ACQUIRED=0
SYNC_LOCK_INHERITED=0
# shellcheck disable=SC2034
SYNC_LOCK_ENABLED=1

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

record_conflict() {
  conflicts+=("$1")
}

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
  local require_asset_sync_helper="${2:-0}"

  [[ -f "$candidate/SKILL.md" && \
    -d "$candidate/assets/stacks" && \
    -f "$candidate/assets/common/hooks/sync-marketplace.sh" && \
    -f "$candidate/assets/common/settings.json" && \
    -f "$candidate/assets/codex/hooks.json" && \
    -f "$candidate/scripts/merge-managed-settings.py" && \
    ("$require_asset_sync_helper" -eq 0 || -f "$candidate/$ASSET_SYNC_HELPER_PATH") ]]
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

sorted_skill_candidates() {
  local cache_root="$1"
  local skill_name="$2"

  # Prefix candidates with zero-padded numeric components before lexical sorting.
  find "$cache_root" -type f -path "*/skills/$skill_name/SKILL.md" -print 2>/dev/null |
    awk -F/ '
      {
        version = $(NF - 3)
        if (version !~ /^[0-9]+(\.[0-9]+)?(\.[0-9]+)?([+-].*)?$/) {
          printf "%020d.%020d.%020d\t%s\n", 0, 0, 0, $0
          next
        }
        split(version, components, /[.+-]/)
        printf "%020d.%020d.%020d\t%s\n", components[1] + 0, components[2] + 0, components[3] + 0, $0
      }
    ' |
    sort -r |
    cut -f2-
}

resolve_skill_dir() {
  local candidate
  local provider_root
  local cache_root
  local hook_directory
  local project_root
  local require_asset_sync_helper="${1:-0}"

  if [[ -n "${AGENT_READY_SETUP_SKILL_DIR:-}" ]]; then
    candidate="$AGENT_READY_SETUP_SKILL_DIR"
    if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
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
      if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi

  hook_directory="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  for candidate in \
    "$hook_directory/../../../.." \
    "$hook_directory/../../.."; do
    if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
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
  if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  cache_root="$provider_root/plugins/cache/$MARKETPLACE_NAME/groot-kit"
  while IFS= read -r candidate; do
    candidate="${candidate%/SKILL.md}"
    if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(sorted_skill_candidates "$cache_root" "$SKILL_NAME")

  if project_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    candidate="$project_root/plugins/groot-kit/skills/$SKILL_NAME"
    if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  return 1
}

refresh_missing_asset_sync_helper() {
  local refreshed_skill_dir

  if [[ -f "$skill_dir/$ASSET_SYNC_HELPER_PATH" ]]; then
    return 0
  fi

  echo "[marketplace-sync] Shared synchronization helper is missing; refreshing $MARKETPLACE_NAME for $provider..."
  if ! command -v fury >/dev/null 2>&1; then
    printf 'ERROR: fury CLI is required to download %s\n' "$ASSET_SYNC_HELPER_PATH" >&2
    return 1
  fi
  if ! fury ai assets marketplace upgrade \
    --name "$MARKETPLACE_NAME" \
    --provider "$provider"; then
    printf 'ERROR: marketplace refresh failed while downloading %s\n' "$ASSET_SYNC_HELPER_PATH" >&2
    return 1
  fi

  if ! refreshed_skill_dir="$(resolve_skill_dir 1)"; then
    printf 'ERROR: refreshed %s source is unavailable; %s could not be downloaded\n' \
      "$SKILL_NAME" "$ASSET_SYNC_HELPER_PATH" >&2
    return 1
  fi
  skill_dir="$refreshed_skill_dir"

  if [[ ! -f "$skill_dir/$ASSET_SYNC_HELPER_PATH" ]]; then
    printf 'ERROR: marketplace refresh completed but %s is still missing from %s\n' \
      "$ASSET_SYNC_HELPER_PATH" "$skill_dir" >&2
    return 1
  fi
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

if ! refresh_missing_asset_sync_helper; then
  if [[ -n "${AGENT_READY_SETUP_SKILL_DIR:-}" ]]; then
    exit 1
  fi
  printf 'WARNING: %s is unavailable after marketplace refresh; local projection skipped.\n' \
    "$ASSET_SYNC_HELPER_PATH" >&2
  exit 0
fi

# shellcheck disable=SC2034
ASSET_SYNC_SKILL_DIR="$skill_dir"
# shellcheck disable=SC1090
source "$skill_dir/$ASSET_SYNC_HELPER_PATH"
# shellcheck disable=SC2034
SYNC_LOCK_INHERITED="$sync_lock_inherited"

if ! project_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  printf 'WARNING: could not resolve Git project root; local projection skipped.\n' >&2
  exit 0
fi
cd -- "$project_root"

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

link_claude_asset() {
  local relative="$1"
  local source="$SHARED_DIR/$relative"
  local destination="$CLAUDE_DIR/$relative"
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
  local destination="$SHARED_DIR/skills/$skill_name/SKILL.md"
  local temporary_adapter

  if ! temporary_adapter="$(mktemp "${TMPDIR:-/tmp}/agent-ready-adapter.XXXXXX")"; then
    conflicts+=("could not stage skill adapter for $source; neither was changed")
    return 0
  fi
  if ! render_skill_adapter "$source" "$skill_name" > "$temporary_adapter"; then
    rm -f -- "$temporary_adapter"
    conflicts+=("could not render skill adapter for $source; neither was changed")
    return 0
  fi
  chmod 0644 "$temporary_adapter"

  sync_file "$temporary_adapter" "$destination" "$source"
  rm -f -- "$temporary_adapter"
  link_claude_asset "skills/$skill_name/SKILL.md"
}

project_assets() {
  local source_root="$1"
  local project_codex_mcp="$2"
  local source_asset
  local relative_asset
  local skill_name

  [[ -d "$source_root" ]] || return 0

  while IFS= read -r -d '' source_asset; do
    relative_asset="${source_asset#"$source_root/"}"
    case "$relative_asset" in
      CLAUDE.md|settings.json)
        continue
        ;;
      hooks/*)
        sync_file "$source_asset" "$SHARED_DIR/$relative_asset"
        ;;
      mcp.json)
        sync_file "$source_asset" "$SHARED_DIR/$relative_asset"
        link_claude_asset "$relative_asset"
        if [[ "$project_codex_mcp" -eq 1 ]]; then
          sync_file "$source_asset" "$CODEX_DIR/.mcp.json"
        fi
        ;;
      skills/*/SKILL.md)
        skill_name="${relative_asset#skills/}"
        skill_name="${skill_name%/SKILL.md}"
        create_skill_adapter "$source_asset" "$skill_name"
        ;;
      skills/*/*.md)
        sync_file "$source_asset" "$SHARED_DIR/$relative_asset"
        link_claude_asset "$relative_asset"
        ;;
      agents/*.md|commands/*.md|skills/*.md)
        sync_file "$source_asset" "$SHARED_DIR/$relative_asset"
        link_claude_asset "$relative_asset"
        skill_name="${relative_asset##*/}"
        skill_name="${skill_name%.md}"
        create_skill_adapter "$source_asset" "$skill_name"
        ;;
      *)
        sync_file "$source_asset" "$SHARED_DIR/$relative_asset"
        link_claude_asset "$relative_asset"
        ;;
    esac
  done < <(find "$source_root" -type f -print0)
}

sync_claude_settings() {
  local template="$1"
  local destination="$CLAUDE_DIR/settings.json"
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
  merge_managed_settings "$template" "$destination" strict > "$temporary_settings" || merge_status=$?

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

if [[ -L "$SHARED_DIR" || ( -e "$SHARED_DIR" && ! -d "$SHARED_DIR" ) ]]; then
  echo "WARNING: .agents is a symlink or non-directory; no asset was changed" >&2
  exit 0
fi
if ! acquire_sync_lock; then
  exit 0
fi

sync_hook_source="$skill_dir/assets/common/hooks/sync-marketplace.sh"
sync_hook_destination="$SHARED_DIR/hooks/sync-marketplace.sh"
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

# Project common and stack assets before merging instruction references. The
# shared tree remains canonical, while Claude and Codex receive provider views.
project_assets "$skill_dir/assets/common" 0
project_assets "$skill_dir/assets/stacks/$stack" 1

# Reuse bootstrap's conservative instruction normalizer so SessionStart also
# discovers project CLAUDE.md files under directories such as .claude/.
if [[ -f "$skill_dir/scripts/bootstrap.sh" ]] && \
  grep -Fq -- '--normalize-only' "$skill_dir/scripts/bootstrap.sh"; then
  bash "$skill_dir/scripts/bootstrap.sh" \
    --stack "$stack" \
    --skill-dir "$skill_dir" \
    --provider "$provider" \
    --normalize-only
else
  printf 'WARNING: bootstrap.sh does not support instruction normalization; skipped.\n' >&2
fi

sync_claude_settings "$skill_dir/assets/common/settings.json"
sync_file "$skill_dir/assets/codex/hooks.json" "$CODEX_DIR/hooks/hooks.json"

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
