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

# Projection touches every managed asset on each SessionStart; parameter
# expansion and skipping existing directories avoid one fork per path.
ensure_parent_directory() {
  local path="$1"
  local parent_directory="${path%/*}"

  [[ "$parent_directory" == "$path" || -z "$parent_directory" || -d "$parent_directory" ]] && return 0
  mkdir -p -- "$parent_directory"
}

validate_destination_parent() {
  local destination="$1"
  local parent_directory
  local current_path="."
  local path_component
  local relative_parent
  local -a path_components

  parent_directory="${destination%/*}"
  [[ "$parent_directory" == "$destination" || "$parent_directory" == "." ]] && return 0

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

# Assets published by agent-ready-setup are always overwritten: projects add
# their own rules or skills instead of editing managed ones. A symlink at a
# managed path is replaced, never followed; the link is removed before the
# rename so a link to a directory cannot redirect the write elsewhere.
# Consumers define record_conflict and record_updated.
replace_managed_symlink() {
  local source="$1"
  local destination="$2"
  local previous_target
  local temporary_destination=""

  if ! previous_target="$(readlink -- "$destination")"; then
    record_conflict "could not read symlink $destination; neither was changed"
    return 0
  fi
  if ! temporary_destination="$(mktemp "${destination}.agent-ready-sync.XXXXXX")" || \
    ! cp -p -- "$source" "$temporary_destination"; then
    [[ -n "$temporary_destination" ]] && rm -f -- "$temporary_destination"
    record_conflict "could not stage template content for $destination; neither was changed"
    return 0
  fi
  if [[ ! -L "$destination" || "$(readlink -- "$destination")" != "$previous_target" ]]; then
    rm -f -- "$temporary_destination"
    record_conflict "$destination changed during synchronization; neither was changed"
    return 0
  fi
  if ! rm -f -- "$destination" || ! mv -- "$temporary_destination" "$destination"; then
    rm -f -- "$temporary_destination"
    record_conflict "could not replace symlink $destination with the template; review it manually"
    return 0
  fi
  record_updated "$destination (symlink replaced with template)"
}

# Replaces a modified Claude view (regular file or foreign symlink) with the
# managed symlink to the canonical shared asset.
replace_with_claude_view() {
  local destination="$1"
  local target="$2"
  local temporary_link="${destination}.agent-ready-link.$$"

  if [[ -e "$temporary_link" || -L "$temporary_link" ]]; then
    record_conflict "temporary normalization path already exists for $destination; neither was changed"
    return 0
  fi
  if ! ln -s -- "$target" "$temporary_link"; then
    rm -f -- "$temporary_link"
    record_conflict "could not stage Claude view $destination; neither was changed"
    return 0
  fi
  if ! rm -f -- "$destination" || ! mv -- "$temporary_link" "$destination"; then
    rm -f -- "$temporary_link"
    record_conflict "could not replace Claude view $destination; review it manually"
    return 0
  fi
  record_updated "$destination -> managed view"
}

# Claude registers agents and commands natively from .claude/agents and
# .claude/commands. A .claude/skills view of their Codex adapter would register
# the same workflow twice. The name belongs to agent-ready-setup, so the view is
# removed even when it was edited; only non-regular paths are left for manual
# review. Consumers define record_removed.
remove_claude_skill_view() {
  local skill_name="$1"
  local view_directory="$CLAUDE_DIR/skills/$skill_name"
  local view_path="$view_directory/SKILL.md"

  [[ -e "$view_path" || -L "$view_path" ]] || return 0
  if [[ ! -L "$view_path" && ! -f "$view_path" ]]; then
    record_conflict "$view_path duplicates Claude agent or command $skill_name but is not a regular file; preserved"
    return 0
  fi
  if ! rm -f -- "$view_path"; then
    record_conflict "could not remove duplicate Claude skill view $view_path; preserved"
    return 0
  fi
  record_removed "$view_path"
  rmdir -- "$view_directory" 2>/dev/null || true
}

# Rules the repository adds under .agents/rules/ get the same Claude view as
# template rules, so Claude loads them natively. The renderer owns the
# definition of a project rule; managed views whose rule was deleted are pruned.
# Consumers define link_claude_asset and record_removed.
project_rule_claude_views() {
  local template_renderer="$1"
  local template_rules_directory="$2"
  local relative_path
  local rule_file
  local view_path

  [[ -d "$SHARED_DIR/rules" && ! -L "$SHARED_DIR/rules" ]] || return 0

  while IFS=$'\t' read -r relative_path rule_file; do
    [[ "$rule_file" == "$SHARED_DIR/rules/"* ]] || continue
    link_claude_asset "rules/$relative_path"
  done < <(bash "$template_renderer" --list-rules \
    --rules-dir "$template_rules_directory" \
    --project-rules-dir "$SHARED_DIR/rules")

  [[ -d "$CLAUDE_DIR/rules" && ! -L "$CLAUDE_DIR/rules" ]] || return 0
  while IFS= read -r -d '' view_path; do
    relative_path="${view_path#"$CLAUDE_DIR/"}"
    [[ -e "$SHARED_DIR/$relative_path" || -L "$SHARED_DIR/$relative_path" ]] && continue
    [[ "$(readlink -- "$view_path")" == "$(relative_shared_target "$relative_path")" ]] || continue
    if rm -f -- "$view_path"; then
      record_removed "$view_path"
    fi
  done < <(find "$CLAUDE_DIR/rules" -type l -print0)
}

# Templates carry their own provider frontmatter, so adapters are verbatim
# copies. Kept for hooks projected by older versions that call it before
# restarting with the updated hook.
render_skill_adapter() {
  cat -- "$1"
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
