#!/bin/bash

set -euo pipefail
umask 077

readonly FALLBACK_SCHEMA_VERSION=1
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
    printf '%s\n' '{"schema_version":1,"provider":null,"ok":false,"exit_code":70,"active_context":null,"source":"fresh","checked_at_epoch":null,"checks":[{"name":"internal_contract","ok":false,"status":"failed","failure_code":"INTERNAL_CONTRACT_FAILED","attempts":null,"http_status":null,"retry_after_seconds":null}],"failures":[{"code":"INTERNAL_CONTRACT_FAILED","check":"internal_contract","exit_code":70}]}'
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
  printf '{"schema_version":1,"provider":null,"ok":false,"exit_code":%s,"active_context":null,"source":"fresh","checked_at_epoch":null,"checks":[{"name":"%s","ok":false,"status":"failed","failure_code":"%s","attempts":null,"http_status":null,"retry_after_seconds":null}],"failures":[{"code":"%s","check":"%s","exit_code":%s}]}\n' \
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

  CHECKS_JSON="$({
    printf '%s' "$CHECKS_JSON"
  } | jq -c \
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

  FAILURES_JSON="$({
    printf '%s' "$FAILURES_JSON"
  } | jq -c \
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
  local provider_json
  local result_json

  if [ "$SELECTED_EXIT_CODE" -eq 0 ]; then
    result_ok=true
  fi

  if [ -n "$RESOLVED_PROVIDER" ]; then
    provider_json="$(jq -nc --arg provider "$RESOLVED_PROVIDER" '$provider')"
  else
    provider_json='null'
  fi

  if [ -z "$RESULT_CHECKED_AT_EPOCH" ]; then
    RESULT_CHECKED_AT_EPOCH="$(date +%s)"
  fi

  result_json="$(jq -nc \
    --argjson schema_version "$SCHEMA_VERSION" \
    --argjson provider "$provider_json" \
    --argjson ok "$result_ok" \
    --argjson exit_code "$SELECTED_EXIT_CODE" \
    --arg source "$RESULT_SOURCE" \
    --argjson checked_at_epoch "$RESULT_CHECKED_AT_EPOCH" \
    --argjson checks "$CHECKS_JSON" \
    --argjson failures "$FAILURES_JSON" \
    '{
      schema_version: $schema_version,
      provider: $provider,
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
  jq -e '
    . as $config |
    type == "object" and
    ($config.schema_version | type == "number") and
    ($config.schema_version == ($config.schema_version | floor)) and
    ($config.schema_version >= 1) and
    ($config.plugin.id | type == "string") and
    ($config.plugin.id | test("^[a-z0-9-]+@[a-z0-9-]+$")) and
    ($config.plugin.required_skill_path | type == "string") and
    ($config.plugin.required_skill_path | test("^[A-Za-z0-9._/-]+$")) and
    (($config.plugin.required_skill_path | startswith("/")) | not) and
    (($config.plugin.required_skill_path | split("/") | index("..")) == null) and
    ($config.api.base_url | type == "string") and
    ($config.api.base_url | test("^https://[A-Za-z0-9.-]+$")) and
    ($config.api.endpoints | type == "object") and
    (($config.api.endpoints | keys | sort) == ["document", "documents", "identity", "ping", "skill_version"]) and
    all($config.api.endpoints[]; (type == "string") and test("^/[A-Za-z0-9/_-]+$")) and
    ($config.required_document.name | type == "string") and
    ($config.required_document.id | type == "string") and
    ($config.required_document.id | test("^[A-Z0-9]+$")) and
    ($config.required_document.viewer_url | type == "string") and
    ($config.required_document.viewer_url | test("^https://[A-Za-z0-9.-]+/d/[A-Z0-9]+/view$")) and
    ($config.required_document.viewer_url | endswith("/d/" + $config.required_document.id + "/view")) and
    ($config.network.connect_timeout_seconds | type == "number") and
    ($config.network.connect_timeout_seconds == ($config.network.connect_timeout_seconds | floor)) and
    ($config.network.connect_timeout_seconds > 0) and
    ($config.network.connect_timeout_seconds <= 60) and
    ($config.network.max_time_seconds | type == "number") and
    ($config.network.max_time_seconds == ($config.network.max_time_seconds | floor)) and
    ($config.network.max_time_seconds >= $config.network.connect_timeout_seconds) and
    ($config.network.max_time_seconds <= 120) and
    ($config.network.max_retries | type == "number") and
    ($config.network.max_retries == ($config.network.max_retries | floor)) and
    (($config.network.max_retries == 0) or ($config.network.max_retries == 1)) and
    ($config.reuse_result.max_age_seconds | type == "number") and
    ($config.reuse_result.max_age_seconds == ($config.reuse_result.max_age_seconds | floor)) and
    ($config.reuse_result.max_age_seconds > 0) and
    ($config.reuse_result.max_age_seconds <= 3600)
  ' "$CONFIG_FILE" >/dev/null 2>&1
}

create_temp_directory() {
  if TEMP_DIRECTORY="$(mktemp -d -t groot-grid-preflight.XXXXXX 2>/dev/null)"; then
    return 0
  fi

  if TEMP_DIRECTORY="$(mktemp -d /tmp/groot-grid-preflight.XXXXXX 2>/dev/null)"; then
    return 0
  fi

  return 1
}

get_file_owner() {
  local file_path="$1"

  if stat -f '%u' "$file_path" >/dev/null 2>&1; then
    stat -f '%u' "$file_path" 2>/dev/null
    return 0
  fi

  if stat -c '%u' "$file_path" >/dev/null 2>&1; then
    stat -c '%u' "$file_path" 2>/dev/null
    return 0
  fi

  return 1
}

get_file_mode() {
  local file_path="$1"

  if stat -f '%Lp' "$file_path" >/dev/null 2>&1; then
    stat -f '%Lp' "$file_path" 2>/dev/null
    return 0
  fi

  if stat -c '%a' "$file_path" >/dev/null 2>&1; then
    stat -c '%a' "$file_path" 2>/dev/null
    return 0
  fi

  return 1
}

reuse_file_is_secure() {
  local file_path="$1"
  local file_owner
  local file_mode
  local file_mode_decimal
  local current_user_id

  if [ -L "$file_path" ] || [ ! -f "$file_path" ] || [ ! -r "$file_path" ]; then
    return 1
  fi

  if ! file_owner="$(get_file_owner "$file_path")"; then
    return 1
  fi

  current_user_id="$(id -u)"
  if [ "$file_owner" != "$current_user_id" ]; then
    return 1
  fi

  if ! file_mode="$(get_file_mode "$file_path")"; then
    return 1
  fi

  case "$file_mode" in
    ''|*[!0-7]*) return 1 ;;
    *) ;;
  esac

  file_mode_decimal=$((8#$file_mode))
  if [ $((file_mode_decimal & 36)) -ne 0 ]; then
    return 1
  fi

  return 0
}

try_reuse_result() {
  local current_epoch
  local reused_provider

  if [ -z "$REUSE_RESULT_FILE" ]; then
    return 1
  fi

  if ! reuse_file_is_secure "$REUSE_RESULT_FILE"; then
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
      ($result.schema_version == $schema_version) and
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
      (($result.checks | map(.name)) == ["dependencies", "configuration", "provider_inventory", "required_skill", "ping", "skill_version", "identity", "general_read", "required_document"]) and
      all($result.checks[];
        (type == "object") and
        (.ok == true) and
        (.status == "passed") and
        (.failure_code == null) and
        ((.attempts == null) or ((.attempts | type == "number") and (.attempts >= 1))) and
        ((.http_status == null) or ((.http_status | type == "number") and (.http_status >= 100) and (.http_status <= 599))) and
        ((.retry_after_seconds == null) or ((.retry_after_seconds | type == "number") and (.retry_after_seconds >= 0) and (.retry_after_seconds <= 86400)))
      )
    ' < "$REUSE_RESULT_FILE" >/dev/null 2>&1; then
    printf '%s\n' 'check-groot-queue-readiness: REUSE_RESULT_REJECTED; running a fresh preflight.' >&2
    return 1
  fi

  reused_provider="$(jq -er '.provider' < "$REUSE_RESULT_FILE")"
  RESOLVED_PROVIDER="$reused_provider"
  RESULT_SOURCE="reused"
  RESULT_CHECKED_AT_EPOCH="$(jq -er '.checked_at_epoch' < "$REUSE_RESULT_FILE")"
  CHECKS_JSON="$(jq -c '[.checks[] | {
    name,
    ok,
    status,
    failure_code,
    attempts,
    http_status,
    retry_after_seconds
  }]' < "$REUSE_RESULT_FILE")"
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

reset_inventory_state() {
  INVENTORY_OK=false
  REQUIRED_SKILL_OK=false
  INVENTORY_FAILURE_CODE=""
  INVENTORY_EXIT_CODE=10
  PLUGIN_VERSION=""
  PLUGIN_INSTALL_PATH=""
}

inspect_provider_inventory() {
  local provider="$1"
  local inventory_file="$TEMP_DIRECTORY/${provider}-inventory.json"
  local plugin_count
  local plugin_enabled
  local plugin_installed
  local required_skill_file

  reset_inventory_state

  if [ "$provider" = "copilot" ]; then
    INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_UNSUPPORTED"
    INVENTORY_EXIT_CODE=2
    return 0
  fi

  if ! command -v "$provider" >/dev/null 2>&1; then
    INVENTORY_FAILURE_CODE="PROVIDER_CLI_UNAVAILABLE"
    INVENTORY_EXIT_CODE=2
    return 0
  fi

  case "$provider" in
    claude)
      if ! claude plugin list --json > "$inventory_file" 2>/dev/null; then
        INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_FAILED"
        return 0
      fi

      if ! jq -e 'type == "array" and all(.[]; type == "object")' "$inventory_file" >/dev/null 2>&1; then
        INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_INVALID"
        return 0
      fi

      plugin_count="$(jq -r --arg plugin_id "$PLUGIN_ID" '[.[] | select(.id == $plugin_id)] | length' "$inventory_file")"
      if [ "$plugin_count" -eq 0 ]; then
        INVENTORY_FAILURE_CODE="PLUGIN_NOT_INSTALLED"
        return 0
      fi
      if [ "$plugin_count" -ne 1 ]; then
        INVENTORY_FAILURE_CODE="PLUGIN_INVENTORY_AMBIGUOUS"
        return 0
      fi

      plugin_enabled="$(jq -r --arg plugin_id "$PLUGIN_ID" '[.[] | select(.id == $plugin_id)][0].enabled' "$inventory_file")"
      if [ "$plugin_enabled" != "true" ]; then
        INVENTORY_FAILURE_CODE="PLUGIN_DISABLED"
        return 0
      fi

      if ! jq -e --arg plugin_id "$PLUGIN_ID" '
        [.[] | select(.id == $plugin_id)][0] as $plugin |
        ($plugin.version | type == "string") and
        ($plugin.version | length > 0) and
        ($plugin.installPath | type == "string") and
        ($plugin.installPath | startswith("/")) and
        (($plugin.installPath | test("[[:cntrl:]]")) | not)
      ' "$inventory_file" >/dev/null 2>&1; then
        INVENTORY_FAILURE_CODE="PLUGIN_INVENTORY_INVALID"
        return 0
      fi

      PLUGIN_VERSION="$(jq -er --arg plugin_id "$PLUGIN_ID" '[.[] | select(.id == $plugin_id)][0].version' "$inventory_file")"
      PLUGIN_INSTALL_PATH="$(jq -er --arg plugin_id "$PLUGIN_ID" '[.[] | select(.id == $plugin_id)][0].installPath' "$inventory_file")"
      ;;
    codex)
      if ! codex plugin list --marketplace tech-plugins-marketplace --json > "$inventory_file" 2>/dev/null; then
        INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_FAILED"
        return 0
      fi

      if ! jq -e 'type == "object" and (.installed | type == "array") and all(.installed[]; type == "object")' "$inventory_file" >/dev/null 2>&1; then
        INVENTORY_FAILURE_CODE="PROVIDER_INVENTORY_INVALID"
        return 0
      fi

      plugin_count="$(jq -r --arg plugin_id "$PLUGIN_ID" '[.installed[] | select(.pluginId == $plugin_id)] | length' "$inventory_file")"
      if [ "$plugin_count" -eq 0 ]; then
        INVENTORY_FAILURE_CODE="PLUGIN_NOT_INSTALLED"
        return 0
      fi
      if [ "$plugin_count" -ne 1 ]; then
        INVENTORY_FAILURE_CODE="PLUGIN_INVENTORY_AMBIGUOUS"
        return 0
      fi

      plugin_installed="$(jq -r --arg plugin_id "$PLUGIN_ID" '[.installed[] | select(.pluginId == $plugin_id)][0].installed' "$inventory_file")"
      plugin_enabled="$(jq -r --arg plugin_id "$PLUGIN_ID" '[.installed[] | select(.pluginId == $plugin_id)][0].enabled' "$inventory_file")"
      if [ "$plugin_installed" != "true" ]; then
        INVENTORY_FAILURE_CODE="PLUGIN_NOT_INSTALLED"
        return 0
      fi
      if [ "$plugin_enabled" != "true" ]; then
        INVENTORY_FAILURE_CODE="PLUGIN_DISABLED"
        return 0
      fi

      if ! jq -e --arg plugin_id "$PLUGIN_ID" '
        [.installed[] | select(.pluginId == $plugin_id)][0] as $plugin |
        ($plugin.version | type == "string") and
        ($plugin.version | length > 0) and
        ($plugin.source.path | type == "string") and
        ($plugin.source.path | startswith("/")) and
        (($plugin.source.path | test("[[:cntrl:]]")) | not)
      ' "$inventory_file" >/dev/null 2>&1; then
        INVENTORY_FAILURE_CODE="PLUGIN_INVENTORY_INVALID"
        return 0
      fi

      PLUGIN_VERSION="$(jq -er --arg plugin_id "$PLUGIN_ID" '[.installed[] | select(.pluginId == $plugin_id)][0].version' "$inventory_file")"
      PLUGIN_INSTALL_PATH="$(jq -er --arg plugin_id "$PLUGIN_ID" '[.installed[] | select(.pluginId == $plugin_id)][0].source.path' "$inventory_file")"
      ;;
  esac

  INVENTORY_OK=true
  required_skill_file="${PLUGIN_INSTALL_PATH%/}/$REQUIRED_SKILL_PATH"
  if [ -f "$required_skill_file" ] && [ -r "$required_skill_file" ]; then
    REQUIRED_SKILL_OK=true
  fi
}

resolve_provider() {
  local candidate_provider
  local provider_command_available=false
  local fallback_provider=""
  local fallback_version=""
  local fallback_install_path=""

  if [ "$REQUESTED_PROVIDER" != "auto" ]; then
    RESOLVED_PROVIDER="$REQUESTED_PROVIDER"
    inspect_provider_inventory "$RESOLVED_PROVIDER"
    return 0
  fi

  for candidate_provider in codex claude; do
    if ! command -v "$candidate_provider" >/dev/null 2>&1; then
      continue
    fi

    provider_command_available=true
    inspect_provider_inventory "$candidate_provider"

    if [ "$INVENTORY_OK" = "true" ] && [ "$REQUIRED_SKILL_OK" = "true" ]; then
      if is_strict_semver "$PLUGIN_VERSION"; then
        RESOLVED_PROVIDER="$candidate_provider"
        return 0
      fi

      if [ -z "$fallback_provider" ]; then
        fallback_provider="$candidate_provider"
        fallback_version="$PLUGIN_VERSION"
        fallback_install_path="$PLUGIN_INSTALL_PATH"
      fi
    fi
  done

  if [ -n "$fallback_provider" ]; then
    RESOLVED_PROVIDER="$fallback_provider"
    INVENTORY_OK=true
    REQUIRED_SKILL_OK=true
    INVENTORY_FAILURE_CODE=""
    INVENTORY_EXIT_CODE=10
    PLUGIN_VERSION="$fallback_version"
    PLUGIN_INSTALL_PATH="$fallback_install_path"
    return 0
  fi

  reset_inventory_state
  if [ "$provider_command_available" = "true" ]; then
    INVENTORY_FAILURE_CODE="NO_VERIFIABLE_PROVIDER"
    INVENTORY_EXIT_CODE=10
  else
    INVENTORY_FAILURE_CODE="PROVIDER_CLI_UNAVAILABLE"
    INVENTORY_EXIT_CODE=2
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
  local curl_error_file="$TEMP_DIRECTORY/curl-error"

  while [ "$attempt" -le "$max_attempts" ]; do
    : > "$HTTP_BODY_FILE"
    : > "$HTTP_HEADERS_FILE"
    : > "$curl_error_file"
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
      2> "$curl_error_file")"; then
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
  local response_contract="$3"
  local default_exit_code="$4"
  local default_failure_code="$5"
  local forbidden_failure_code="$6"
  local not_found_failure_code="$7"
  local invalid_json_failure_code="$8"
  local identity_on_unauthorized="$9"
  local failure_code=""
  local failure_exit_code="$default_exit_code"

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
CONFIG_FILE="$SCRIPT_DIRECTORY/../knowledge/config/grid-sharing.json"

if [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ] || ! validate_configuration; then
  append_check "configuration" false "failed" "CONFIGURATION_INVALID"
  record_failure "CONFIGURATION_INVALID" "configuration" 70
  emit_result
fi

SCHEMA_VERSION="$(jq -er '.schema_version' "$CONFIG_FILE")"
PLUGIN_ID="$(jq -er '.plugin.id' "$CONFIG_FILE")"
REQUIRED_SKILL_PATH="$(jq -er '.plugin.required_skill_path' "$CONFIG_FILE")"
API_BASE_URL="$(jq -er '.api.base_url' "$CONFIG_FILE")"
PING_ENDPOINT="$(jq -er '.api.endpoints.ping' "$CONFIG_FILE")"
SKILL_VERSION_ENDPOINT="$(jq -er '.api.endpoints.skill_version' "$CONFIG_FILE")"
IDENTITY_ENDPOINT="$(jq -er '.api.endpoints.identity' "$CONFIG_FILE")"
DOCUMENTS_ENDPOINT="$(jq -er '.api.endpoints.documents' "$CONFIG_FILE")"
DOCUMENT_ENDPOINT="$(jq -er '.api.endpoints.document' "$CONFIG_FILE")"
REQUIRED_DOCUMENT_ID="$(jq -er '.required_document.id' "$CONFIG_FILE")"
CONNECT_TIMEOUT_SECONDS="$(jq -er '.network.connect_timeout_seconds' "$CONFIG_FILE")"
MAX_TIME_SECONDS="$(jq -er '.network.max_time_seconds' "$CONFIG_FILE")"
MAX_RETRIES="$(jq -er '.network.max_retries' "$CONFIG_FILE")"
REUSE_RESULT_MAX_AGE_SECONDS="$(jq -er '.reuse_result.max_age_seconds' "$CONFIG_FILE")"
append_check "configuration" true "passed"

if ! create_temp_directory; then
  append_check "runtime" false "failed" "TEMP_DIRECTORY_UNAVAILABLE"
  record_failure "TEMP_DIRECTORY_UNAVAILABLE" "runtime" 70
  emit_result
fi

try_reuse_result || true

INVENTORY_OK=false
REQUIRED_SKILL_OK=false
INVENTORY_FAILURE_CODE=""
INVENTORY_EXIT_CODE=10
PLUGIN_VERSION=""
PLUGIN_INSTALL_PATH=""
resolve_provider

if [ "$INVENTORY_OK" = "true" ]; then
  append_check "provider_inventory" true "passed"
else
  append_check "provider_inventory" false "failed" "$INVENTORY_FAILURE_CODE"
  record_failure "$INVENTORY_FAILURE_CODE" "provider_inventory" "$INVENTORY_EXIT_CODE"
fi

if [ "$INVENTORY_OK" != "true" ]; then
  append_check "required_skill" false "not_run" "PLUGIN_INVENTORY_UNAVAILABLE"
elif [ "$REQUIRED_SKILL_OK" = "true" ]; then
  append_check "required_skill" true "passed"
else
  append_check "required_skill" false "failed" "REQUIRED_SKILL_UNAVAILABLE"
  record_failure "REQUIRED_SKILL_UNAVAILABLE" "required_skill" 10
fi

PLUGIN_VERSION_VALID=false
ENCODED_PLUGIN_VERSION=""
if [ -n "$PLUGIN_VERSION" ] && is_strict_semver "$PLUGIN_VERSION"; then
  PLUGIN_VERSION_VALID=true
  ENCODED_PLUGIN_VERSION="$(jq -nr --arg version "$PLUGIN_VERSION" '$version | @uri')"
fi

run_probe \
  "ping" \
  "$API_BASE_URL$PING_ENDPOINT" \
  "ping" \
  20 \
  "GRID_PING_FAILED" \
  "GRID_PING_FORBIDDEN" \
  "GRID_PING_NOT_FOUND" \
  "GRID_PING_RESPONSE_INVALID" \
  "false"

if [ "$LAST_PROBE_OK" != "true" ]; then
  if [ "$PLUGIN_VERSION_VALID" = "true" ]; then
    append_not_run_check "skill_version" "$LAST_PROBE_FAILURE_CODE"
  elif [ -n "$PLUGIN_VERSION" ]; then
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

if [ "$PLUGIN_VERSION_VALID" = "true" ]; then
  run_probe \
    "skill_version" \
    "$API_BASE_URL$SKILL_VERSION_ENDPOINT?current_version=$ENCODED_PLUGIN_VERSION" \
    "skill_version" \
    21 \
    "PLUGIN_VERSION_INCOMPATIBLE" \
    "PLUGIN_VERSION_FORBIDDEN" \
    "PLUGIN_VERSION_ENDPOINT_NOT_FOUND" \
    "PLUGIN_VERSION_RESPONSE_INVALID" \
    "true"
else
  if [ -n "$PLUGIN_VERSION" ]; then
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

run_probe \
  "identity" \
  "$API_BASE_URL$IDENTITY_ENDPOINT" \
  "identity" \
  22 \
  "GRID_IDENTITY_UNAVAILABLE" \
  "GRID_IDENTITY_FORBIDDEN" \
  "GRID_IDENTITY_ENDPOINT_NOT_FOUND" \
  "GRID_IDENTITY_RESPONSE_INVALID" \
  "true"

if [ "$LAST_PROBE_OK" != "true" ]; then
  append_not_run_check "general_read" "$LAST_PROBE_FAILURE_CODE"
  append_not_run_check "required_document" "$LAST_PROBE_FAILURE_CODE"
  emit_result
fi

run_probe \
  "general_read" \
  "$API_BASE_URL$DOCUMENTS_ENDPOINT?scope=owned&limit=1" \
  "general_read" \
  23 \
  "GENERAL_READ_FAILED" \
  "GENERAL_READ_FORBIDDEN" \
  "GENERAL_READ_ENDPOINT_NOT_FOUND" \
  "GENERAL_READ_RESPONSE_INVALID" \
  "true"

if [ "$LAST_PROBE_FAILURE_CODE" = "GRID_RATE_LIMITED" ]; then
  append_not_run_check "required_document" "GRID_RATE_LIMITED"
  emit_result
fi

run_probe \
  "required_document" \
  "$API_BASE_URL$DOCUMENT_ENDPOINT/$REQUIRED_DOCUMENT_ID" \
  "required_document" \
  24 \
  "REQUIRED_DOCUMENT_READ_FAILED" \
  "REQUIRED_DOCUMENT_FORBIDDEN" \
  "REQUIRED_DOCUMENT_NOT_FOUND" \
  "REQUIRED_DOCUMENT_RESPONSE_INVALID" \
  "true"

emit_result
