#!/bin/bash
# Shared primitives for Agent Ready asset synchronization scripts.
# Consumers define record_conflict and configure shared paths/state before calls.

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

# shellcheck disable=SC2329
release_sync_lock() {
  if [[ "${SYNC_LOCK_ACQUIRED:-0}" -eq 1 ]]; then
    rm -f -- "$SYNC_LOCK_OWNER_FILE"
    rmdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null || true
  fi
}

acquire_sync_lock() {
  [[ "${SYNC_LOCK_ENABLED:-1}" -eq 1 ]] || return 0

  if [[ "${SYNC_LOCK_INHERITED:-0}" -eq 1 ]] && has_current_sync_lock_owner; then
    SYNC_LOCK_ACQUIRED=1
    trap release_sync_lock EXIT
    return 0
  fi

  if mkdir -p -- "$(dirname -- "$SYNC_LOCK_DIRECTORY")" && \
    mkdir -- "$SYNC_LOCK_DIRECTORY" 2>/dev/null; then
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
      record_conflict "$destination parent directory contains symlink $current_path; neither was changed"
      return 1
    fi
    if [[ -e "$current_path" && ! -d "$current_path" ]]; then
      record_conflict "$destination parent directory is not a directory: $current_path; neither was changed"
      return 1
    fi
  done
}

show_sync_diff() {
  local source="$1"
  local destination="$2"
  local source_description="${3:-$source}"

  printf 'Diff for %s (source: %s):\n' "$destination" "$source_description"
  if [[ -f "$destination" ]]; then
    diff -u -- "$destination" "$source" || true
  else
    diff -u -- /dev/null "$source" || true
  fi
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

  printf '%s%s/%s\n' "$prefix" "$SHARED_DIR" "$relative"
}

render_skill_adapter() {
  local source="$1"
  local skill_name="$2"

  printf '%s\n' '---'
  printf 'name: %s\n' "$skill_name"
  printf 'description: Provider-neutral reusable workflow for %s.\n' "$skill_name"
  printf '%s\n\n' '---'
  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
    !in_frontmatter { print }
  ' "$source"
}

merge_managed_settings() {
  local template_path="$1"
  local settings_path="$2"
  local matching_mode="${3:-strict}"
  local -a matching_options=()

  case "$matching_mode" in
    strict) ;;
    nested) matching_options+=(--allow-nested-template-match) ;;
    *)
      printf 'ERROR: unsupported managed settings matching mode: %s\n' "$matching_mode" >&2
      return 2
      ;;
  esac

  python3 "$ASSET_SYNC_SKILL_DIR/scripts/merge-managed-settings.py" \
    "${matching_options[@]}" \
    "$template_path" \
    "$settings_path"
}
