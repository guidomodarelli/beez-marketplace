#!/bin/bash
# bootstrap.sh
# Projects Agent Ready templates into Claude, shared-agent, and Codex trees.
# Managed assets are always synchronized with the templates without prompting;
# symlinks, non-regular files, and custom content are preserved and reported.
# Instruction files are normalized so AGENTS.md is canonical and every CLAUDE.md
# is the root proxy template.
#
# Usage:
#   bash bootstrap.sh --stack <frontend|node|java|go> --skill-dir <path> [--provider <claude|codex>]
#   bash bootstrap.sh --stack <frontend|node|java|go> --skill-dir <path> --normalize-only

set -euo pipefail

# shellcheck disable=SC2034
readonly MARKETPLACE_NAME="groot-marketplace"
readonly SKILL_NAME="agent-ready-setup"

STACK=""
REQUESTED_SKILL_DIR=""
SKILL_DIR=""
PROVIDER="${AGENT_READY_SETUP_ACTIVE_PROVIDER:-}"
MARKETPLACE_ALREADY_UPGRADED="${AGENT_READY_SETUP_MARKETPLACE_UPGRADED:-0}"
NORMALIZE_ONLY=0
readonly SYNC_LOCK_DIRECTORY=".agents/.agent-ready-assets.lock"
# shellcheck disable=SC2034
readonly SYNC_LOCK_OWNER_FILE="$SYNC_LOCK_DIRECTORY/owner"
# shellcheck disable=SC2034
readonly SYNC_LOCK_STALE_AFTER_MINUTES=10
# shellcheck disable=SC2034
SYNC_LOCK_ACQUIRED=0
# shellcheck disable=SC2034
SYNC_LOCK_INHERITED=0
SYNC_LOCK_ENABLED=0

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
    --normalize-only)
      NORMALIZE_ONLY=1
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

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

if [[ "$SKILL_DIR" != /* ]]; then
  if ! SKILL_DIR="$(CDPATH='' cd -- "$SKILL_DIR" && pwd)"; then
    echo "ERROR: could not resolve --skill-dir: $SKILL_DIR" >&2
    exit 1
  fi
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
  local project_root
  local snapshot_candidate
  local snapshot_provider

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
  cache_root="$provider_root/plugins/cache/$MARKETPLACE_NAME/groot-kit"
  snapshot_provider="${provider_root##*/.}"

  if [[ "$REQUESTED_SKILL_DIR" != "$cache_root"/* ]] && \
    is_valid_skill_dir "$REQUESTED_SKILL_DIR"; then
    printf '%s\n' "$REQUESTED_SKILL_DIR"
    return 0
  fi

  snapshot_candidate="$(marketplace_snapshot_skill_dir "$snapshot_provider")"
  if ! is_valid_skill_dir "$snapshot_candidate"; then
    snapshot_candidate=""
  fi

  # The requested cache version stays eligible: excluding it downgraded callers
  # that already pass the newest version to the next older cache entry. The
  # snapshot wins unless the cache already holds a newer version, so projection
  # never waits for a provider plugin update.
  while IFS= read -r candidate; do
    candidate="${candidate%/SKILL.md}"
    if is_valid_skill_dir "$candidate"; then
      if [[ -n "$snapshot_candidate" ]] && \
        [[ ! "$(semantic_version_key "$(marketplace_snapshot_version "$snapshot_provider")")" < \
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
      if [[ "$candidate" != "$REQUESTED_SKILL_DIR" ]] && is_valid_skill_dir "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi

  candidate="$provider_root/skills/$SKILL_NAME"
  if [[ "$candidate" != "$REQUESTED_SKILL_DIR" ]] && is_valid_skill_dir "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

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

describe_skill_source() {
  local source="$1"
  local source_version
  local snapshot_provider

  for snapshot_provider in claude codex; do
    if [[ "$source" == "$(marketplace_snapshot_skill_dir "$snapshot_provider")" ]]; then
      source_version="$(marketplace_snapshot_version "$snapshot_provider")"
      printf '[marketplace-bootstrap] Using %s marketplace snapshot version %s.\n' \
        "$SKILL_NAME" "${source_version:-unknown}"
      return 0
    fi
  done

  source_version="$(cache_skill_version "$source")"
  if [[ "$source_version" =~ ^[0-9]+(\.[0-9]+){0,2}([+-].*)?$ ]]; then
    printf '[marketplace-bootstrap] Using %s cache version %s.\n' "$SKILL_NAME" "$source_version"
  else
    printf '[marketplace-bootstrap] Using local %s source.\n' "$SKILL_NAME"
  fi
}

validate_skill_source() {
  COMMON_SRC="$SKILL_DIR/assets/common"
  SRC="$SKILL_DIR/assets/stacks/$STACK"
  CODEX_ASSETS="$SKILL_DIR/assets/codex"
  ROOT_CLAUDE_TEMPLATE="$SKILL_DIR/assets/claude-proxy.md"
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

  if [[ ! -f "$SRC/agents-template.md" ]]; then
    echo "ERROR: Stack template is missing agents-template.md: $SRC/agents-template.md" >&2
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

  if [[ ! -f "$SKILL_DIR/scripts/asset-sync-common.sh" ]]; then
    echo "ERROR: Shared asset synchronization helper is missing: $SKILL_DIR/scripts/asset-sync-common.sh" >&2
    exit 1
  fi

  if [[ ! -f "$SKILL_DIR/scripts/merge-managed-settings.py" ]]; then
    echo "ERROR: Managed settings merger is missing: $SKILL_DIR/scripts/merge-managed-settings.py" >&2
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

  if [[ "$STACK" == "frontend" && ! -x "$SKILL_DIR/scripts/setup-groot-ui.sh" ]]; then
    echo "ERROR: Frontend groot-ui version helper is missing or not executable: $SKILL_DIR/scripts/setup-groot-ui.sh" >&2
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
MIGRATED=()
RENAMED=()
REMOVED=()
CONFLICTS=()
CLEANUP_CONFLICTS=()
PROVIDER_ROOT_CONFLICTS=()

record_conflict() {
  CONFLICTS+=("$1")
}

if ! command -v git >/dev/null 2>&1 || [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != true ]]; then
  echo "ERROR: bootstrap must run inside a Git worktree" >&2
  exit 1
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd -- "$PROJECT_ROOT"

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

groot_ui_prefetch_started=0

# The npm registry lookup does not depend on the marketplace upgrade, so it runs
# concurrently instead of adding its latency after the upgrade. A process
# substitution on fixed descriptor 9 works with macOS bash 3.2 and leaves no
# temporary file behind when the script exits early.
start_groot_ui_version_prefetch() {
  [[ -z "${AGENT_READY_SETUP_GROOT_UI_LATEST_VERSION:-}" ]] || return 0
  [[ -f package.json ]] || return 0
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

if [[ "$NORMALIZE_ONLY" -eq 0 && "$STACK" == "frontend" ]]; then
  start_groot_ui_version_prefetch
fi

if [[ "$NORMALIZE_ONLY" -eq 1 ]]; then
  echo "[marketplace-bootstrap] Instruction normalization only; marketplace upgrade skipped."
elif [[ "$MARKETPLACE_ALREADY_UPGRADED" -eq 0 ]]; then
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
describe_skill_source "$SKILL_DIR"
validate_skill_source
# shellcheck disable=SC2034
ASSET_SYNC_SKILL_DIR="$SKILL_DIR"
# Serializes sync writers so concurrent invocations cannot replace each other's
# files. Upgrade runs before this lock to keep failed upgrades write-free.
# shellcheck disable=SC1091
source "$SKILL_DIR/scripts/asset-sync-common.sh"
# shellcheck disable=SC2034
SYNC_LOCK_ENABLED=$(( 1 - NORMALIZE_ONLY ))

if [[ "$NORMALIZE_ONLY" -eq 0 ]] && ! acquire_sync_lock; then
  exit 0
fi

if [[ "$NORMALIZE_ONLY" -eq 0 && "$STACK" == "frontend" ]]; then
  collect_groot_ui_version_prefetch
  bash "$SKILL_DIR/scripts/setup-groot-ui.sh" "package.json"
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

sync_file() {
  local src="$1"
  local dst="$2"
  local source_description="${3:-$src}"
  local expected_destination=""
  local temporary_destination
  local supplied_snapshot="${4:-}"

  if [[ ! -f "$src" ]]; then
    CONFLICTS+=("$source_description is not a regular file; $dst was not changed")
    return 0
  fi

  # A caller may require the exact pre-merge snapshot, including initial absence.
  if [[ -n "$supplied_snapshot" ]] && ! destination_matches_snapshot "$dst" "$supplied_snapshot"; then
    record_conflict "$dst changed during synchronization; neither was changed"
    return 0
  fi

  if ! validate_destination_parent "$dst"; then
    return 0
  fi
  ensure_parent_directory "$dst"

  if [[ -L "$dst" ]]; then
    if [[ -n "$supplied_snapshot" ]]; then
      record_conflict "$dst changed during synchronization; neither was changed"
      return 0
    fi
    replace_managed_symlink "$src" "$dst"
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
    if [[ -n "$supplied_snapshot" ]] && ! destination_matches_snapshot "$dst" "$supplied_snapshot"; then
      rm -f -- "$temporary_destination"
      record_conflict "$dst changed during synchronization; neither was changed"
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
  if ! cp -p -- "${supplied_snapshot:-$dst}" "$expected_destination"; then
    rm -f -- "$expected_destination"
    CONFLICTS+=("could not snapshot $dst before replacement; neither was changed")
    return 0
  fi

  show_sync_diff "$src" "$dst" "$source_description"

  temporary_destination="$(mktemp "${dst}.agent-ready-sync.XXXXXX")"
  if ! cp -p -- "$src" "$temporary_destination"; then
    rm -f -- "$temporary_destination" "$expected_destination"
    CONFLICTS+=("could not stage updated content for $dst; neither was changed")
    return 0
  fi

  if [[ -L "$dst" || ! -f "$dst" ]] || ! cmp -s "$dst" "$expected_destination"; then
    rm -f -- "$temporary_destination" "$expected_destination"
    CONFLICTS+=("$dst changed during synchronization; neither was changed")
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
  ensure_parent_directory "$destination"
  target=$(relative_shared_target "$relative")

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
      CONFLICTS+=("$destination is not a regular file; neither was changed")
      return 0
    fi
    replace_with_claude_view "$destination" "$target"
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
  merge_managed_settings "$template" "$destination" nested > "$temporary_settings" || merge_status=$?

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

record_renamed() {
  RENAMED+=("$1")
}

is_claude_filename() {
  case "$1" in
    [cC][lL][aA][uU][dD][eE].[mM][dD]) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_claude_filename() {
  local directory="$1"
  local claude_file="$directory/$CLAUDE_FILE"
  local candidate
  local case_variant=""
  local case_variant_count=0
  local exact_name_found=0
  local temporary_path
  local ignore_status

  while IFS= read -r -d '' candidate; do
    if is_ignored_path "$candidate"; then
      continue
    else
      ignore_status=$?
      if [[ "$ignore_status" -eq 2 ]]; then
        CONFLICTS+=("could not determine whether $candidate is ignored; neither was renamed")
        return 0
      fi
    fi

    if [[ "${candidate##*/}" == "$CLAUDE_FILE" ]]; then
      exact_name_found=1
    else
      case_variant="$candidate"
      case_variant_count=$((case_variant_count + 1))
    fi
  done < <(find "$directory" -mindepth 1 -maxdepth 1 -iname "$CLAUDE_FILE" -print0)

  if [[ "$case_variant_count" -eq 0 ]]; then
    return 0
  fi

  if [[ "$exact_name_found" -eq 1 || "$case_variant_count" -ne 1 ]]; then
    CONFLICTS+=("$directory contains multiple case variants of $CLAUDE_FILE; neither was renamed")
    return 0
  fi

  if [[ -L "$case_variant" || ! -f "$case_variant" ]]; then
    CONFLICTS+=("$case_variant is not a regular file; $claude_file was not renamed")
    return 0
  fi

  if ! temporary_path="$(mktemp "$directory/.${CLAUDE_FILE}.agent-ready-name.XXXXXX")"; then
    CONFLICTS+=("could not stage rename for $case_variant; $claude_file was not changed")
    return 0
  fi
  rm -f -- "$temporary_path"

  if ! mv -- "$case_variant" "$temporary_path" || ! mv -n -- "$temporary_path" "$claude_file"; then
    if [[ -e "$temporary_path" || -L "$temporary_path" ]]; then
      if mv -n -- "$temporary_path" "$case_variant"; then
        CONFLICTS+=("could not rename $case_variant to $claude_file; destination changed concurrently and was preserved")
      else
        CONFLICTS+=("could not rename $case_variant to $claude_file; staged content was preserved at $temporary_path")
      fi
    else
      CONFLICTS+=("could not rename $case_variant to $claude_file; neither was changed")
    fi
    return 0
  fi

  if [[ -e "$temporary_path" || -L "$temporary_path" ]]; then
    if mv -n -- "$temporary_path" "$case_variant"; then
      CONFLICTS+=("could not rename $case_variant to $claude_file; destination changed concurrently and was preserved")
    else
      CONFLICTS+=("could not rename $case_variant to $claude_file; staged content was preserved at $temporary_path")
    fi
    return 0
  fi

  record_renamed "$case_variant -> $claude_file"
}

normalize_instruction_filenames() {
  local path
  local basename
  local directory

  normalize_claude_filename "."
  while IFS= read -r -d '' path; do
    basename="${path##*/}"
    if ! is_claude_filename "$basename"; then
      continue
    fi
    if [[ "$path" == */* ]]; then
      directory="${path%/*}"
    else
      directory="."
    fi
    normalize_claude_filename "$directory"
  done < <(git ls-files --cached --others --exclude-standard -z)
}

is_normalized_root_claude() {
  [[ -f "$CLAUDE_FILE" ]] && cmp -s "$CLAUDE_FILE" "$ROOT_CLAUDE_TEMPLATE"
}

is_normalized_claude_proxy() {
  local claude_file="$1"

  [[ -f "$claude_file" ]] && cmp -s "$claude_file" "$ROOT_CLAUDE_TEMPLATE"
}

write_claude_proxy() {
  local claude_file="$1"

  cp -- "$ROOT_CLAUDE_TEMPLATE" "$claude_file"
}

is_plain_claude_proxy() {
  local claude_file="$1"

  [[ -f "$claude_file" ]] && [[ "$(cat -- "$claude_file")" == "$CLAUDE_PROXY" ]]
}

create_root_agents_from_template() {
  local temporary_agents_file
  local -a renderer_arguments=(
    --template "$SRC/agents-template.md"
    --rules-dir "$SRC/rules"
    --project-rules-dir "$SHARED_DIR/rules"
    --centralization "$CENTRALIZATION_TEMPLATE"
  )

  if [[ -d "$COMMON_SRC/rules" ]]; then
    renderer_arguments+=(--common-rules-dir "$COMMON_SRC/rules")
  fi

  mkdir -p -- "$(dirname -- "$AGENTS_FILE")"
  temporary_agents_file="$(mktemp "${AGENTS_FILE}.agent-ready-template.XXXXXX")"
  if ! bash "$TEMPLATE_RENDERER" "${renderer_arguments[@]}" > "$temporary_agents_file"; then
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
    sync_file "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
    return
  fi

  # The template is the single source. The renderer materializes its dynamic
  # rule catalog for the neutral shared tree consumed through AGENTS.md.
  create_root_agents_from_template
  cp -- "$ROOT_CLAUDE_TEMPLATE" "$CLAUDE_FILE"
  record_created "$CLAUDE_FILE"
}

normalize_instruction_filenames
normalize_root_instructions

# The centralization rule is part of the managed AGENTS.md block, which
# merge-instructions.sh copies verbatim from the template on every sync.

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
    if is_normalized_claude_proxy "$claude_file"; then
      if [[ -e "$agents_file" ]]; then
        record_skipped "$claude_file"
        record_skipped "$agents_file"
      elif validate_destination_parent "$agents_file" && : > "$agents_file"; then
        MIGRATED+=("$claude_file -> $agents_file (empty canonical sibling)")
      else
        CONFLICTS+=("$claude_file is an orphaned proxy; $agents_file could not be created")
      fi
      return
    fi

    if is_plain_claude_proxy "$claude_file"; then
      if [[ -e "$agents_file" ]]; then
        write_claude_proxy "$claude_file"
        MIGRATED+=("$claude_file -> root instruction proxy")
      elif validate_destination_parent "$agents_file" && : > "$agents_file"; then
        write_claude_proxy "$claude_file"
        MIGRATED+=("$claude_file -> $agents_file (empty canonical sibling)")
      else
        CONFLICTS+=("$claude_file is an orphaned proxy; $agents_file could not be created")
      fi
      return
    fi

    if [[ ! -e "$agents_file" ]]; then
      cp -- "$claude_file" "$agents_file"
      write_claude_proxy "$claude_file"
      MIGRATED+=("$claude_file -> $agents_file")
    elif cmp -s "$claude_file" "$agents_file"; then
      write_claude_proxy "$claude_file"
      MIGRATED+=("$claude_file -> $agents_file")
    else
      CONFLICTS+=("$claude_file and $agents_file differ; neither was overwritten")
    fi
    return
  fi

  if [[ -e "$agents_file" ]]; then
    write_claude_proxy "$claude_file"
    MIGRATED+=("$agents_file -> $claude_file proxy")
  fi
}

normalize_nested_instructions() {
  local path
  local basename
  local directory

  while IFS= read -r -d '' path; do
    basename="${path##*/}"
    if [[ "$basename" != "$CLAUDE_FILE" && "$basename" != "$AGENTS_FILE" ]]; then
      continue
    fi
    if [[ "$path" == */* ]]; then
      directory="${path%/*}"
    else
      directory="."
    fi
    [[ "$directory" == "." ]] && continue
    normalize_nested_instruction_pair "$directory"
  done < <(git ls-files --cached --others --exclude-standard -z)
}

normalize_nested_instructions

if [[ "$NORMALIZE_ONLY" -eq 1 ]]; then
  printf '\nInstruction normalization completed from %s.\n' "$PROJECT_ROOT"
  if [[ ${#RENAMED[@]} -gt 0 ]]; then
    echo "Renamed instruction files:"
    for file in "${RENAMED[@]}"; do printf '  ↪ %s\n' "$file"; done
  fi
  if [[ ${#MIGRATED[@]} -gt 0 ]]; then
    echo "Normalized instructions:"
    for file in "${MIGRATED[@]}"; do printf '  ↔ %s\n' "$file"; done
  fi
  if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "Already existed (skipped):"
    for file in "${SKIPPED[@]}"; do printf '  ~ %s\n' "$file"; done
  fi
  if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    echo "Instruction conflicts or differences (preserved):" >&2
    for conflict in "${CONFLICTS[@]}"; do printf '  ! %s\n' "$conflict" >&2; done
  fi
  exit 0
fi

# Templates already carry provider frontmatter, so skill adapters are verbatim
# copies of their source template.
create_skill_adapter() {
  local src="$1"
  local skill_name="$2"

  sync_file "$src" "$SHARED_DIR/skills/$skill_name/SKILL.md"
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

    if [[ "$relative" == "agents-template.md" ]]; then
      continue
    elif [[ "$relative" == "settings.json" ]]; then
      sync_claude_settings "$file"
    else
      case "$relative" in
        github/*)
          sync_file "$file" ".github/${relative#github/}"
          continue
          ;;
        skills/*/SKILL.md)
          skill_name="${relative#skills/}"
          skill_name="${skill_name%/SKILL.md}"
          create_skill_adapter "$file" "$skill_name"
          ;;
        skills/*/*.md)
          sync_file "$file" "$SHARED_DIR/$relative"
          ;;
        agents/*.md|commands/*.md|skills/*.md)
          sync_file "$file" "$SHARED_DIR/$relative"
          skill_name="${relative##*/}"
          skill_name="${skill_name%.md}"
          create_skill_adapter "$file" "$skill_name"
          case "$relative" in
            skills/*.md) link_claude_asset "skills/$skill_name/SKILL.md" ;;
            *) remove_claude_skill_view "$skill_name" ;;
          esac
          ;;
        *)
          sync_file "$file" "$SHARED_DIR/$relative"
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
project_rule_claude_views "$TEMPLATE_RENDERER" "$SRC/rules" "$COMMON_SRC/rules"

cleanup_legacy_claude_hooks
cleanup_stale_claude_links

# Codex-specific plugin assets use Codex's supported names while retaining the
# same MCP definitions and shared hook scripts.
if [[ -f "$SRC/mcp.json" ]]; then
  sync_file "$SRC/mcp.json" "$CODEX_DIR/.mcp.json"
fi
sync_codex_hooks "$CODEX_ASSETS/hooks.json"

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

if [[ ${#RENAMED[@]} -gt 0 ]]; then
  echo ""
  echo "Renamed instruction files:"
  for file in "${RENAMED[@]}"; do printf '  ↪ %s\n' "$file"; done
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
