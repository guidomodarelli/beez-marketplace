#!/bin/bash
# sync-marketplace.sh
# Upgrades groot-marketplace and projects managed Agent Ready assets locally.
# Runs automatically on session start (SessionStart hook).

set -euo pipefail

# Keep hook stdout empty: progress (including child commands) belongs on stderr.
# Codex treats output starting with '[' or '{' as JSON, not plain-text logs.
exec 1>&2

# shellcheck disable=SC2034
readonly MARKETPLACE_NAME="groot-marketplace"
readonly SKILL_NAME="agent-ready-setup"
readonly SHARED_DIR=".agents"
readonly CLAUDE_DIR=".claude"
readonly CODEX_DIR=".codex"
readonly GROOT_UI_HELPER_SCRIPT="scripts/setup-groot-ui.sh"
readonly ASSET_SYNC_HELPER_PATH="scripts/asset-sync-common.sh"
readonly MARKETPLACE_UPGRADE_INTERVAL_MINUTES=60
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
force_marketplace_upgrade="${AGENT_READY_SETUP_FORCE_UPGRADE:-0}"
sync_lock_inherited="${AGENT_READY_SETUP_SYNC_LOCK_HELD:-0}"
backup_directory="${AGENT_READY_SETUP_BACKUP_DIRECTORY:-}"
created_assets=()
updated_assets=()
skipped_assets=()
removed_assets=()
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

if [[ "$force_marketplace_upgrade" != 0 && "$force_marketplace_upgrade" != 1 ]]; then
  printf 'ERROR: AGENT_READY_SETUP_FORCE_UPGRADE must be 0 or 1\n' >&2
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

groot_ui_prefetch_started=0

# The npm registry lookup does not depend on the marketplace upgrade, so it runs
# concurrently instead of adding its latency after the upgrade. A process
# substitution on fixed descriptor 9 works with macOS bash 3.2 and leaves no
# temporary file behind when the script exits early.
start_groot_ui_version_prefetch() {
  local prefetch_root

  [[ -z "${AGENT_READY_SETUP_GROOT_UI_LATEST_VERSION:-}" ]] || return 0
  prefetch_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  grep -qE '"react"|"nordic"|"@andes/[^" ]+"' "$prefetch_root/package.json" 2>/dev/null || return 0
  command -v npm >/dev/null 2>&1 || return 0
  exec 9< <(npm view groot-ui version 2>/dev/null)
  groot_ui_prefetch_started=1
}

# Exports the prefetched version for setup-groot-ui.sh; an empty result lets the
# helper perform its own lookup and report errors as before.
collect_groot_ui_version_prefetch() {
  local prefetched_version=""

  [[ "$groot_ui_prefetch_started" -eq 1 ]] || return 0
  IFS= read -r prefetched_version <&9 || true
  exec 9<&-
  groot_ui_prefetch_started=0
  prefetched_version="${prefetched_version%$'\r'}"
  if [[ -n "$prefetched_version" ]]; then
    export AGENT_READY_SETUP_GROOT_UI_LATEST_VERSION="$prefetched_version"
  fi
}

if [[ -z "$stack_override" || "$stack_override" == "frontend" ]]; then
  start_groot_ui_version_prefetch
fi

# The upgrade is a network round trip on every SessionStart; within the window
# the installed marketplace copy is reused. The stamp lives outside the project
# and is written only after a successful upgrade, one per provider.
marketplace_upgrade_stamp="${XDG_CACHE_HOME:-$HOME/.cache}/agent-ready-setup/marketplace-upgrade-$provider.stamp"

is_marketplace_upgrade_recent() {
  [[ "$force_marketplace_upgrade" -eq 0 ]] || return 1
  [[ -f "$marketplace_upgrade_stamp" && ! -L "$marketplace_upgrade_stamp" ]] || return 1
  [[ -n "$(find "$marketplace_upgrade_stamp" -mmin "-$MARKETPLACE_UPGRADE_INTERVAL_MINUTES" -print 2>/dev/null)" ]]
}

record_marketplace_upgrade() {
  local stamp_directory="${marketplace_upgrade_stamp%/*}"

  [[ ! -L "$marketplace_upgrade_stamp" && ! -L "$stamp_directory" ]] || return 0
  mkdir -p -- "$stamp_directory" 2>/dev/null && touch -- "$marketplace_upgrade_stamp" 2>/dev/null || true
}

if [[ "$marketplace_already_upgraded" -eq 1 ]]; then
  echo "[marketplace-sync] Marketplace upgrade already completed by caller."
elif is_marketplace_upgrade_recent; then
  printf '[marketplace-sync] Marketplace upgraded less than %s minutes ago; upgrade skipped. Set AGENT_READY_SETUP_FORCE_UPGRADE=1 to force it.\n' \
    "$MARKETPLACE_UPGRADE_INTERVAL_MINUTES"
else
  echo "[marketplace-sync] Upgrading $MARKETPLACE_NAME for $provider..."
  fury ai assets marketplace upgrade \
    --name "$MARKETPLACE_NAME" \
    --provider "$provider"
  record_marketplace_upgrade
  echo "[marketplace-sync] Marketplace upgrade completed."
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

# Uses the same zero-padded numeric components as sorted_skill_candidates so
# snapshot and cache versions compare identically.
semantic_version_key() {
  printf '%s\n' "$1" |
    awk '
      {
        if ($0 !~ /^[0-9]+(\.[0-9]+)?(\.[0-9]+)?([+-].*)?$/) {
          printf "%020d.%020d.%020d\n", 0, 0, 0
          next
        }
        split($0, components, /[.+-]/)
        printf "%020d.%020d.%020d\n", components[1] + 0, components[2] + 0, components[3] + 0
      }
    '
}

# The marketplace upgrade refreshes only the provider marketplace snapshot; the
# versioned plugin cache advances only after a provider plugin update, so the
# snapshot is the source that carries the latest published templates.
marketplace_snapshot_root() {
  local marketplace_provider="$1"
  local known_marketplaces="$HOME/.claude/plugins/known_marketplaces.json"
  local codex_config="$HOME/.codex/config.toml"
  local configured_location=""

  if [[ "$marketplace_provider" == "claude" ]]; then
    if [[ -f "$known_marketplaces" ]] && command -v python3 >/dev/null 2>&1; then
      configured_location="$(python3 - "$known_marketplaces" "$MARKETPLACE_NAME" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], encoding="utf-8") as known_marketplaces_file:
    marketplace = json.load(known_marketplaces_file).get(sys.argv[2]) or {}
install_location = marketplace.get("installLocation") if isinstance(marketplace, dict) else None
if isinstance(install_location, str):
    print(install_location)
PY
)"
    fi
    printf '%s\n' "${configured_location:-$HOME/.claude/plugins/marketplaces/$MARKETPLACE_NAME}"
    return 0
  fi

  if [[ -f "$codex_config" ]]; then
    configured_location="$(awk -v section="[marketplaces.$MARKETPLACE_NAME]" '
      /^[[:space:]]*\[/ {
        current = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", current)
        in_section = (current == section)
        next
      }
      in_section && /^[[:space:]]*source_type[[:space:]]*=/ {
        source_type = $0
        sub(/^[^"]*"/, "", source_type)
        sub(/".*$/, "", source_type)
      }
      in_section && /^[[:space:]]*source[[:space:]]*=/ {
        source_location = $0
        sub(/^[^"]*"/, "", source_location)
        sub(/".*$/, "", source_location)
      }
      END {
        if (source_type == "local" && source_location != "") {
          print source_location
        }
      }
    ' "$codex_config" 2>/dev/null || true)"
  fi
  printf '%s\n' "${configured_location:-$HOME/.codex/.tmp/marketplaces/$MARKETPLACE_NAME}"
}

marketplace_snapshot_skill_dir() {
  printf '%s/plugins/groot-kit/skills/%s\n' "$(marketplace_snapshot_root "$1")" "$SKILL_NAME"
}

# Reads the plugin manifest version beside the snapshot skill; both provider
# manifests share the same version.
marketplace_snapshot_version() {
  local plugin_root
  local manifest

  plugin_root="$(marketplace_snapshot_root "$1")/plugins/groot-kit"
  for manifest in "$plugin_root/.claude-plugin/plugin.json" "$plugin_root/.codex-plugin/plugin.json"; do
    if [[ -f "$manifest" ]]; then
      sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1
      return 0
    fi
  done
}

cache_skill_version() {
  basename "$(dirname "$(dirname "$1")")"
}

resolve_skill_dir() {
  local candidate
  local provider_root
  local cache_root
  local hook_directory
  local project_root
  local snapshot_candidate
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

  if [[ "$provider" == "claude" ]]; then
    provider_root="$HOME/.claude"
  else
    provider_root="$HOME/.codex"
  fi

  snapshot_candidate="$(marketplace_snapshot_skill_dir "$provider")"
  if ! is_valid_skill_dir "$snapshot_candidate" "$require_asset_sync_helper"; then
    snapshot_candidate=""
  fi

  # The snapshot wins unless the cache already holds a newer version, so
  # projection never waits for a provider plugin update.
  cache_root="$provider_root/plugins/cache/$MARKETPLACE_NAME/groot-kit"
  while IFS= read -r candidate; do
    candidate="${candidate%/SKILL.md}"
    if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
      if [[ -n "$snapshot_candidate" ]] && \
        [[ ! "$(semantic_version_key "$(marketplace_snapshot_version "$provider")")" < \
          "$(semantic_version_key "$(cache_skill_version "$candidate")")" ]]; then
        candidate="$snapshot_candidate"
      fi
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(sorted_skill_candidates "$cache_root" "$SKILL_NAME")

  if [[ -n "$snapshot_candidate" ]]; then
    printf '%s\n' "$snapshot_candidate"
    return 0
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

  candidate="$provider_root/skills/$SKILL_NAME"
  if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if project_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    candidate="$project_root/plugins/groot-kit/skills/$SKILL_NAME"
    if is_valid_skill_dir "$candidate" "$require_asset_sync_helper"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  return 1
}

describe_skill_source() {
  local source="$1"
  local source_version

  if [[ "$source" == "$(marketplace_snapshot_skill_dir "$provider")" ]]; then
    source_version="$(marketplace_snapshot_version "$provider")"
    printf '[marketplace-sync] Using %s marketplace snapshot version %s.\n' \
      "$SKILL_NAME" "${source_version:-unknown}"
    return 0
  fi

  source_version="$(cache_skill_version "$source")"
  if [[ "$source_version" =~ ^[0-9]+(\.[0-9]+){0,2}([+-].*)?$ ]]; then
    printf '[marketplace-sync] Using %s cache version %s.\n' "$SKILL_NAME" "$source_version"
  else
    printf '[marketplace-sync] Using local %s source.\n' "$SKILL_NAME"
  fi
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
  record_marketplace_upgrade

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

describe_skill_source "$skill_dir"

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
  collect_groot_ui_version_prefetch

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

record_removed() {
  removed_assets+=("$1")
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
  if ! ensure_parent_directory "$backup_destination"; then
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
  local supplied_snapshot="${4:-}"

  if [[ ! -f "$source" ]]; then
    conflicts+=("$source is not a regular file; $destination was not changed")
    return 0
  fi
  # A caller may require the exact pre-merge snapshot, including initial absence.
  if [[ -n "$supplied_snapshot" ]] && ! destination_matches_snapshot "$destination" "$supplied_snapshot"; then
    record_conflict "$destination changed during synchronization; neither was changed"
    return 0
  fi

  if ! validate_destination_parent "$destination"; then
    return 0
  fi
  ensure_parent_directory "$destination"

  if [[ -L "$destination" ]]; then
    if [[ -n "$supplied_snapshot" ]]; then
      record_conflict "$destination changed during synchronization; neither was changed"
      return 0
    fi
    replace_managed_symlink "$source" "$destination"
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
    if [[ -n "$supplied_snapshot" ]] && ! destination_matches_snapshot "$destination" "$supplied_snapshot"; then
      rm -f -- "$temporary_destination"
      record_conflict "$destination changed during synchronization; neither was changed"
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
  if ! cp -p -- "${supplied_snapshot:-$destination}" "$expected_destination"; then
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
  ensure_parent_directory "$destination"
  target="$(relative_shared_target "$relative")"

  if [[ -L "$destination" ]]; then
    if [[ "$(readlink -- "$destination")" == "$target" ]]; then
      record_skipped "$destination"
    else
      replace_with_claude_view "$destination" "$target"
    fi
    return 0
  fi
  if [[ -e "$destination" ]]; then
    if [[ ! -f "$destination" ]]; then
      conflicts+=("$destination is not a regular file; neither was changed")
      return 0
    fi
    replace_with_claude_view "$destination" "$target"
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

# Templates already carry provider frontmatter, so skill adapters are verbatim
# copies of their source template.
create_skill_adapter() {
  local source="$1"
  local skill_name="$2"

  sync_file "$source" "$SHARED_DIR/skills/$skill_name/SKILL.md"
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
      github/*)
        sync_file "$source_asset" ".github/${relative_asset#github/}"
        ;;
      agents-template.md|settings.json)
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
        link_claude_asset "$relative_asset"
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
        case "$relative_asset" in
          skills/*.md) link_claude_asset "skills/$skill_name/SKILL.md" ;;
          *) remove_claude_skill_view "$skill_name" ;;
        esac
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
  collect_groot_ui_version_prefetch
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
project_rule_claude_views \
  "$skill_dir/scripts/render-instruction-template.sh" \
  "$skill_dir/assets/stacks/$stack/rules" \
  "$skill_dir/assets/common/rules"

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
sync_codex_hooks "$skill_dir/assets/codex/hooks.json"

echo "[marketplace-sync] Local managed asset projection completed for $stack."

if [[ ${#created_assets[@]} -gt 0 ]]; then
  echo "Created:"
  printf '  + %s\n' "${created_assets[@]}"
fi
if [[ ${#updated_assets[@]} -gt 0 ]]; then
  echo "Updated from templates:"
  printf '  ↻ %s\n' "${updated_assets[@]}"
fi
if [[ ${#removed_assets[@]} -gt 0 ]]; then
  echo "Removed duplicate Claude views:"
  printf '  - %s\n' "${removed_assets[@]}"
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
