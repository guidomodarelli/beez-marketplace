#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE="$SCRIPT_DIRECTORY/../knowledge/config/labor-share-data.json"
TEMP_DIRECTORY=""
HTTP_BODY_FILE=""
HTTP_STATUS=""
HTTP_ATTEMPTS=0
HTTP_OUTCOME=""

usage() {
  cat <<'USAGE'
Usage:
  query-labor-share-data.sh execution --labor-share-id <id> [--labor-share-id <id> ...]
  query-labor-share-data.sh processes --facility-type <WAREHOUSE|SC|XD> [--facility-type <type> ...]
USAGE
}

cleanup() {
  local cleanup_status=$?
  trap - EXIT INT TERM
  if [ -n "$TEMP_DIRECTORY" ] && [ -d "$TEMP_DIRECTORY" ]; then
    rm -rf -- "$TEMP_DIRECTORY"
  fi
  exit "$cleanup_status"
}

emit_result() {
  local operation="$1"
  local status="$2"
  local facts_json="$3"
  local source_status="$4"
  local warnings_json="$5"

  jq -cn \
    --arg operation "$operation" \
    --arg status "$status" \
    --arg source_status "$source_status" \
    --argjson attempts "$HTTP_ATTEMPTS" \
    --argjson facts "$facts_json" \
    --argjson warnings "$warnings_json" \
    '{
      schema_version: 1,
      operation: $operation,
      status: $status,
      resource_fingerprint: "redacted",
      facts: $facts,
      source_results: [{
        source: "shipping_users_mgmt_api",
        status: $source_status,
        attempts: $attempts
      }],
      warnings: $warnings
    }'
}

emit_indeterminate() {
  local operation="$1"
  local warning="$2"
  emit_result "$operation" "indeterminate" '{}' "indeterminate" "$(jq -cn --arg warning "$warning" '[$warning]')"
}

validate_configuration() {
  jq -e '
    .schema_version == 1 and
    .api.base_url == "https://prod--shipping-users-mgmt-api.legacy.furyapps.io" and
    (.api.endpoints | keys == ["execution", "processes"]) and
    .api.endpoints.execution == {
      "method": "GET",
      "path": "/management/v1/labor-share/{labor_share_id}"
    } and
    .api.endpoints.processes == {
      "method": "GET",
      "path": "/management/v1/labor-share/process/{facility_type}"
    } and
    (.network.connect_timeout_seconds | type == "number" and . >= 1 and . <= 30) and
    (.network.max_time_seconds | type == "number" and . >= 1 and . <= 60) and
    (.network.max_get_retries | type == "number" and (. % 1) == 0 and . >= 0 and . <= 1) and
    (.network.max_response_bytes | type == "number" and (. % 1) == 0 and . >= 1024 and . <= 1048576) and
    (.limits.max_safe_integer == 9007199254740991) and
    (.limits.max_identifier_length | type == "number" and (. % 1) == 0 and . >= 1 and . <= 16) and
    (.limits.max_assignments | type == "number" and (. % 1) == 0 and . >= 1 and . <= 1000) and
    (.limits.max_processes | type == "number" and (. % 1) == 0 and . >= 1 and . <= 500) and
    (.limits.max_sub_processes_per_process | type == "number" and (. % 1) == 0 and . >= 1 and . <= 500) and
    (.limits.max_description_length | type == "number" and (. % 1) == 0 and . >= 1 and . <= 500) and
    .allowed_facility_types == ["WAREHOUSE", "SC", "XD"]
  ' "$CONFIG_FILE" >/dev/null 2>&1
}

canonicalize_identifier() {
  local candidate="$1"
  local canonical="$candidate"

  while [ "${#canonical}" -gt 1 ] && [ "${canonical#0}" != "$canonical" ]; do
    canonical="${canonical#0}"
  done
  printf '%s' "$canonical"
}

validate_identifier() {
  local candidate="$1"

  case "$candidate" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "${#candidate}" -le "$MAX_IDENTIFIER_LENGTH" ] || return 1

  local canonical
  canonical="$(canonicalize_identifier "$candidate")"
  [ "$canonical" != "0" ] || return 1
  [ "${#canonical}" -lt "${#MAX_SAFE_INTEGER}" ] \
    || { [ "${#canonical}" -eq "${#MAX_SAFE_INTEGER}" ] && [[ "$canonical" < "$MAX_SAFE_INTEGER" || "$canonical" == "$MAX_SAFE_INTEGER" ]]; }
}

normalize_identifier_candidates() {
  local candidate
  local canonical
  local normalized='[]'

  for candidate in "$@"; do
    if ! validate_identifier "$candidate"; then
      return 1
    fi
    canonical="$(canonicalize_identifier "$candidate")"
    normalized="$(jq -cn --argjson current "$normalized" --arg value "$canonical" '$current + [$value] | unique')"
  done

  [ "$(jq 'length' <<< "$normalized")" -eq 1 ] || return 2
  jq -r '.[0]' <<< "$normalized"
}

normalize_facility_candidates() {
  local candidate
  local normalized='[]'

  for candidate in "$@"; do
    if ! jq -e --arg candidate "$candidate" '.allowed_facility_types | index($candidate) != null' "$CONFIG_FILE" >/dev/null; then
      return 1
    fi
    normalized="$(jq -cn --argjson current "$normalized" --arg value "$candidate" '$current + [$value] | unique')"
  done

  [ "$(jq 'length' <<< "$normalized")" -eq 1 ] || return 2
  jq -r '.[0]' <<< "$normalized"
}

request_http() {
  local url="$1"
  local attempt=1
  local max_attempts=$((MAX_GET_RETRIES + 1))
  local curl_exit

  HTTP_BODY_FILE="$TEMP_DIRECTORY/response-body"
  HTTP_STATUS=""
  HTTP_ATTEMPTS=0
  HTTP_OUTCOME=""

  while [ "$attempt" -le "$max_attempts" ]; do
    : > "$HTTP_BODY_FILE"
    set +e
    HTTP_STATUS="$(curl \
      --silent \
      --show-error \
      --fail-with-body \
      --request GET \
      --proto '=https' \
      --connect-timeout "$CONNECT_TIMEOUT_SECONDS" \
      --max-time "$MAX_TIME_SECONDS" \
      --max-redirs 0 \
      --max-filesize "$MAX_RESPONSE_BYTES" \
      --header 'Accept: application/json' \
      --output "$HTTP_BODY_FILE" \
      --write-out '%{http_code}' \
      --url "$url" \
      2>/dev/null)"
    curl_exit=$?
    set -e

    HTTP_ATTEMPTS="$attempt"
    if [ "$curl_exit" -eq 63 ]; then
      HTTP_OUTCOME="response_too_large"
      return 1
    fi

    case "$HTTP_STATUS" in
      [1-5][0-9][0-9]) ;;
      *) HTTP_STATUS="" ;;
    esac

    if [ -z "$HTTP_STATUS" ] || { [ "$curl_exit" -ne 0 ] && [ "$curl_exit" -ne 22 ]; }; then
      if [ "$attempt" -lt "$max_attempts" ]; then
        attempt=$((attempt + 1))
        continue
      fi
      HTTP_OUTCOME="transport_error"
      return 1
    fi

    case "$HTTP_STATUS" in
      502|503|504)
        if [ "$attempt" -lt "$max_attempts" ]; then
          attempt=$((attempt + 1))
          continue
        fi
        ;;
    esac
    break
  done

  if [ "$(wc -c < "$HTTP_BODY_FILE" | tr -d ' ')" -gt "$MAX_RESPONSE_BYTES" ]; then
    HTTP_OUTCOME="response_too_large"
    return 1
  fi

  HTTP_OUTCOME="http"
  return 0
}

warning_for_http_status() {
  local operation="$1"
  local http_status="$2"

  case "$http_status" in
    401) printf 'UPSTREAM_UNAUTHORIZED' ;;
    403) printf 'UPSTREAM_FORBIDDEN' ;;
    404)
      if [ "$operation" = "execution" ]; then
        printf 'LABOR_SHARE_NOT_FOUND'
      else
        printf 'UPSTREAM_NOT_FOUND'
      fi
      ;;
    429) printf 'UPSTREAM_RATE_LIMITED' ;;
    5??) printf 'UPSTREAM_ERROR' ;;
    *) printf 'UPSTREAM_HTTP_ERROR' ;;
  esac
}

handle_request_failure() {
  local operation="$1"
  local warning

  case "$HTTP_OUTCOME" in
    response_too_large) warning="UPSTREAM_RESPONSE_TOO_LARGE" ;;
    *) warning="UPSTREAM_TRANSPORT_ERROR" ;;
  esac
  emit_indeterminate "$operation" "$warning"
}

validate_execution_response() {
  jq -e \
    --argjson max_assignments "$MAX_ASSIGNMENTS" \
    --argjson max_safe_integer "$MAX_SAFE_INTEGER" '
      type == "array" and
      length >= 1 and length <= $max_assignments and
      all(.[ ];
        type == "object" and
        (.id | type == "number" and (. % 1) == 0 and . > 0 and . <= $max_safe_integer) and
        (.user_id | type == "number" and (. % 1) == 0 and . > 0 and . <= $max_safe_integer) and
        (.fullname | type == "string") and
        (.operational_process == null or (.operational_process | type == "string")) and
        (.message == null or (.message | type == "string")) and
        (.status == "SUCCESS" or .status == "FAIL") and
        (.return_date | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$"))
      ) and
      ([.[].id] | length == (unique | length))
    ' "$HTTP_BODY_FILE" >/dev/null 2>&1
}

render_execution_result() {
  local facts_json
  local warnings_json

  facts_json="$(jq -c '
    ([.[] | select(.status == "SUCCESS")] | length) as $success |
    ([.[] | select(.status == "FAIL")] | length) as $fail |
    ([.[].return_date] | unique) as $dates |
    {
      processing: false,
      assignments: {
        counts: {
          total: length,
          success: $success,
          fail: $fail
        },
        result_consistency: (
          if $success > 0 and $fail > 0 then "mixed"
          elif $success > 0 then "uniform_success"
          else "uniform_fail"
          end
        ),
        scheduled_return: (
          if ($dates | length) == 1
          then {consistency: "uniform", at: $dates[0]}
          else {consistency: "mixed", distinct_values: ($dates | length)}
          end
        )
      }
    }
  ' "$HTTP_BODY_FILE")"

  warnings_json="$(jq -c '
    ([.[] | select(.status == "SUCCESS")] | length) as $success |
    ([.[] | select(.status == "FAIL")] | length) as $fail |
    ([.[].return_date] | unique | length) as $date_count |
    [
      if $success > 0 and $fail > 0 then "MIXED_ASSIGNMENT_RESULTS" else empty end,
      if $date_count > 1 then "INCONSISTENT_SCHEDULED_RETURN" else empty end
    ]
  ' "$HTTP_BODY_FILE")"

  emit_result "execution" "complete" "$facts_json" "ok" "$warnings_json"
}

validate_processes_response() {
  jq -e \
    --argjson max_processes "$MAX_PROCESSES" \
    --argjson max_sub_processes "$MAX_SUB_PROCESSES" \
    --argjson max_description_length "$MAX_DESCRIPTION_LENGTH" \
    --argjson max_safe_integer "$MAX_SAFE_INTEGER" '
      type == "array" and
      length <= $max_processes and
      all(.[ ];
        type == "object" and
        (.id | type == "number" and (. % 1) == 0 and . > 0 and . <= $max_safe_integer) and
        (.description | type == "string" and length >= 1 and length <= $max_description_length) and
        (.sub_processes | type == "array" and length <= $max_sub_processes) and
        all(.sub_processes[ ];
          type == "object" and
          (.id | type == "number" and (. % 1) == 0 and . > 0 and . <= $max_safe_integer) and
          (.description | type == "string" and length >= 1 and length <= $max_description_length)
        )
      ) and
      ([.[].id] | length == (unique | length))
    ' "$HTTP_BODY_FILE" >/dev/null 2>&1
}

render_processes_result() {
  local facts_json

  facts_json="$(jq -c '{
    catalog: {
      process_count: length,
      processes: [
        .[] | {
          description,
          sub_process_count: (.sub_processes | length),
          sub_processes: [.sub_processes[].description]
        }
      ]
    }
  }' "$HTTP_BODY_FILE")"

  emit_result "processes" "complete" "$facts_json" "ok" '[]'
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 2
fi

OPERATION="$1"
shift
IDENTIFIER_CANDIDATES=()
FACILITY_CANDIDATES=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --labor-share-id)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      IDENTIFIER_CANDIDATES+=("$2")
      shift 2
      ;;
    --facility-type)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      FACILITY_CANDIDATES+=("$2")
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  printf '{"schema_version":1,"status":"indeterminate","warnings":["LOCAL_DEPENDENCY_UNAVAILABLE"]}\n'
  exit 0
fi

if [ -L "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ] || ! validate_configuration; then
  printf '{"schema_version":1,"status":"indeterminate","warnings":["CONFIGURATION_INVALID"]}\n'
  exit 0
fi

BASE_URL="$(jq -r '.api.base_url' "$CONFIG_FILE")"
CONNECT_TIMEOUT_SECONDS="$(jq -r '.network.connect_timeout_seconds' "$CONFIG_FILE")"
MAX_TIME_SECONDS="$(jq -r '.network.max_time_seconds' "$CONFIG_FILE")"
MAX_GET_RETRIES="$(jq -r '.network.max_get_retries' "$CONFIG_FILE")"
MAX_RESPONSE_BYTES="$(jq -r '.network.max_response_bytes' "$CONFIG_FILE")"
MAX_SAFE_INTEGER="$(jq -r '.limits.max_safe_integer' "$CONFIG_FILE")"
MAX_IDENTIFIER_LENGTH="$(jq -r '.limits.max_identifier_length' "$CONFIG_FILE")"
MAX_ASSIGNMENTS="$(jq -r '.limits.max_assignments' "$CONFIG_FILE")"
MAX_PROCESSES="$(jq -r '.limits.max_processes' "$CONFIG_FILE")"
MAX_SUB_PROCESSES="$(jq -r '.limits.max_sub_processes_per_process' "$CONFIG_FILE")"
MAX_DESCRIPTION_LENGTH="$(jq -r '.limits.max_description_length' "$CONFIG_FILE")"

umask 077
TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/groot-labor-share.XXXXXX")"
trap cleanup EXIT INT TERM

case "$OPERATION" in
  execution)
    if [ "${#FACILITY_CANDIDATES[@]}" -ne 0 ] || [ "${#IDENTIFIER_CANDIDATES[@]}" -eq 0 ]; then
      emit_indeterminate "execution" "INVALID_LABOR_SHARE_ID"
      exit 0
    fi

    set +e
    LABOR_SHARE_ID="$(normalize_identifier_candidates "${IDENTIFIER_CANDIDATES[@]}")"
    normalize_status=$?
    set -e
    if [ "$normalize_status" -eq 1 ]; then
      emit_indeterminate "execution" "INVALID_LABOR_SHARE_ID"
      exit 0
    elif [ "$normalize_status" -eq 2 ]; then
      emit_indeterminate "execution" "AMBIGUOUS_LABOR_SHARE_ID"
      exit 0
    fi

    EXECUTION_PATH="$(jq -r '.api.endpoints.execution.path' "$CONFIG_FILE")"
    EXECUTION_URL="$BASE_URL${EXECUTION_PATH/\{labor_share_id\}/$LABOR_SHARE_ID}"
    if ! request_http "$EXECUTION_URL"; then
      handle_request_failure "execution"
      exit 0
    fi

    case "$HTTP_STATUS" in
      200)
        if validate_execution_response; then
          render_execution_result
        else
          emit_indeterminate "execution" "INVALID_LABOR_SHARE_RESPONSE"
        fi
        ;;
      202)
        emit_result "execution" "processing" '{"processing":true}' "processing" '["LABOR_SHARE_PROCESSING"]'
        ;;
      *) emit_indeterminate "execution" "$(warning_for_http_status "$OPERATION" "$HTTP_STATUS")" ;;
    esac
    ;;
  processes)
    if [ "${#IDENTIFIER_CANDIDATES[@]}" -ne 0 ] || [ "${#FACILITY_CANDIDATES[@]}" -eq 0 ]; then
      emit_indeterminate "processes" "INVALID_FACILITY_TYPE"
      exit 0
    fi

    set +e
    FACILITY_TYPE="$(normalize_facility_candidates "${FACILITY_CANDIDATES[@]}")"
    normalize_status=$?
    set -e
    if [ "$normalize_status" -eq 1 ]; then
      emit_indeterminate "processes" "INVALID_FACILITY_TYPE"
      exit 0
    elif [ "$normalize_status" -eq 2 ]; then
      emit_indeterminate "processes" "AMBIGUOUS_FACILITY_TYPE"
      exit 0
    fi

    PROCESSES_PATH="$(jq -r '.api.endpoints.processes.path' "$CONFIG_FILE")"
    PROCESSES_URL="$BASE_URL${PROCESSES_PATH/\{facility_type\}/$FACILITY_TYPE}"
    if ! request_http "$PROCESSES_URL"; then
      handle_request_failure "processes"
      exit 0
    fi

    case "$HTTP_STATUS" in
      200)
        if validate_processes_response; then
          render_processes_result
        else
          emit_indeterminate "processes" "INVALID_LABOR_SHARE_RESPONSE"
        fi
        ;;
      *) emit_indeterminate "processes" "$(warning_for_http_status "$OPERATION" "$HTTP_STATUS")" ;;
    esac
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
