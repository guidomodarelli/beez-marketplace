#!/bin/bash

set -euo pipefail
umask 077

readonly FALLBACK_SCHEMA_VERSION=2
readonly MAX_RETRY_AFTER_SECONDS=86400

OUTPUT_EMITTED=false
TEMP_DIRECTORY=""
CHECKS_JSON='[]'
FAILURES_JSON='[]'
SELECTED_EXIT_CODE=0
SELECTED_EXIT_PRIORITY=999
REQUESTED_PROVIDER=""
RESOLVED_PROVIDER=""
REUSE_RESULT_FILE=""
RESULT_SOURCE="fresh"
RESULT_CHECKED_AT_EPOCH=""
SCHEMA_VERSION="$FALLBACK_SCHEMA_VERSION"

cleanup() {
  if [ -n "${TEMP_DIRECTORY:-}" ] && [ -d "$TEMP_DIRECTORY" ]; then
    rm -rf -- "$TEMP_DIRECTORY"
  fi
}

on_exit() {
  local shell_status=$?

  if [ "$OUTPUT_EMITTED" != "true" ]; then
    printf '%s\n' '{"schema_version":2,"scope":"shell","provider":null,"ok":false,"exit_code":70,"active_context":null,"source":"fresh","checked_at_epoch":null,"checks":[{"name":"internal_contract","ok":false,"status":"failed","failure_code":"INTERNAL_CONTRACT_FAILED","attempts":null,"http_status":null,"retry_after_seconds":null}],"failures":[{"code":"INTERNAL_CONTRACT_FAILED","check":"internal_contract","exit_code":70}]}'
    shell_status=70
  fi

  cleanup
  return "$shell_status"
}

handle_signal() {
  exit 70
}

trap on_exit EXIT
trap handle_signal HUP INT TERM

emit_constant_failure() {
  local exit_code="$1"
  local failure_code="$2"
  local check_name="$3"

  OUTPUT_EMITTED=true
  printf '{"schema_version":2,"scope":"shell","provider":null,"ok":false,"exit_code":%s,"active_context":null,"source":"fresh","checked_at_epoch":null,"checks":[{"name":"%s","ok":false,"status":"failed","failure_code":"%s","attempts":null,"http_status":null,"retry_after_seconds":null}],"failures":[{"code":"%s","check":"%s","exit_code":%s}]}\n' \
    "$exit_code" "$check_name" "$failure_code" "$failure_code" "$check_name" "$exit_code"
  exit "$exit_code"
}

append_check() {
  local check_name="$1"
  local check_ok="$2"
  local check_status="$3"
  local failure_code="${4:-}"
  local attempts="${5:-}"
  local http_status="${6:-}"
  local retry_after_seconds="${7:-}"

  CHECKS_JSON="$(printf '%s' "$CHECKS_JSON" | jq -c \
    --arg name "$check_name" \
    --argjson ok "$check_ok" \
    --arg status "$check_status" \
    --arg failure_code "$failure_code" \
    --arg attempts "$attempts" \
    --arg http_status "$http_status" \
    --arg retry_after_seconds "$retry_after_seconds" \
    '. + [{
      name: $name,
      ok: $ok,
      status: $status,
      failure_code: (if $failure_code == "" then null else $failure_code end),
      attempts: (if $attempts == "" then null else ($attempts | tonumber) end),
      http_status: (if $http_status == "" then null else ($http_status | tonumber) end),
      retry_after_seconds: (if $retry_after_seconds == "" then null else ($retry_after_seconds | tonumber) end)
    }]')"
}

exit_priority() {
  case "$1" in
    70) printf '%s' 10 ;;
    2) printf '%s' 20 ;;
    10) printf '%s' 30 ;;
    25) printf '%s' 40 ;;
    20) printf '%s' 50 ;;
    21) printf '%s' 60 ;;
    22) printf '%s' 70 ;;
    23) printf '%s' 80 ;;
    24) printf '%s' 90 ;;
    *) printf '%s' 100 ;;
  esac
}

record_failure() {
  local failure_code="$1"
  local check_name="$2"
  local exit_code="$3"
  local priority

  FAILURES_JSON="$(printf '%s' "$FAILURES_JSON" | jq -c \
    --arg code "$failure_code" \
    --arg check "$check_name" \
    --argjson exit_code "$exit_code" \
    '. + [{code: $code, check: $check, exit_code: $exit_code}]')"

  priority="$(exit_priority "$exit_code")"
  if [ "$priority" -lt "$SELECTED_EXIT_PRIORITY" ]; then
    SELECTED_EXIT_PRIORITY="$priority"
    SELECTED_EXIT_CODE="$exit_code"
  fi
}

emit_result() {
  local result_ok=false
  local result_json

  if [ "$SELECTED_EXIT_CODE" -eq 0 ]; then
    result_ok=true
  fi

  if [ -z "$RESULT_CHECKED_AT_EPOCH" ]; then
    RESULT_CHECKED_AT_EPOCH="$(date +%s)"
  fi

  result_json="$(jq -nc \
    --argjson schema_version "$SCHEMA_VERSION" \
    --arg scope "shell" \
    --arg provider "$RESOLVED_PROVIDER" \
    --argjson ok "$result_ok" \
    --argjson exit_code "$SELECTED_EXIT_CODE" \
    --arg source "$RESULT_SOURCE" \
    --argjson checked_at_epoch "$RESULT_CHECKED_AT_EPOCH" \
    --argjson checks "$CHECKS_JSON" \
    --argjson failures "$FAILURES_JSON" \
    '{
      schema_version: $schema_version,
      scope: $scope,
      provider: (if $provider == "" then null else $provider end),
      ok: $ok,
      exit_code: $exit_code,
      active_context: null,
      source: $source,
      checked_at_epoch: $checked_at_epoch,
      checks: $checks,
      failures: $failures
    }')"

  OUTPUT_EMITTED=true
  printf '%s\n' "$result_json"
  exit "$SELECTED_EXIT_CODE"
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --provider)
        if [ -n "$REQUESTED_PROVIDER" ] || [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
          emit_constant_failure 2 "INVALID_ARGUMENTS" "arguments"
        fi
        REQUESTED_PROVIDER="$2"
        shift 2
        ;;
      --reuse-result)
        if [ -n "$REUSE_RESULT_FILE" ] || [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
          emit_constant_failure 2 "INVALID_ARGUMENTS" "arguments"
        fi
        REUSE_RESULT_FILE="$2"
        shift 2
        ;;
      *)
        emit_constant_failure 2 "INVALID_ARGUMENTS" "arguments"
        ;;
    esac
  done

  case "$REQUESTED_PROVIDER" in
    claude|codex|copilot|auto) ;;
    *) emit_constant_failure 2 "INVALID_PROVIDER" "arguments" ;;
  esac

  if [ -n "$REUSE_RESULT_FILE" ]; then
    case "$REUSE_RESULT_FILE" in
      /*) ;;
      *) emit_constant_failure 2 "INVALID_REUSE_RESULT_PATH" "arguments" ;;
    esac

    case "$REUSE_RESULT_FILE" in
      *[!A-Za-z0-9_./-]*) emit_constant_failure 2 "INVALID_REUSE_RESULT_PATH" "arguments" ;;
      *) ;;
    esac
  fi
}

validate_configuration() {
  local config_json="$1"

  printf '%s' "$config_json" | jq -e '
    . as $config |
    type == "object" and
    (($config | keys | sort) == ["fury_runtime", "fury_services", "grid_sharing", "reuse_result", "schema_version"]) and
    ($config.schema_version == 2) and

    ($config.grid_sharing | type == "object") and
    (($config.grid_sharing | keys | sort) == ["api", "network", "plugin", "required_document"]) and
    ($config.grid_sharing.plugin | type == "object") and
    (($config.grid_sharing.plugin | keys | sort) == ["id", "required_skill_path"]) and
    ($config.grid_sharing.plugin.id == "grid-sharing@tech-plugins-marketplace") and
    ($config.grid_sharing.plugin.required_skill_path == "skills/grid/SKILL.md") and
    ($config.grid_sharing.api | type == "object") and
    (($config.grid_sharing.api | keys | sort) == ["base_url", "endpoints"]) and
    ($config.grid_sharing.api.base_url == "https://grid.melioffice.com") and
    ($config.grid_sharing.api.endpoints | type == "object") and
    (($config.grid_sharing.api.endpoints | keys | sort) == ["documents", "identity", "ping", "skill_version"]) and
    ($config.grid_sharing.api.endpoints.ping == "/ping") and
    ($config.grid_sharing.api.endpoints.skill_version == "/skill/version") and
    ($config.grid_sharing.api.endpoints.identity == "/api/v1/me") and
    ($config.grid_sharing.api.endpoints.documents == "/api/v1/documents") and
    ($config.grid_sharing.required_document | type == "object") and
    (($config.grid_sharing.required_document | keys | sort) == ["id", "name", "viewer_url"]) and
    ($config.grid_sharing.required_document.name | type == "string") and
    ($config.grid_sharing.required_document.name | length > 0) and
    (($config.grid_sharing.required_document.name | test("[[:cntrl:]]")) | not) and
    ($config.grid_sharing.required_document.id | type == "string") and
    ($config.grid_sharing.required_document.id | test("^[A-Z0-9]+$")) and
    ($config.grid_sharing.required_document.viewer_url | type == "string") and
    ($config.grid_sharing.required_document.viewer_url | test("^https://grid\\.adminml\\.com/d/[A-Z0-9]+/view$")) and
    ($config.grid_sharing.required_document.viewer_url | endswith("/d/" + $config.grid_sharing.required_document.id + "/view")) and
    ($config.grid_sharing.network | type == "object") and
    (($config.grid_sharing.network | keys | sort) == ["connect_timeout_seconds", "max_retries", "max_time_seconds"]) and
    ($config.grid_sharing.network.connect_timeout_seconds | type == "number") and
    ($config.grid_sharing.network.connect_timeout_seconds == ($config.grid_sharing.network.connect_timeout_seconds | floor)) and
    ($config.grid_sharing.network.connect_timeout_seconds > 0) and
    ($config.grid_sharing.network.connect_timeout_seconds <= 60) and
    ($config.grid_sharing.network.max_time_seconds | type == "number") and
    ($config.grid_sharing.network.max_time_seconds == ($config.grid_sharing.network.max_time_seconds | floor)) and
    ($config.grid_sharing.network.max_time_seconds >= $config.grid_sharing.network.connect_timeout_seconds) and
    ($config.grid_sharing.network.max_time_seconds <= 120) and
    ($config.grid_sharing.network.max_retries | type == "number") and
    ($config.grid_sharing.network.max_retries == ($config.grid_sharing.network.max_retries | floor)) and
    (($config.grid_sharing.network.max_retries == 0) or ($config.grid_sharing.network.max_retries == 1)) and

    ($config.fury_services | type == "object") and
    (($config.fury_services | keys | sort) == ["expected_mcp_server", "mcp_manifest_path", "plugin", "provider_manifest_paths"]) and
    ($config.fury_services.plugin | type == "object") and
    (($config.fury_services.plugin | keys | sort) == ["id", "required_skill_path"]) and
    ($config.fury_services.plugin.id == "fury-services@tech-plugins-marketplace") and
    ($config.fury_services.plugin.required_skill_path == "skills/fury-services-documentation/SKILL.md") and
    ($config.fury_services.provider_manifest_paths | type == "object") and
    (($config.fury_services.provider_manifest_paths | keys | sort) == ["claude", "codex"]) and
    ($config.fury_services.provider_manifest_paths.claude == ".claude-plugin/plugin.json") and
    ($config.fury_services.provider_manifest_paths.codex == ".codex-plugin/plugin.json") and
    ($config.fury_services.mcp_manifest_path == ".mcp.json") and
    ($config.fury_services.expected_mcp_server | type == "object") and
    (($config.fury_services.expected_mcp_server | keys | sort) == ["args", "command", "name"]) and
    ($config.fury_services.expected_mcp_server.name == "fury") and
    ($config.fury_services.expected_mcp_server.command == "mcp-remote-proxy") and
    ($config.fury_services.expected_mcp_server.args == [
      "https://mcp-services-gateway.furycloud.io/v1/servers/fury",
      "--headers",
      "x-origin",
      "fury-services-plugin",
      "--timeout",
      "300"
    ]) and

    ($config.fury_runtime | type == "object") and
    (($config.fury_runtime | keys | sort) == ["component", "required_tools"]) and
    ($config.fury_runtime.component == "furydocs") and
    ($config.fury_runtime.required_tools == ["get_doc_structure", "get_doc_file"]) and

    ($config.reuse_result | type == "object") and
    (($config.reuse_result | keys | sort) == ["max_age_seconds"]) and
    ($config.reuse_result.max_age_seconds | type == "number") and
    ($config.reuse_result.max_age_seconds == ($config.reuse_result.max_age_seconds | floor)) and
    ($config.reuse_result.max_age_seconds > 0) and
    ($config.reuse_result.max_age_seconds <= 3600)
  ' >/dev/null 2>&1
}

create_temp_directory() {
  if TEMP_DIRECTORY="$(mktemp -d -t groot-readiness.XXXXXX 2>/dev/null)"; then
    return 0
  fi

  if TEMP_DIRECTORY="$(mktemp -d /tmp/groot-readiness.XXXXXX 2>/dev/null)"; then
    return 0
  fi

  return 1
}

reuse_parent_directory_is_secure() {
  local file_path="$1"
  local perl_binary="$2"
  local current_user_id="$3"
  local parent_directory="${file_path%/*}"

  if [ -z "$parent_directory" ]; then
    parent_directory="/"
  fi

  "$perl_binary" -e '
    my ($parent_directory, $expected_user_id) = @ARGV;
    my @metadata = lstat($parent_directory);
    exit 1 unless @metadata;
    exit 1 unless (($metadata[2] & 0170000) == 0040000);
    exit 1 unless $metadata[4] == $expected_user_id;
    exit 1 unless (($metadata[2] & 0077) == 0);
  ' "$parent_directory" "$current_user_id" >/dev/null 2>&1
}

snapshot_reuse_file() {
  local file_path="$1"
  local snapshot_file="$2"
  local descriptor_metadata
  local file_type
  local file_owner
  local file_mode
  local file_mode_decimal
  local current_user_id
  local perl_binary

  if [ -L "$file_path" ] || [ ! -f "$file_path" ] || [ ! -r "$file_path" ]; then
    return 1
  fi

  if ! perl_binary="$(command -v perl)" || [ -z "$perl_binary" ]; then
    return 1
  fi
  current_user_id="$(id -u)"

  if ! reuse_parent_directory_is_secure "$file_path" "$perl_binary" "$current_user_id"; then
    return 1
  fi

  if ! exec 9< "$file_path"; then
    return 1
  fi

  if [ -L "$file_path" ]; then
    exec 9<&-
    return 1
  fi
  if ! descriptor_metadata="$("$perl_binary" -e '
    my @metadata = stat(STDIN);
    exit 1 unless @metadata;
    my $type = (($metadata[2] & 0170000) == 0100000) ? "regular file" : "other";
    printf "%s|%d|%o", $type, $metadata[4], ($metadata[2] & 0777);
  ' <&9 2>/dev/null)"; then
    exec 9<&-
    return 1
  fi
  IFS='|' read -r file_type file_owner file_mode <<EOF
$descriptor_metadata
EOF

  case "$file_type" in
    "regular file") ;;
    *)
      exec 9<&-
      return 1
      ;;
  esac

  if [ "$file_owner" != "$current_user_id" ]; then
    exec 9<&-
    return 1
  fi

  case "$file_mode" in
    ''|*[!0-7]*)
      exec 9<&-
      return 1
      ;;
  esac

  file_mode_decimal=$((8#$file_mode))
  if [ $((file_mode_decimal & 63)) -ne 0 ]; then
    exec 9<&-
    return 1
  fi

  if ! /bin/cat <&9 > "$snapshot_file"; then
    exec 9<&-
    return 1
  fi
  exec 9<&-
  chmod 600 "$snapshot_file"
  [ -s "$snapshot_file" ]
}

try_reuse_result() {
  local current_epoch
  local reused_provider
  local reuse_snapshot_file="$TEMP_DIRECTORY/reuse-result-snapshot.json"

  if [ -z "$REUSE_RESULT_FILE" ]; then
    return 1
  fi

  if ! snapshot_reuse_file "$REUSE_RESULT_FILE" "$reuse_snapshot_file"; then
    append_check "reuse_result" false "failed" "REUSE_RESULT_FILE_UNSAFE"
    record_failure "REUSE_RESULT_FILE_UNSAFE" "reuse_result" 70
    emit_result
  fi

  current_epoch="$(date +%s)"
  if ! jq -e \
    --argjson schema_version "$SCHEMA_VERSION" \
    --arg requested_provider "$REQUESTED_PROVIDER" \
    --argjson current_epoch "$current_epoch" \
    --argjson max_age_seconds "$REUSE_RESULT_MAX_AGE_SECONDS" '
      . as $result |
      ($result | type == "object") and
      (($result | keys | sort) == ["active_context", "checked_at_epoch", "checks", "exit_code", "failures", "ok", "provider", "schema_version", "scope", "source"]) and
      ($result.schema_version == $schema_version) and
      ($result.scope == "shell") and
      (($result.provider == "claude") or ($result.provider == "codex")) and
      ((($requested_provider == "auto") and (($result.provider == "claude") or ($result.provider == "codex"))) or ($result.provider == $requested_provider)) and
      ($result.ok == true) and
      ($result.exit_code == 0) and
      ($result.active_context == null) and
      (($result.source == "fresh") or ($result.source == "reused")) and
      ($result.checked_at_epoch | type == "number") and
      ($result.checked_at_epoch == ($result.checked_at_epoch | floor)) and
      (($current_epoch - $result.checked_at_epoch) >= 0) and
      (($current_epoch - $result.checked_at_epoch) <= $max_age_seconds) and
      ($result.failures == []) and
      ($result.checks | type == "array") and
      (($result.checks | map(.name)) == ["dependencies", "configuration", "provider_inventory", "grid_plugin", "grid_required_skill", "fury_plugin", "fury_required_skill", "fury_manifest", "fury_mcp_declaration", "fury_mcp_cli", "ping", "skill_version", "identity", "general_read", "required_document"]) and
      all($result.checks[];
        (type == "object") and
        ((keys | sort) == ["attempts", "failure_code", "http_status", "name", "ok", "retry_after_seconds", "status"]) and
        (.ok == true) and
        (.status == "passed") and
        (.failure_code == null) and
        ((.attempts == null) or ((.attempts | type == "number") and (.attempts >= 1))) and
        ((.http_status == null) or ((.http_status | type == "number") and (.http_status >= 100) and (.http_status <= 599))) and
        ((.retry_after_seconds == null) or ((.retry_after_seconds | type == "number") and (.retry_after_seconds >= 0) and (.retry_after_seconds <= 86400)))
      )
    ' < "$reuse_snapshot_file" >/dev/null 2>&1; then
    printf '%s\n' 'check-groot-queue-readiness: REUSE_RESULT_REJECTED; running a fresh preflight.' >&2
    return 1
  fi

  reused_provider="$(jq -er '.provider' < "$reuse_snapshot_file")"
  RESOLVED_PROVIDER="$reused_provider"
  RESULT_SOURCE="reused"
  RESULT_CHECKED_AT_EPOCH="$(jq -er '.checked_at_epoch' < "$reuse_snapshot_file")"
  CHECKS_JSON="$(jq -c '[.checks[] | {
    name,
    ok,
    status,
    failure_code,
    attempts,
    http_status,
    retry_after_seconds
  }]' < "$reuse_snapshot_file")"
  FAILURES_JSON='[]'
  SELECTED_EXIT_CODE=0
  SELECTED_EXIT_PRIORITY=999
  emit_result
}

is_strict_semver() {
  local version="$1"

  jq -ne --arg version "$version" '
    $version | test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\\.((0|[1-9][0-9]*)|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$")
  ' >/dev/null 2>&1
}

reset_provider_state() {
  PROVIDER_INVENTORY_OK=false
  PROVIDER_INVENTORY_FAILURE_CODE=""
  PROVIDER_INVENTORY_EXIT_CODE=10
  PROVIDER_INVENTORY_FILE=""

  GRID_PLUGIN_OK=false
  GRID_PLUGIN_FAILURE_CODE=""
  GRID_REQUIRED_SKILL_OK=false
  GRID_PLUGIN_VERSION=""
  GRID_PLUGIN_INSTALL_PATH=""

  FURY_PLUGIN_OK=false
  FURY_PLUGIN_FAILURE_CODE=""
  FURY_REQUIRED_SKILL_OK=false
  FURY_PLUGIN_VERSION=""
  FURY_PLUGIN_INSTALL_PATH=""

  FURY_MANIFEST_OK=false
  FURY_MANIFEST_FAILURE_CODE=""
  FURY_MCP_DECLARATION_OK=false
  FURY_MCP_DECLARATION_FAILURE_CODE=""
  FURY_MCP_CLI_OK=false
  FURY_MCP_CLI_FAILURE_CODE=""
}

set_plugin_failure() {
  local plugin_kind="$1"
  local failure_code="$2"

  case "$plugin_kind" in
    grid) GRID_PLUGIN_FAILURE_CODE="$failure_code" ;;
    fury) FURY_PLUGIN_FAILURE_CODE="$failure_code" ;;
  esac
}

load_provider_inventory() {
  local provider="$1"

  PROVIDER_INVENTORY_FILE="$TEMP_DIRECTORY/${provider}-inventory.json"

  if [ "$provider" = "copilot" ]; then
    PROVIDER_INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_UNSUPPORTED"
    PROVIDER_INVENTORY_EXIT_CODE=2
    return 0
  fi

  if ! command -v "$provider" >/dev/null 2>&1; then
    PROVIDER_INVENTORY_FAILURE_CODE="PROVIDER_CLI_UNAVAILABLE"
    PROVIDER_INVENTORY_EXIT_CODE=2
    return 0
  fi

  case "$provider" in
    claude)
      if ! claude plugin list --json > "$PROVIDER_INVENTORY_FILE" 2>/dev/null; then
        PROVIDER_INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_FAILED"
        return 0
      fi
      if ! jq -e 'type == "array" and all(.[]; type == "object")' "$PROVIDER_INVENTORY_FILE" >/dev/null 2>&1; then
        PROVIDER_INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_INVALID"
        return 0
      fi
      ;;
    codex)
      if ! codex plugin list --marketplace tech-plugins-marketplace --json > "$PROVIDER_INVENTORY_FILE" 2>/dev/null; then
        PROVIDER_INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_FAILED"
        return 0
      fi
      if ! jq -e 'type == "object" and (.installed | type == "array") and all(.installed[]; type == "object")' "$PROVIDER_INVENTORY_FILE" >/dev/null 2>&1; then
        PROVIDER_INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_INVALID"
        return 0
      fi
      ;;
  esac

  PROVIDER_INVENTORY_OK=true
}

inspect_inventory_plugin() {
  local provider="$1"
  local plugin_kind="$2"
  local plugin_id="$3"
  local not_installed_code="$4"
  local disabled_code="$5"
  local ambiguous_code="$6"
  local invalid_code="$7"
  local normalized_inventory_file="$TEMP_DIRECTORY/${provider}-${plugin_kind}-plugin.json"
  local plugin_count
  local plugin_installed
  local plugin_enabled
  local plugin_version
  local plugin_install_path
  local plugin_values

  case "$provider" in
    claude)
      plugin_count="$(jq -r --arg plugin_id "$plugin_id" '[.[] | select(.id == $plugin_id)] | length' "$PROVIDER_INVENTORY_FILE")"
      ;;
    codex)
      plugin_count="$(jq -r --arg plugin_id "$plugin_id" '[.installed[] | select(.pluginId == $plugin_id)] | length' "$PROVIDER_INVENTORY_FILE")"
      ;;
  esac

  if [ "$plugin_count" -eq 0 ]; then
    set_plugin_failure "$plugin_kind" "$not_installed_code"
    return 0
  fi
  if [ "$plugin_count" -ne 1 ]; then
    set_plugin_failure "$plugin_kind" "$ambiguous_code"
    return 0
  fi

  case "$provider" in
    claude)
      jq -ec --arg plugin_id "$plugin_id" '
        [.[] | select(.id == $plugin_id)][0]
        | {installed: true, enabled, version, path: .installPath}
      ' "$PROVIDER_INVENTORY_FILE" > "$normalized_inventory_file"
      ;;
    codex)
      jq -ec --arg plugin_id "$plugin_id" '
        [.installed[] | select(.pluginId == $plugin_id)][0]
        | {installed, enabled, version, path: .source.path}
      ' "$PROVIDER_INVENTORY_FILE" > "$normalized_inventory_file"
      ;;
  esac

  if ! plugin_values="$(jq -er '
    select(
      type == "object" and
      (.installed | type == "boolean") and
      (.enabled | type == "boolean") and
      (.version | type == "string") and
      (.version | length > 0) and
      ((.version | test("[[:cntrl:]]")) | not) and
      (.path | type == "string") and
      (.path | startswith("/")) and
      ((.path | test("[[:cntrl:]]")) | not)
    )
    | [.installed, .enabled, .version, .path]
    | @tsv
  ' "$normalized_inventory_file")"; then
    set_plugin_failure "$plugin_kind" "$invalid_code"
    return 0
  fi

  IFS=$'\t' read -r plugin_installed plugin_enabled plugin_version plugin_install_path <<EOF
$plugin_values
EOF

  if [ "$plugin_installed" != "true" ]; then
    set_plugin_failure "$plugin_kind" "$not_installed_code"
    return 0
  fi
  if [ "$plugin_enabled" != "true" ]; then
    set_plugin_failure "$plugin_kind" "$disabled_code"
    return 0
  fi

  case "$plugin_kind" in
    grid)
      GRID_PLUGIN_OK=true
      GRID_PLUGIN_VERSION="$plugin_version"
      GRID_PLUGIN_INSTALL_PATH="$plugin_install_path"
      ;;
    fury)
      if ! is_strict_semver "$plugin_version"; then
        FURY_PLUGIN_FAILURE_CODE="$invalid_code"
        return 0
      fi
      FURY_PLUGIN_OK=true
      FURY_PLUGIN_VERSION="$plugin_version"
      FURY_PLUGIN_INSTALL_PATH="$plugin_install_path"
      ;;
  esac
}

inspect_required_skills() {
  local grid_required_skill_file
  local fury_required_skill_file

  if [ "$GRID_PLUGIN_OK" = "true" ]; then
    grid_required_skill_file="${GRID_PLUGIN_INSTALL_PATH%/}/$GRID_REQUIRED_SKILL_PATH"
    if [ ! -L "$grid_required_skill_file" ] && [ -f "$grid_required_skill_file" ] && [ -r "$grid_required_skill_file" ]; then
      GRID_REQUIRED_SKILL_OK=true
    fi
  fi

  if [ "$FURY_PLUGIN_OK" = "true" ]; then
    fury_required_skill_file="${FURY_PLUGIN_INSTALL_PATH%/}/$FURY_REQUIRED_SKILL_PATH"
    if [ ! -L "$fury_required_skill_file" ] && [ -f "$fury_required_skill_file" ] && [ -r "$fury_required_skill_file" ]; then
      FURY_REQUIRED_SKILL_OK=true
    fi
  fi
}

inspect_fury_manifest() {
  local provider="$1"
  local provider_manifest_path
  local provider_manifest_file

  case "$provider" in
    claude) provider_manifest_path="$FURY_CLAUDE_MANIFEST_PATH" ;;
    codex) provider_manifest_path="$FURY_CODEX_MANIFEST_PATH" ;;
    *) return 0 ;;
  esac

  provider_manifest_file="${FURY_PLUGIN_INSTALL_PATH%/}/$provider_manifest_path"
  if [ -L "$provider_manifest_file" ] || [ ! -f "$provider_manifest_file" ] || [ ! -r "$provider_manifest_file" ]; then
    FURY_MANIFEST_FAILURE_CODE="FURY_MANIFEST_UNAVAILABLE"
    return 0
  fi

  case "$provider" in
    claude)
      if ! jq -e \
        --arg version "$FURY_PLUGIN_VERSION" \
        --arg mcp_manifest_path "./$FURY_MCP_MANIFEST_PATH" '
          type == "object" and
          (.name == "fury-services") and
          (.version == $version) and
          ((has("mcpServers") | not) or (.mcpServers == $mcp_manifest_path))
        ' "$provider_manifest_file" >/dev/null 2>&1; then
        FURY_MANIFEST_FAILURE_CODE="FURY_MANIFEST_INVALID"
        return 0
      fi
      ;;
    codex)
      if ! jq -e \
        --arg version "$FURY_PLUGIN_VERSION" \
        --arg mcp_manifest_path "./$FURY_MCP_MANIFEST_PATH" '
          type == "object" and
          (.name == "fury-services") and
          (.version == $version) and
          (.skills == "./skills/") and
          (.mcpServers == $mcp_manifest_path)
        ' "$provider_manifest_file" >/dev/null 2>&1; then
        FURY_MANIFEST_FAILURE_CODE="FURY_MANIFEST_INVALID"
        return 0
      fi
      ;;
  esac

  FURY_MANIFEST_OK=true
}

inspect_fury_mcp_declaration() {
  local mcp_manifest_file="${FURY_PLUGIN_INSTALL_PATH%/}/$FURY_MCP_MANIFEST_PATH"

  if [ -L "$mcp_manifest_file" ] || [ ! -f "$mcp_manifest_file" ] || [ ! -r "$mcp_manifest_file" ]; then
    FURY_MCP_DECLARATION_FAILURE_CODE="FURY_MCP_DECLARATION_UNAVAILABLE"
    return 0
  fi

  if ! jq -e \
    --arg server_name "$FURY_MCP_SERVER_NAME" \
    --arg expected_command "$FURY_MCP_COMMAND" \
    --argjson expected_args "$FURY_MCP_ARGS_JSON" '
      type == "object" and
      ((keys | sort) == ["mcpServers"]) and
      (.mcpServers | type == "object") and
      ((.mcpServers | keys) == [$server_name]) and
      (.mcpServers[$server_name] | type == "object") and
      ((.mcpServers[$server_name] | keys | sort) == ["args", "command"]) and
      (.mcpServers[$server_name].command == $expected_command) and
      (.mcpServers[$server_name].args == $expected_args)
    ' "$mcp_manifest_file" >/dev/null 2>&1; then
    FURY_MCP_DECLARATION_FAILURE_CODE="FURY_MCP_DECLARATION_INVALID"
    return 0
  fi

  FURY_MCP_DECLARATION_OK=true
}

inspect_claude_mcp_cli() {
  local mcp_output_file="$TEMP_DIRECTORY/claude-mcp-list.txt"
  local server_prefix="plugin:fury-services:$FURY_MCP_SERVER_NAME:"
  local expected_configuration="$server_prefix $FURY_MCP_COMMAND $FURY_MCP_ARG_GATEWAY $FURY_MCP_ARG_HEADERS_FLAG $FURY_MCP_ARG_HEADER_NAME $FURY_MCP_ARG_HEADER_VALUE $FURY_MCP_ARG_TIMEOUT_FLAG $FURY_MCP_ARG_TIMEOUT_VALUE"
  local expected_connected_line="$expected_configuration - ✔ Connected"
  local legacy_connected_line="$expected_configuration - ✓ Connected"
  local matching_server_count=0
  local configuration_matches=false
  local connected_matches=false
  local output_line

  if ! claude mcp list > "$mcp_output_file" 2>/dev/null; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CLI_CHECK_FAILED"
    return 0
  fi

  while IFS= read -r output_line || [ -n "$output_line" ]; do
    case "$output_line" in
      "$server_prefix"*)
        matching_server_count=$((matching_server_count + 1))
        if [ "$output_line" = "$expected_connected_line" ] || [ "$output_line" = "$legacy_connected_line" ]; then
          connected_matches=true
        fi
        case "$output_line" in
          "$expected_configuration - "*) configuration_matches=true ;;
          *) ;;
        esac
        ;;
      *) ;;
    esac
  done < "$mcp_output_file"

  if [ "$matching_server_count" -eq 0 ]; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_NOT_CONFIGURED"
  elif [ "$matching_server_count" -ne 1 ]; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CLI_RESPONSE_INVALID"
  elif [ "$connected_matches" = "true" ]; then
    FURY_MCP_CLI_OK=true
  elif [ "$configuration_matches" = "true" ]; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CONNECTION_UNAVAILABLE"
  else
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CLI_RESPONSE_INVALID"
  fi
}

inspect_codex_mcp_cli() {
  local mcp_output_file="$TEMP_DIRECTORY/codex-mcp-list.json"
  local server_count

  if ! codex mcp list --json > "$mcp_output_file" 2>/dev/null; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CLI_CHECK_FAILED"
    return 0
  fi

  if ! jq -e 'type == "array" and all(.[]; (type == "object") and (.name | type == "string"))' "$mcp_output_file" >/dev/null 2>&1; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CLI_RESPONSE_INVALID"
    return 0
  fi

  server_count="$(jq -r --arg server_name "$FURY_MCP_SERVER_NAME" '[.[] | select(.name == $server_name)] | length' "$mcp_output_file")"
  if [ "$server_count" -eq 0 ]; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_NOT_CONFIGURED"
    return 0
  fi
  if [ "$server_count" -ne 1 ]; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CLI_RESPONSE_INVALID"
    return 0
  fi

  if jq -e \
    --arg server_name "$FURY_MCP_SERVER_NAME" \
    '[.[] | select(.name == $server_name)][0] | (.enabled == false)' \
    "$mcp_output_file" >/dev/null 2>&1; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CONNECTION_UNAVAILABLE"
    return 0
  fi

  if ! jq -e \
    --arg server_name "$FURY_MCP_SERVER_NAME" \
    --arg expected_command "$FURY_MCP_COMMAND" \
    --argjson expected_args "$FURY_MCP_ARGS_JSON" '
      [.[] | select(.name == $server_name)][0] |
      (.enabled == true) and
      (.disabled_reason == null) and
      (.transport | type == "object") and
      (.transport.type == "stdio") and
      (.transport.command == $expected_command) and
      (.transport.args == $expected_args)
    ' "$mcp_output_file" >/dev/null 2>&1; then
    FURY_MCP_CLI_FAILURE_CODE="FURY_MCP_CLI_RESPONSE_INVALID"
    return 0
  fi

  FURY_MCP_CLI_OK=true
}

inspect_fury_mcp_cli() {
  local provider="$1"

  case "$provider" in
    claude) inspect_claude_mcp_cli ;;
    codex) inspect_codex_mcp_cli ;;
  esac
}

inspect_provider_readiness() {
  local provider="$1"

  reset_provider_state
  load_provider_inventory "$provider"
  if [ "$PROVIDER_INVENTORY_OK" != "true" ]; then
    return 0
  fi

  inspect_inventory_plugin \
    "$provider" \
    "grid" \
    "$GRID_PLUGIN_ID" \
    "PLUGIN_NOT_INSTALLED" \
    "PLUGIN_DISABLED" \
    "PLUGIN_INVENTORY_AMBIGUOUS" \
    "PLUGIN_INVENTORY_INVALID"
  inspect_inventory_plugin \
    "$provider" \
    "fury" \
    "$FURY_PLUGIN_ID" \
    "FURY_PLUGIN_NOT_INSTALLED" \
    "FURY_PLUGIN_DISABLED" \
    "FURY_PLUGIN_INVENTORY_AMBIGUOUS" \
    "FURY_PLUGIN_INVENTORY_INVALID"
  inspect_required_skills

  if [ "$FURY_PLUGIN_OK" = "true" ] && [ "$FURY_REQUIRED_SKILL_OK" = "true" ]; then
    inspect_fury_manifest "$provider"
  fi
  if [ "$FURY_MANIFEST_OK" = "true" ]; then
    inspect_fury_mcp_declaration
  fi
  if [ "$FURY_MCP_DECLARATION_OK" = "true" ]; then
    inspect_fury_mcp_cli "$provider"
  fi
}

provider_shell_readiness_ok() {
  [ "$PROVIDER_INVENTORY_OK" = "true" ] &&
    [ "$GRID_PLUGIN_OK" = "true" ] &&
    [ "$GRID_REQUIRED_SKILL_OK" = "true" ] &&
    is_strict_semver "$GRID_PLUGIN_VERSION" &&
    [ "$FURY_PLUGIN_OK" = "true" ] &&
    [ "$FURY_REQUIRED_SKILL_OK" = "true" ] &&
    [ "$FURY_MANIFEST_OK" = "true" ] &&
    [ "$FURY_MCP_DECLARATION_OK" = "true" ] &&
    [ "$FURY_MCP_CLI_OK" = "true" ]
}

resolve_provider() {
  local candidate_provider
  local provider_command_available=false

  if [ "$REQUESTED_PROVIDER" != "auto" ]; then
    RESOLVED_PROVIDER="$REQUESTED_PROVIDER"
    inspect_provider_readiness "$RESOLVED_PROVIDER"
    return 0
  fi

  RESOLVED_PROVIDER=""
  for candidate_provider in codex claude; do
    if ! command -v "$candidate_provider" >/dev/null 2>&1; then
      continue
    fi

    provider_command_available=true
    inspect_provider_readiness "$candidate_provider"
    if provider_shell_readiness_ok; then
      RESOLVED_PROVIDER="$candidate_provider"
      return 0
    fi
  done

  if [ "$provider_command_available" != "true" ]; then
    reset_provider_state
    PROVIDER_INVENTORY_FAILURE_CODE="PROVIDER_CLI_UNAVAILABLE"
    PROVIDER_INVENTORY_EXIT_CODE=2
  fi
}

sanitize_retry_after() {
  local header_line
  local header_value

  HTTP_RETRY_AFTER_SECONDS=""
  while IFS= read -r header_line || [ -n "$header_line" ]; do
    header_line="${header_line%$'\r'}"
    case "$header_line" in
      [Rr][Ee][Tt][Rr][Yy]-[Aa][Ff][Tt][Ee][Rr]:*)
        header_value="${header_line#*:}"
        while [ "${header_value# }" != "$header_value" ] || [ "${header_value#$'\t'}" != "$header_value" ]; do
          header_value="${header_value# }"
          header_value="${header_value#$'\t'}"
        done
        while [ "${header_value% }" != "$header_value" ] || [ "${header_value%$'\t'}" != "$header_value" ]; do
          header_value="${header_value% }"
          header_value="${header_value%$'\t'}"
        done
        case "$header_value" in
          ''|*[!0-9]*) ;;
          *)
            while [ "${#header_value}" -gt 1 ] && [ "${header_value#0}" != "$header_value" ]; do
              header_value="${header_value#0}"
            done
            if [ "${#header_value}" -le 6 ] && [ "$header_value" -le "$MAX_RETRY_AFTER_SECONDS" ]; then
              HTTP_RETRY_AFTER_SECONDS="$header_value"
            fi
            ;;
        esac
        ;;
      *) ;;
    esac
  done < "$HTTP_HEADERS_FILE"
}

request_http() {
  local url="$1"
  local attempt=1
  local max_attempts=$((MAX_RETRIES + 1))
  local curl_succeeded

  HTTP_STATUS=""
  HTTP_ATTEMPTS=0
  HTTP_TRANSPORT_OK=false
  HTTP_RETRY_AFTER_SECONDS=""
  HTTP_BODY_FILE="$TEMP_DIRECTORY/http-body"
  HTTP_HEADERS_FILE="$TEMP_DIRECTORY/http-headers"

  while [ "$attempt" -le "$max_attempts" ]; do
    : > "$HTTP_BODY_FILE"
    : > "$HTTP_HEADERS_FILE"
    curl_succeeded=false

    if HTTP_STATUS="$(curl \
      --silent \
      --show-error \
      --request GET \
      --proto '=https' \
      --connect-timeout "$CONNECT_TIMEOUT_SECONDS" \
      --max-time "$MAX_TIME_SECONDS" \
      --max-redirs 0 \
      --header 'Accept: application/json' \
      --dump-header "$HTTP_HEADERS_FILE" \
      --output "$HTTP_BODY_FILE" \
      --write-out '%{http_code}' \
      --url "$url" \
      2>/dev/null)"; then
      curl_succeeded=true
    fi

    HTTP_ATTEMPTS="$attempt"
    if [ "$curl_succeeded" = "true" ]; then
      case "$HTTP_STATUS" in
        [0-9][0-9][0-9]) HTTP_TRANSPORT_OK=true ;;
        *) HTTP_TRANSPORT_OK=false ;;
      esac
    else
      HTTP_TRANSPORT_OK=false
      HTTP_STATUS=""
    fi

    if [ "$HTTP_TRANSPORT_OK" != "true" ]; then
      if [ "$attempt" -lt "$max_attempts" ]; then
        attempt=$((attempt + 1))
        continue
      fi
      break
    fi

    case "$HTTP_STATUS" in
      5[0-9][0-9])
        if [ "$attempt" -lt "$max_attempts" ]; then
          attempt=$((attempt + 1))
          continue
        fi
        ;;
      *) ;;
    esac
    break
  done

  if [ "$HTTP_STATUS" = "429" ]; then
    sanitize_retry_after
  fi
}

validate_skill_version_response() {
  local remote_version

  RESPONSE_CONTRACT_OUTCOME="invalid"
  if ! jq -e '
    type == "object" and
    (.up_to_date | type == "boolean") and
    (.update_required | type == "boolean") and
    ((has("version") | not) or ((.version | type == "string") and (.version | length > 0)))
  ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    return 1
  fi

  if jq -e 'has("version")' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    remote_version="$(jq -er '.version' "$HTTP_BODY_FILE")"
    if ! is_strict_semver "$remote_version"; then
      return 1
    fi
  fi

  if jq -e '(.up_to_date == true) and (.update_required == false)' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    RESPONSE_CONTRACT_OUTCOME="valid"
    return 0
  fi

  RESPONSE_CONTRACT_OUTCOME="incompatible"
  return 1
}

validate_response_contract() {
  local response_contract="$1"

  RESPONSE_CONTRACT_OUTCOME="invalid"
  case "$response_contract" in
    ping)
      if jq -eRs 'gsub("^[[:space:]]+|[[:space:]]+$"; "") == "pong"' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
        RESPONSE_CONTRACT_OUTCOME="valid"
        return 0
      fi
      ;;
    skill_version)
      validate_skill_version_response
      return $?
      ;;
    identity)
      if jq -e '
        type == "object" and
        (.caller_id | type == "string") and
        (.caller_id | length > 0) and
        (.ldap | type == "string") and
        (.ldap | length > 0) and
        (.email | type == "string") and
        (.email | length > 0) and
        (.auth_path | type == "string") and
        (.auth_path | length > 0) and
        (.is_public | type == "boolean")
      ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
        RESPONSE_CONTRACT_OUTCOME="valid"
        return 0
      fi
      ;;
    general_read)
      if jq -e '
        type == "object" and
        (.documents | type == "array") and
        all(.documents[]; type == "object")
      ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
        RESPONSE_CONTRACT_OUTCOME="valid"
        return 0
      fi
      ;;
    required_document)
      if jq -e --arg required_document_id "$REQUIRED_DOCUMENT_ID" '
        type == "object" and
        (.doc_id | type == "string") and
        (.doc_id == $required_document_id) and
        (.title | type == "string") and
        (.title | length > 0) and
        (.doc_type | type == "string") and
        (.doc_type | length > 0) and
        (.content_storage == "s3")
      ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
        RESPONSE_CONTRACT_OUTCOME="valid"
        return 0
      fi
      ;;
    *) ;;
  esac

  return 1
}

run_probe() {
  local check_name="$1"
  local url="$2"
  local response_contract
  local default_exit_code
  local default_failure_code
  local forbidden_failure_code
  local not_found_failure_code
  local invalid_json_failure_code
  local identity_on_unauthorized
  local failure_code=""
  local failure_exit_code

  case "$check_name" in
    ping)
      response_contract="ping"
      default_exit_code=20
      default_failure_code="GRID_PING_FAILED"
      forbidden_failure_code="GRID_PING_FORBIDDEN"
      not_found_failure_code="GRID_PING_NOT_FOUND"
      invalid_json_failure_code="GRID_PING_RESPONSE_INVALID"
      identity_on_unauthorized=false
      ;;
    skill_version)
      response_contract="skill_version"
      default_exit_code=21
      default_failure_code="PLUGIN_VERSION_INCOMPATIBLE"
      forbidden_failure_code="PLUGIN_VERSION_FORBIDDEN"
      not_found_failure_code="PLUGIN_VERSION_ENDPOINT_NOT_FOUND"
      invalid_json_failure_code="PLUGIN_VERSION_RESPONSE_INVALID"
      identity_on_unauthorized=true
      ;;
    identity)
      response_contract="identity"
      default_exit_code=22
      default_failure_code="GRID_IDENTITY_UNAVAILABLE"
      forbidden_failure_code="GRID_IDENTITY_FORBIDDEN"
      not_found_failure_code="GRID_IDENTITY_ENDPOINT_NOT_FOUND"
      invalid_json_failure_code="GRID_IDENTITY_RESPONSE_INVALID"
      identity_on_unauthorized=true
      ;;
    general_read)
      response_contract="general_read"
      default_exit_code=23
      default_failure_code="GENERAL_READ_FAILED"
      forbidden_failure_code="GENERAL_READ_FORBIDDEN"
      not_found_failure_code="GENERAL_READ_ENDPOINT_NOT_FOUND"
      invalid_json_failure_code="GENERAL_READ_RESPONSE_INVALID"
      identity_on_unauthorized=true
      ;;
    required_document)
      response_contract="required_document"
      default_exit_code=24
      default_failure_code="REQUIRED_DOCUMENT_READ_FAILED"
      forbidden_failure_code="REQUIRED_DOCUMENT_FORBIDDEN"
      not_found_failure_code="REQUIRED_DOCUMENT_NOT_FOUND"
      invalid_json_failure_code="REQUIRED_DOCUMENT_RESPONSE_INVALID"
      identity_on_unauthorized=true
      ;;
  esac
  failure_exit_code="$default_exit_code"

  LAST_PROBE_OK=false
  LAST_PROBE_FAILURE_CODE=""
  request_http "$url"

  if [ "$HTTP_TRANSPORT_OK" != "true" ]; then
    failure_code="GRID_TRANSPORT_FAILED"
    failure_exit_code=20
  else
    case "$HTTP_STATUS" in
      2[0-9][0-9])
        if validate_response_contract "$response_contract"; then
          append_check "$check_name" true "passed" "" "$HTTP_ATTEMPTS" "$HTTP_STATUS" ""
          LAST_PROBE_OK=true
          return 0
        fi
        if [ "$RESPONSE_CONTRACT_OUTCOME" = "incompatible" ]; then
          failure_code="PLUGIN_VERSION_INCOMPATIBLE"
          failure_exit_code=21
        else
          failure_code="$invalid_json_failure_code"
        fi
        ;;
      401)
        if [ "$identity_on_unauthorized" = "true" ]; then
          failure_code="GRID_IDENTITY_UNAVAILABLE"
          failure_exit_code=22
        else
          failure_code="$default_failure_code"
        fi
        ;;
      403) failure_code="$forbidden_failure_code" ;;
      404) failure_code="$not_found_failure_code" ;;
      429)
        failure_code="GRID_RATE_LIMITED"
        failure_exit_code=25
        ;;
      5[0-9][0-9])
        failure_code="GRID_SERVICE_UNAVAILABLE"
        failure_exit_code=20
        ;;
      *) failure_code="$default_failure_code" ;;
    esac
  fi

  append_check "$check_name" false "failed" "$failure_code" "$HTTP_ATTEMPTS" "$HTTP_STATUS" "$HTTP_RETRY_AFTER_SECONDS"
  record_failure "$failure_code" "$check_name" "$failure_exit_code"
  LAST_PROBE_FAILURE_CODE="$failure_code"
  printf 'check-groot-queue-readiness: %s failed with %s.\n' "$check_name" "$failure_code" >&2
}

append_not_run_check() {
  local check_name="$1"
  local failure_code="$2"

  append_check "$check_name" false "not_run" "$failure_code"
}

parse_arguments "$@"

if ! command -v jq >/dev/null 2>&1; then
  emit_constant_failure 70 "LOCAL_DEPENDENCY_UNAVAILABLE" "dependencies"
fi

if ! command -v curl >/dev/null 2>&1; then
  RESOLVED_PROVIDER=""
  if [ "$REQUESTED_PROVIDER" != "auto" ]; then
    RESOLVED_PROVIDER="$REQUESTED_PROVIDER"
  fi
  RESULT_CHECKED_AT_EPOCH="$(date +%s)"
  append_check "dependencies" false "failed" "LOCAL_DEPENDENCY_UNAVAILABLE"
  record_failure "LOCAL_DEPENDENCY_UNAVAILABLE" "dependencies" 70
  emit_result
fi

RESULT_CHECKED_AT_EPOCH="$(date +%s)"
append_check "dependencies" true "passed"

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE="$SCRIPT_DIRECTORY/../knowledge/config/groot-queue-readiness.json"
CONFIG_JSON=""

if [ -L "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ] \
  || ! CONFIG_JSON="$(jq -ce '.' "$CONFIG_FILE" 2>/dev/null)" \
  || ! validate_configuration "$CONFIG_JSON"; then
  append_check "configuration" false "failed" "CONFIGURATION_INVALID"
  record_failure "CONFIGURATION_INVALID" "configuration" 70
  emit_result
fi

CONFIG_VALUES="$(printf '%s' "$CONFIG_JSON" | jq -er '[
  .schema_version,
  .grid_sharing.plugin.id,
  .grid_sharing.plugin.required_skill_path,
  .grid_sharing.api.base_url,
  .grid_sharing.api.endpoints.ping,
  .grid_sharing.api.endpoints.skill_version,
  .grid_sharing.api.endpoints.identity,
  .grid_sharing.api.endpoints.documents,
  .grid_sharing.required_document.id,
  .grid_sharing.network.connect_timeout_seconds,
  .grid_sharing.network.max_time_seconds,
  .grid_sharing.network.max_retries,
  .fury_services.plugin.id,
  .fury_services.plugin.required_skill_path,
  .fury_services.provider_manifest_paths.claude,
  .fury_services.provider_manifest_paths.codex,
  .fury_services.mcp_manifest_path,
  .fury_services.expected_mcp_server.name,
  .fury_services.expected_mcp_server.command,
  .fury_services.expected_mcp_server.args[0],
  .fury_services.expected_mcp_server.args[1],
  .fury_services.expected_mcp_server.args[2],
  .fury_services.expected_mcp_server.args[3],
  .fury_services.expected_mcp_server.args[4],
  .fury_services.expected_mcp_server.args[5],
  .reuse_result.max_age_seconds
] | @tsv')"
FURY_MCP_ARGS_JSON="$(printf '%s' "$CONFIG_JSON" | jq -ce '.fury_services.expected_mcp_server.args')"
IFS=$'\t' read -r \
  SCHEMA_VERSION \
  GRID_PLUGIN_ID \
  GRID_REQUIRED_SKILL_PATH \
  API_BASE_URL \
  PING_ENDPOINT \
  SKILL_VERSION_ENDPOINT \
  IDENTITY_ENDPOINT \
  DOCUMENTS_ENDPOINT \
  REQUIRED_DOCUMENT_ID \
  CONNECT_TIMEOUT_SECONDS \
  MAX_TIME_SECONDS \
  MAX_RETRIES \
  FURY_PLUGIN_ID \
  FURY_REQUIRED_SKILL_PATH \
  FURY_CLAUDE_MANIFEST_PATH \
  FURY_CODEX_MANIFEST_PATH \
  FURY_MCP_MANIFEST_PATH \
  FURY_MCP_SERVER_NAME \
  FURY_MCP_COMMAND \
  FURY_MCP_ARG_GATEWAY \
  FURY_MCP_ARG_HEADERS_FLAG \
  FURY_MCP_ARG_HEADER_NAME \
  FURY_MCP_ARG_HEADER_VALUE \
  FURY_MCP_ARG_TIMEOUT_FLAG \
  FURY_MCP_ARG_TIMEOUT_VALUE \
  REUSE_RESULT_MAX_AGE_SECONDS <<EOF
$CONFIG_VALUES
EOF
append_check "configuration" true "passed"

if ! create_temp_directory; then
  append_check "runtime" false "failed" "TEMP_DIRECTORY_UNAVAILABLE"
  record_failure "TEMP_DIRECTORY_UNAVAILABLE" "runtime" 70
  emit_result
fi

try_reuse_result || true

reset_provider_state
resolve_provider

if [ "$PROVIDER_INVENTORY_OK" = "true" ]; then
  append_check "provider_inventory" true "passed"
else
  append_check "provider_inventory" false "failed" "$PROVIDER_INVENTORY_FAILURE_CODE"
  record_failure "$PROVIDER_INVENTORY_FAILURE_CODE" "provider_inventory" "$PROVIDER_INVENTORY_EXIT_CODE"
fi

if [ "$PROVIDER_INVENTORY_OK" != "true" ]; then
  append_check "grid_plugin" false "not_run" "$PROVIDER_INVENTORY_FAILURE_CODE"
elif [ "$GRID_PLUGIN_OK" = "true" ]; then
  append_check "grid_plugin" true "passed"
else
  append_check "grid_plugin" false "failed" "$GRID_PLUGIN_FAILURE_CODE"
  record_failure "$GRID_PLUGIN_FAILURE_CODE" "grid_plugin" 10
fi

if [ "$PROVIDER_INVENTORY_OK" != "true" ]; then
  append_check "grid_required_skill" false "not_run" "$PROVIDER_INVENTORY_FAILURE_CODE"
elif [ "$GRID_PLUGIN_OK" != "true" ]; then
  append_check "grid_required_skill" false "not_run" "$GRID_PLUGIN_FAILURE_CODE"
elif [ "$GRID_REQUIRED_SKILL_OK" = "true" ]; then
  append_check "grid_required_skill" true "passed"
else
  append_check "grid_required_skill" false "failed" "REQUIRED_SKILL_UNAVAILABLE"
  record_failure "REQUIRED_SKILL_UNAVAILABLE" "grid_required_skill" 10
fi

if [ "$PROVIDER_INVENTORY_OK" != "true" ]; then
  append_check "fury_plugin" false "not_run" "$PROVIDER_INVENTORY_FAILURE_CODE"
elif [ "$FURY_PLUGIN_OK" = "true" ]; then
  append_check "fury_plugin" true "passed"
else
  append_check "fury_plugin" false "failed" "$FURY_PLUGIN_FAILURE_CODE"
  record_failure "$FURY_PLUGIN_FAILURE_CODE" "fury_plugin" 10
fi

if [ "$PROVIDER_INVENTORY_OK" != "true" ]; then
  append_check "fury_required_skill" false "not_run" "$PROVIDER_INVENTORY_FAILURE_CODE"
elif [ "$FURY_PLUGIN_OK" != "true" ]; then
  append_check "fury_required_skill" false "not_run" "$FURY_PLUGIN_FAILURE_CODE"
elif [ "$FURY_REQUIRED_SKILL_OK" = "true" ]; then
  append_check "fury_required_skill" true "passed"
else
  append_check "fury_required_skill" false "failed" "FURY_REQUIRED_SKILL_UNAVAILABLE"
  record_failure "FURY_REQUIRED_SKILL_UNAVAILABLE" "fury_required_skill" 10
fi

if [ "$PROVIDER_INVENTORY_OK" != "true" ]; then
  append_check "fury_manifest" false "not_run" "$PROVIDER_INVENTORY_FAILURE_CODE"
elif [ "$FURY_PLUGIN_OK" != "true" ]; then
  append_check "fury_manifest" false "not_run" "$FURY_PLUGIN_FAILURE_CODE"
elif [ "$FURY_REQUIRED_SKILL_OK" != "true" ]; then
  append_check "fury_manifest" false "not_run" "FURY_REQUIRED_SKILL_UNAVAILABLE"
elif [ "$FURY_MANIFEST_OK" = "true" ]; then
  append_check "fury_manifest" true "passed"
else
  append_check "fury_manifest" false "failed" "$FURY_MANIFEST_FAILURE_CODE"
  record_failure "$FURY_MANIFEST_FAILURE_CODE" "fury_manifest" 10
fi

if [ "$PROVIDER_INVENTORY_OK" != "true" ]; then
  append_check "fury_mcp_declaration" false "not_run" "$PROVIDER_INVENTORY_FAILURE_CODE"
elif [ "$FURY_PLUGIN_OK" != "true" ]; then
  append_check "fury_mcp_declaration" false "not_run" "$FURY_PLUGIN_FAILURE_CODE"
elif [ "$FURY_REQUIRED_SKILL_OK" != "true" ]; then
  append_check "fury_mcp_declaration" false "not_run" "FURY_REQUIRED_SKILL_UNAVAILABLE"
elif [ "$FURY_MANIFEST_OK" != "true" ]; then
  append_check "fury_mcp_declaration" false "not_run" "$FURY_MANIFEST_FAILURE_CODE"
elif [ "$FURY_MCP_DECLARATION_OK" = "true" ]; then
  append_check "fury_mcp_declaration" true "passed"
else
  append_check "fury_mcp_declaration" false "failed" "$FURY_MCP_DECLARATION_FAILURE_CODE"
  record_failure "$FURY_MCP_DECLARATION_FAILURE_CODE" "fury_mcp_declaration" 10
fi

if [ "$PROVIDER_INVENTORY_OK" != "true" ]; then
  append_check "fury_mcp_cli" false "not_run" "$PROVIDER_INVENTORY_FAILURE_CODE"
elif [ "$FURY_PLUGIN_OK" != "true" ]; then
  append_check "fury_mcp_cli" false "not_run" "$FURY_PLUGIN_FAILURE_CODE"
elif [ "$FURY_REQUIRED_SKILL_OK" != "true" ]; then
  append_check "fury_mcp_cli" false "not_run" "FURY_REQUIRED_SKILL_UNAVAILABLE"
elif [ "$FURY_MANIFEST_OK" != "true" ]; then
  append_check "fury_mcp_cli" false "not_run" "$FURY_MANIFEST_FAILURE_CODE"
elif [ "$FURY_MCP_DECLARATION_OK" != "true" ]; then
  append_check "fury_mcp_cli" false "not_run" "$FURY_MCP_DECLARATION_FAILURE_CODE"
elif [ "$FURY_MCP_CLI_OK" = "true" ]; then
  append_check "fury_mcp_cli" true "passed"
else
  append_check "fury_mcp_cli" false "failed" "$FURY_MCP_CLI_FAILURE_CODE"
  record_failure "$FURY_MCP_CLI_FAILURE_CODE" "fury_mcp_cli" 10
fi

GRID_PLUGIN_VERSION_VALID=false
ENCODED_GRID_PLUGIN_VERSION=""
if [ -n "$GRID_PLUGIN_VERSION" ] && is_strict_semver "$GRID_PLUGIN_VERSION"; then
  GRID_PLUGIN_VERSION_VALID=true
  ENCODED_GRID_PLUGIN_VERSION="$(jq -nr --arg version "$GRID_PLUGIN_VERSION" '$version | @uri')"
fi

if ! provider_shell_readiness_ok; then
  LOCAL_READINESS_FAILURE_CODE="$(printf '%s' "$FAILURES_JSON" | jq -er '.[0].code // empty' 2>/dev/null || true)"
  if [ -z "$LOCAL_READINESS_FAILURE_CODE" ]; then
    LOCAL_READINESS_FAILURE_CODE="PLUGIN_VERSION_INVALID"
  fi

  append_not_run_check "ping" "$LOCAL_READINESS_FAILURE_CODE"
  if [ "$GRID_PLUGIN_OK" = "true" ] && [ "$GRID_REQUIRED_SKILL_OK" = "true" ] \
    && [ "$GRID_PLUGIN_VERSION_VALID" != "true" ]; then
    append_check "skill_version" false "failed" "PLUGIN_VERSION_INVALID"
    record_failure "PLUGIN_VERSION_INVALID" "skill_version" 21
  else
    append_not_run_check "skill_version" "$LOCAL_READINESS_FAILURE_CODE"
  fi
  append_not_run_check "identity" "$LOCAL_READINESS_FAILURE_CODE"
  append_not_run_check "general_read" "$LOCAL_READINESS_FAILURE_CODE"
  append_not_run_check "required_document" "$LOCAL_READINESS_FAILURE_CODE"
  emit_result
fi

run_probe "ping" "$API_BASE_URL$PING_ENDPOINT"

if [ "$LAST_PROBE_OK" != "true" ]; then
  if [ "$GRID_PLUGIN_VERSION_VALID" = "true" ]; then
    append_not_run_check "skill_version" "$LAST_PROBE_FAILURE_CODE"
  elif [ -n "$GRID_PLUGIN_VERSION" ]; then
    append_check "skill_version" false "failed" "PLUGIN_VERSION_INVALID"
    record_failure "PLUGIN_VERSION_INVALID" "skill_version" 21
  else
    append_check "skill_version" false "not_run" "PLUGIN_VERSION_UNAVAILABLE"
  fi
  append_not_run_check "identity" "$LAST_PROBE_FAILURE_CODE"
  append_not_run_check "general_read" "$LAST_PROBE_FAILURE_CODE"
  append_not_run_check "required_document" "$LAST_PROBE_FAILURE_CODE"
  emit_result
fi

if [ "$GRID_PLUGIN_VERSION_VALID" = "true" ]; then
  run_probe "skill_version" "$API_BASE_URL$SKILL_VERSION_ENDPOINT?current_version=$ENCODED_GRID_PLUGIN_VERSION"
else
  if [ -n "$GRID_PLUGIN_VERSION" ]; then
    append_check "skill_version" false "failed" "PLUGIN_VERSION_INVALID"
    record_failure "PLUGIN_VERSION_INVALID" "skill_version" 21
  else
    append_check "skill_version" false "not_run" "PLUGIN_VERSION_UNAVAILABLE"
  fi
  LAST_PROBE_OK=false
  LAST_PROBE_FAILURE_CODE="PLUGIN_VERSION_UNAVAILABLE"
fi

if [ "$LAST_PROBE_FAILURE_CODE" = "GRID_RATE_LIMITED" ]; then
  append_not_run_check "identity" "GRID_RATE_LIMITED"
  append_not_run_check "general_read" "GRID_RATE_LIMITED"
  append_not_run_check "required_document" "GRID_RATE_LIMITED"
  emit_result
fi

run_probe "identity" "$API_BASE_URL$IDENTITY_ENDPOINT"

if [ "$LAST_PROBE_OK" != "true" ]; then
  append_not_run_check "general_read" "$LAST_PROBE_FAILURE_CODE"
  append_not_run_check "required_document" "$LAST_PROBE_FAILURE_CODE"
  emit_result
fi

run_probe "general_read" "$API_BASE_URL$DOCUMENTS_ENDPOINT?scope=owned&limit=1"

if [ "$LAST_PROBE_FAILURE_CODE" = "GRID_RATE_LIMITED" ]; then
  append_not_run_check "required_document" "GRID_RATE_LIMITED"
  emit_result
fi

run_probe "required_document" "$API_BASE_URL$DOCUMENTS_ENDPOINT/$REQUIRED_DOCUMENT_ID"

emit_result
