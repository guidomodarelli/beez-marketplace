#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIRECTORY/../knowledge/config/kraken-user-data.json"
TEMP_DIRECTORY=""
HTTP_BODY_FILE=""
HTTP_STATUS=""
HTTP_TRANSPORT_OK=false
HTTP_ATTEMPTS=0
USER_ID=""
LDAP_USER=""
FACTS_CSV=""
CANDIDATE_ROLE_KEYS_CSV=""
FACTS_JSON='{}'
SOURCE_RESULTS_JSON='[]'
WARNINGS_JSON='[]'
SUCCESSFUL_FACTS=0
FAILED_FACTS=0
MAX_SAFE_JSON_INTEGER=9007199254740991
MAX_SAFE_JSON_INTEGER_LENGTH="${#MAX_SAFE_JSON_INTEGER}"

usage() {
  cat <<'USAGE'
Usage:
  query-kraken-user-data.sh resolve-user --ldap <ldap>
  query-kraken-user-data.sh context (--ldap <ldap> | --user-id <id>) --facts <fact,...>
  query-kraken-user-data.sh role-incompatibilities (--ldap <ldap> | --user-id <id>) --candidate-role-keys <key,...>
USAGE
}

fail_usage() {
  printf '%s\n' "$1" >&2
  usage >&2
  exit 64
}

cleanup() {
  if [ -n "$TEMP_DIRECTORY" ] && [ -d "$TEMP_DIRECTORY" ]; then
    rm -rf -- "$TEMP_DIRECTORY"
  fi
}

append_warning() {
  local warning="$1"
  WARNINGS_JSON="$(jq -cn --argjson warnings "$WARNINGS_JSON" --arg warning "$warning" '$warnings + [$warning] | unique')"
}

append_source_result() {
  local source="$1"
  local authority="$2"
  local status="$3"
  local attempts="$4"
  SOURCE_RESULTS_JSON="$(jq -cn \
    --argjson results "$SOURCE_RESULTS_JSON" \
    --arg source "$source" \
    --arg authority "$authority" \
    --arg status "$status" \
    --argjson attempts "$attempts" \
    '$results + [{source:$source, authority:$authority, status:$status, attempts:$attempts}]')"
}

set_fact() {
  local fact_name="$1"
  local fact_json="$2"
  FACTS_JSON="$(jq -cn --argjson facts "$FACTS_JSON" --arg name "$fact_name" --argjson value "$fact_json" '$facts + {($name):$value}')"
  SUCCESSFUL_FACTS=$((SUCCESSFUL_FACTS + 1))
}

mark_fact_failed() {
  local warning="$1"
  FAILED_FACTS=$((FAILED_FACTS + 1))
  append_warning "$warning"
}

validate_ldap() {
  local value="$1"
  [ -n "$value" ] || return 1
  [ "${#value}" -le "$MAX_IDENTIFIER_LENGTH" ] || return 1
  case "$value" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

validate_user_id() {
  local value="$1"
  case "$value" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "${#value}" -le "$MAX_IDENTIFIER_LENGTH" ] || return 1
  [ "${#value}" -le "$MAX_SAFE_JSON_INTEGER_LENGTH" ] || return 1
  (( 10#$value > 0 && 10#$value <= MAX_SAFE_JSON_INTEGER ))
}

validate_role_key() {
  local value="$1"
  [ -n "$value" ] || return 1
  [ "${#value}" -le "$MAX_IDENTIFIER_LENGTH" ] || return 1
  case "$value" in
    *[!A-Za-z0-9._:-]*) return 1 ;;
  esac
}

normalize_role_keys() {
  local csv="$1"
  local item
  local normalized
  local count

  normalized="$(printf '%s\n' "$csv" | tr ',' '\n' | while IFS= read -r item; do
    [ -n "$item" ] || continue
    validate_role_key "$item" || exit 65
    printf '%s\n' "$item"
  done | sort -u)" || return 1
  [ -n "$normalized" ] || return 1
  count="$(printf '%s\n' "$normalized" | wc -l | tr -d ' ')"
  [ "$count" -le "$MAX_ROLES_PER_CHECK" ] || return 1
  printf '%s\n' "$normalized" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

endpoint_value() {
  local endpoint="$1"
  local field="$2"
  jq -er --arg endpoint "$endpoint" --arg field "$field" '.endpoints[$endpoint][$field]' "$CONFIG_FILE"
}

host_value() {
  local host_key="$1"
  jq -er --arg host "$host_key" '.hosts[$host]' "$CONFIG_FILE"
}

build_endpoint_url() {
  local endpoint="$1"
  local path
  local host_key
  local base_url

  path="$(endpoint_value "$endpoint" path)"
  host_key="$(endpoint_value "$endpoint" host)"
  base_url="$(host_value "$host_key")"
  case "$base_url" in
    https://*) ;;
    *) return 1 ;;
  esac
  printf '%s%s' "$base_url" "$path"
}

source_status_for_http() {
  case "$1" in
    200) printf 'ok' ;;
    401) printf 'unauthorized' ;;
    403) printf 'forbidden' ;;
    404) printf 'not_found' ;;
    429) printf 'rate_limited' ;;
    5??) printf 'upstream_error' ;;
    *) printf 'http_error' ;;
  esac
}

warning_for_http() {
  case "$1" in
    401) printf 'UPSTREAM_UNAUTHORIZED' ;;
    403) printf 'UPSTREAM_FORBIDDEN' ;;
    404) printf 'SUBJECT_NOT_FOUND' ;;
    429) printf 'UPSTREAM_RATE_LIMITED' ;;
    5??) printf 'UPSTREAM_ERROR' ;;
    *) printf 'UPSTREAM_HTTP_ERROR' ;;
  esac
}

request_http() {
  local method="$1"
  local source="$2"
  local authority="$3"
  local url="$4"
  local request_body_file="${5:-}"
  local attempt=1
  local max_attempts=1
  local curl_status
  local response_size

  if [ "$method" = "GET" ]; then
    max_attempts=$((MAX_GET_RETRIES + 1))
  fi

  HTTP_BODY_FILE="$TEMP_DIRECTORY/response-${source//[^A-Za-z0-9_-]/_}"
  : > "$HTTP_BODY_FILE"
  HTTP_STATUS=""
  HTTP_TRANSPORT_OK=false
  HTTP_ATTEMPTS=0

  while [ "$attempt" -le "$max_attempts" ]; do
    : > "$HTTP_BODY_FILE"
    curl_status=""

    if [ "$method" = "POST" ]; then
      curl_status="$(curl \
        --silent \
        --show-error \
        --fail-with-body \
        --request POST \
        --proto '=https' \
        --connect-timeout "$CONNECT_TIMEOUT_SECONDS" \
        --max-time "$MAX_TIME_SECONDS" \
        --max-redirs 0 \
        --max-filesize "$MAX_RESPONSE_BYTES" \
        --header 'Accept: application/json' \
        --header 'Content-Type: application/json' \
        --data-binary "@$request_body_file" \
        --output "$HTTP_BODY_FILE" \
        --write-out '%{http_code}' \
        --url "$url" \
        2>/dev/null)" || true
    else
      curl_status="$(curl \
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
        2>/dev/null)" || true
    fi

    HTTP_ATTEMPTS="$attempt"
    case "$curl_status" in
      [1-5][0-9][0-9])
        HTTP_STATUS="$curl_status"
        HTTP_TRANSPORT_OK=true
        ;;
      *)
        HTTP_STATUS=""
        HTTP_TRANSPORT_OK=false
        ;;
    esac

    if [ "$HTTP_TRANSPORT_OK" != "true" ]; then
      if [ "$method" = "GET" ] && [ "$attempt" -lt "$max_attempts" ]; then
        attempt=$((attempt + 1))
        continue
      fi
      append_source_result "$source" "$authority" "transport_error" "$HTTP_ATTEMPTS"
      append_warning "UPSTREAM_TRANSPORT_ERROR"
      return 1
    fi

    case "$HTTP_STATUS" in
      502|503|504)
        if [ "$method" = "GET" ] && [ "$attempt" -lt "$max_attempts" ]; then
          attempt=$((attempt + 1))
          continue
        fi
        ;;
    esac
    break
  done

  response_size="$(wc -c < "$HTTP_BODY_FILE" | tr -d ' ')"
  if [ "$response_size" -gt "$MAX_RESPONSE_BYTES" ]; then
    append_source_result "$source" "$authority" "response_too_large" "$HTTP_ATTEMPTS"
    append_warning "UPSTREAM_RESPONSE_TOO_LARGE"
    return 1
  fi

  append_source_result "$source" "$authority" "$(source_status_for_http "$HTTP_STATUS")" "$HTTP_ATTEMPTS"
  if [ "$HTTP_STATUS" != "200" ]; then
    append_warning "$(warning_for_http "$HTTP_STATUS")"
    return 1
  fi
  return 0
}

resolve_subject() {
  local endpoint_url
  local encoded_ldap
  local authority
  local match_count

  if [ -n "$USER_ID" ]; then
    validate_user_id "$USER_ID" || return 1
    return 0
  fi

  validate_ldap "$LDAP_USER" || return 1
  endpoint_url="$(build_endpoint_url resolve_user)"
  encoded_ldap="$(jq -nr --arg value "$LDAP_USER" '$value | @uri')"
  authority="$(endpoint_value resolve_user authority)"

  if ! request_http GET resolve_user "$authority" "${endpoint_url}?account_id=${encoded_ldap}&account_type=LDAP"; then
    return 1
  fi

  if ! jq -e --arg ldap "$LDAP_USER" '
    type == "object" and
    (.id | type == "number" and . > 0) and
    (.active | type == "boolean") and
    (.accounts | type == "array") and
    all(.accounts[];
      type == "object" and
      (.account_id | type == "string" and length > 0) and
      (.account_type == "LDAP" or .account_type == "MELI")
    ) and
    ([.accounts[] | select(.account_type == "LDAP" and .account_id == $ldap)] | length == 1)
  ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    append_warning "INVALID_UPSTREAM_RESPONSE"
    return 1
  fi

  match_count="$(jq -r --arg ldap "$LDAP_USER" '[.accounts[] | select(.account_type == "LDAP" and .account_id == $ldap)] | length' "$HTTP_BODY_FILE")"
  [ "$match_count" = "1" ] || return 1
  USER_ID="$(jq -r '.id | tostring' "$HTTP_BODY_FILE")"
}

query_account_status() {
  local endpoint_url
  local authority
  local fact_json

  endpoint_url="$(build_endpoint_url user_status)"
  authority="$(endpoint_value user_status authority)"
  if ! request_http GET user_status "$authority" "${endpoint_url}?ids=${USER_ID}"; then
    mark_fact_failed "ACCOUNT_STATUS_INDETERMINATE"
    return
  fi

  if ! jq -e --argjson user_id "$USER_ID" '
    type == "object" and
    (.results | type == "array") and
    (.paging | type == "object") and
    ([.results[] | select(.id == $user_id)] | length == 1) and
    ([.results[] | select(.id == $user_id)][0].active | type == "boolean")
  ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    mark_fact_failed "INVALID_ACCOUNT_STATUS_RESPONSE"
    return
  fi

  fact_json="$(jq -c --argjson user_id "$USER_ID" '{state: (if ([.results[] | select(.id == $user_id)][0].active) then "active" else "inactive" end), source:"sot"}' "$HTTP_BODY_FILE")"
  set_fact "account-status" "$fact_json"
}

query_roles() {
  local endpoint_url
  local authority
  local fact_json

  endpoint_url="$(build_endpoint_url user_roles)"
  endpoint_url="${endpoint_url//\{user_id\}/$USER_ID}"
  authority="$(endpoint_value user_roles authority)"
  if ! request_http GET user_roles "$authority" "$endpoint_url"; then
    mark_fact_failed "ROLES_INDETERMINATE"
    return
  fi

  if ! jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    mark_fact_failed "INVALID_ROLES_RESPONSE"
    return
  fi

  fact_json="$(jq -c '{keys:(sort | unique), count:length, source:"sot"}' "$HTTP_BODY_FILE")"
  set_fact "roles" "$fact_json"
}

query_permissions() {
  local endpoint_url
  local authority
  local fact_json

  endpoint_url="$(build_endpoint_url user_permissions)"
  endpoint_url="${endpoint_url//\{user_id\}/$USER_ID}"
  authority="$(endpoint_value user_permissions authority)"
  if ! request_http GET user_permissions "$authority" "$endpoint_url"; then
    mark_fact_failed "PERMISSIONS_INDETERMINATE"
    return
  fi

  if ! jq -e '
    type == "object" and
    (.results | type == "array") and
    all(.results[];
      type == "object" and
      (.id | type == "number") and
      (.key | type == "string" and length > 0) and
      (.application_key | type == "string" and length > 0)
    )
  ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    mark_fact_failed "INVALID_PERMISSIONS_RESPONSE"
    return
  fi

  fact_json="$(jq -c '{assignments:[.results[] | {key, application_key}] | sort_by(.application_key, .key) | unique, count:(.results | length), source:"replica"}' "$HTTP_BODY_FILE")"
  set_fact "permissions" "$fact_json"
}

query_temporary_status() {
  local endpoint_url
  local authority
  local attribute_key
  local encoded_key
  local fact_json

  endpoint_url="$(build_endpoint_url temporary_status)"
  endpoint_url="${endpoint_url//\{user_id\}/$USER_ID}"
  authority="$(endpoint_value temporary_status authority)"
  attribute_key="$(endpoint_value temporary_status attribute_key)"
  encoded_key="$(jq -nr --arg value "$attribute_key" '$value | @uri')"

  if ! request_http GET temporary_status "$authority" "${endpoint_url}?key=${encoded_key}"; then
    mark_fact_failed "TEMPORARY_STATUS_INDETERMINATE"
    return
  fi

  if ! jq -e --arg attribute_key "$attribute_key" '
    type == "object" and
    (.results | type == "array") and
    all(.results[];
      type == "object" and
      (.attribute_key | type == "string") and
      (.values | type == "array") and
      all(.values[]; type == "object" and (.value | type == "string"))
    ) and
    ([.results[] | select(.attribute_key == $attribute_key)] | length <= 1)
  ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    mark_fact_failed "INVALID_TEMPORARY_STATUS_RESPONSE"
    return
  fi

  fact_json="$(jq -c --arg attribute_key "$attribute_key" '
    ([.results[] | select(.attribute_key == $attribute_key)] | first // {values:[]}) as $attribute |
    {active:($attribute.values | length > 0), values:([$attribute.values[].value] | sort | unique), source:"sot"}
  ' "$HTTP_BODY_FILE")"
  set_fact "temporary-status" "$fact_json"
}

query_context_accesses() {
  local endpoint_url
  local authority
  local fact_json

  endpoint_url="$(build_endpoint_url context_accesses)"
  endpoint_url="${endpoint_url//\{user_id\}/$USER_ID}"
  authority="$(endpoint_value context_accesses authority)"
  if ! request_http GET context_accesses "$authority" "$endpoint_url"; then
    mark_fact_failed "CONTEXT_ACCESSES_INDETERMINATE"
    return
  fi

  if ! jq -e '
    type == "array" and
    all(.[];
      type == "object" and
      (.id | type == "number") and
      (.key | type == "string" and length > 0) and
      (.active | type == "boolean")
    )
  ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    mark_fact_failed "INVALID_CONTEXT_ACCESSES_RESPONSE"
    return
  fi

  fact_json="$(jq -c '{items:[.[] | {key, active}] | sort_by(.key) | unique, count:length, source:"sot"}' "$HTTP_BODY_FILE")"
  set_fact "context-accesses" "$fact_json"
}

query_silos() {
  local endpoint_url
  local authority
  local fact_json

  endpoint_url="$(build_endpoint_url silos)"
  endpoint_url="${endpoint_url//\{user_id\}/$USER_ID}"
  authority="$(endpoint_value silos authority)"
  if ! request_http GET silos "$authority" "${endpoint_url}?page=0&size=1000"; then
    mark_fact_failed "SILOS_INDETERMINATE"
    return
  fi

  if ! jq -e '
    type == "object" and
    (.results | type == "array") and
    (.paging | type == "object") and
    (.paging.page | type == "number") and
    (.paging.size | type == "number") and
    (.paging.total_pages | type == "number") and
    (.paging.total | type == "number") and
    all(.results[];
      type == "object" and
      (.id | type == "number") and
      (.key | type == "string" and length > 0) and
      (.active | type == "boolean")
    )
  ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    mark_fact_failed "INVALID_SILOS_RESPONSE"
    return
  fi

  fact_json="$(jq -c '{items:[.results[] | {key, active}] | sort_by(.key) | unique, count:(.results | length), source:"sot"}' "$HTTP_BODY_FILE")"
  set_fact "silos" "$fact_json"
}

query_context() {
  local fact
  local seen='|'

  [ -n "$FACTS_CSV" ] || fail_usage "Missing --facts."
  IFS=',' read -r -a requested_facts <<< "$FACTS_CSV"
  for fact in "${requested_facts[@]}"; do
    [ -n "$fact" ] || fail_usage "Fact list contains an empty value."
    case "$seen" in
      *"|$fact|"*) continue ;;
    esac
    seen="${seen}${fact}|"
    case "$fact" in
      account-status) query_account_status ;;
      roles) query_roles ;;
      permissions) query_permissions ;;
      temporary-status) query_temporary_status ;;
      context-accesses) query_context_accesses ;;
      silos) query_silos ;;
      attributes|ssff-status)
        mark_fact_failed "UNSUPPORTED_FACT_CONTRACT"
        ;;
      *) fail_usage "Unsupported fact: $fact" ;;
    esac
  done
}

query_role_incompatibilities() {
  local candidate_roles_json
  local endpoint_url
  local authority
  local request_body_file
  local fact_json
  local result_status

  [ -n "$CANDIDATE_ROLE_KEYS_CSV" ] || fail_usage "Missing --candidate-role-keys."
  candidate_roles_json="$(normalize_role_keys "$CANDIDATE_ROLE_KEYS_CSV")" || fail_usage "Invalid candidate role keys."
  endpoint_url="$(build_endpoint_url assignment_check)"
  authority="$(endpoint_value assignment_check authority)"
  request_body_file="$TEMP_DIRECTORY/assignment-check-request"
  jq -cn --argjson user_id "$USER_ID" --argjson roles "$candidate_roles_json" '{user_id:$user_id, new_assignments:$roles}' > "$request_body_file"

  if ! request_http POST assignment_check "$authority" "$endpoint_url" "$request_body_file"; then
    FAILED_FACTS=1
    append_warning "ROLE_INCOMPATIBILITIES_INDETERMINATE"
    return
  fi

  if ! jq -e --argjson candidates "$candidate_roles_json" '
    type == "array" and
    all(.[];
      type == "object" and
      (.role | type == "string" and length > 0) and
      (.can_assign | type == "boolean") and
      (.incompatibilities | type == "array") and
      all(.incompatibilities[]; type == "string" and length > 0)
    ) and
    (([.[].role] | sort) == ($candidates | sort)) and
    (length == ($candidates | length))
  ' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    FAILED_FACTS=1
    append_warning "INVALID_ROLE_INCOMPATIBILITIES_RESPONSE"
    return
  fi

  if jq -e 'all(.[]; .can_assign == true)' "$HTTP_BODY_FILE" >/dev/null 2>&1; then
    result_status="compatible"
  else
    result_status="incompatible"
  fi
  fact_json="$(jq -c '{evaluated_roles:[.[].role] | sort | unique, conflicts:[.[] | select(.can_assign == false) | {role, incompatible_with:(.incompatibilities | sort | unique)}]}' "$HTTP_BODY_FILE")"
  FACTS_JSON="$(jq -cn --argjson facts "$FACTS_JSON" --argjson result "$fact_json" '$facts + {role_incompatibilities:$result}')"
  SUCCESSFUL_FACTS=1
  OPERATION_STATUS="$result_status"
}

render_result() {
  local status

  if [ "${OPERATION:-}" = "role-incompatibilities" ] \
    && { [ "${OPERATION_STATUS:-}" = "compatible" ] || [ "${OPERATION_STATUS:-}" = "incompatible" ]; }; then
    status="$OPERATION_STATUS"
  elif [ "$SUCCESSFUL_FACTS" -gt 0 ] && [ "$FAILED_FACTS" -eq 0 ]; then
    status="complete"
  elif [ "$SUCCESSFUL_FACTS" -gt 0 ]; then
    status="partial"
  else
    status="indeterminate"
  fi

  jq -cn \
    --argjson schema_version 1 \
    --arg status "$status" \
    --arg subject_fingerprint "redacted" \
    --argjson facts "$FACTS_JSON" \
    --argjson source_results "$SOURCE_RESULTS_JSON" \
    --argjson warnings "$WARNINGS_JSON" \
    '{schema_version:$schema_version,status:$status,subject_fingerprint:$subject_fingerprint,facts:$facts,source_results:$source_results,warnings:$warnings}'
}

[ -f "$CONFIG_FILE" ] || { printf 'Kraken user data configuration is missing.\n' >&2; exit 78; }
command -v jq >/dev/null 2>&1 || { printf 'jq is required.\n' >&2; exit 69; }
command -v curl >/dev/null 2>&1 || { printf 'curl is required.\n' >&2; exit 69; }
jq -e '
  .schema_version == 1 and
  (.hosts | type == "object" and all(.[]; type == "string" and startswith("https://"))) and
  (.network.connect_timeout_seconds | type == "number" and . > 0) and
  (.network.max_time_seconds | type == "number" and . > 0) and
  (.network.max_get_retries | type == "number" and . >= 0) and
  (.network.max_response_bytes | type == "number" and . > 0) and
  (.limits.max_roles_per_check | type == "number" and . > 0) and
  (.limits.max_identifier_length | type == "number" and . > 0)
' "$CONFIG_FILE" >/dev/null 2>&1 || { printf 'Kraken user data configuration is invalid.\n' >&2; exit 78; }

CONNECT_TIMEOUT_SECONDS="$(jq -er '.network.connect_timeout_seconds' "$CONFIG_FILE")"
MAX_TIME_SECONDS="$(jq -er '.network.max_time_seconds' "$CONFIG_FILE")"
MAX_GET_RETRIES="$(jq -er '.network.max_get_retries' "$CONFIG_FILE")"
MAX_RESPONSE_BYTES="$(jq -er '.network.max_response_bytes' "$CONFIG_FILE")"
MAX_ROLES_PER_CHECK="$(jq -er '.limits.max_roles_per_check' "$CONFIG_FILE")"
MAX_IDENTIFIER_LENGTH="$(jq -er '.limits.max_identifier_length' "$CONFIG_FILE")"

OPERATION="${1:-}"
[ -n "$OPERATION" ] || fail_usage "Missing operation."
shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ldap)
      [ "$#" -ge 2 ] || fail_usage "Missing value for --ldap."
      LDAP_USER="$2"
      shift 2
      ;;
    --user-id)
      [ "$#" -ge 2 ] || fail_usage "Missing value for --user-id."
      USER_ID="$2"
      shift 2
      ;;
    --facts)
      [ "$#" -ge 2 ] || fail_usage "Missing value for --facts."
      FACTS_CSV="$2"
      shift 2
      ;;
    --role-keys|--candidate-role-keys)
      [ "$#" -ge 2 ] || fail_usage "Missing role keys."
      CANDIDATE_ROLE_KEYS_CSV="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *) fail_usage "Unknown argument: $1" ;;
  esac
done

if [ -n "$LDAP_USER" ] && [ -n "$USER_ID" ]; then
  fail_usage "Use either --ldap or --user-id, not both."
fi
if [ -z "$LDAP_USER" ] && [ -z "$USER_ID" ]; then
  fail_usage "Missing subject: use --ldap or --user-id."
fi
validate_ldap "$LDAP_USER" || { [ -z "$LDAP_USER" ] || fail_usage "Invalid LDAP."; }
validate_user_id "$USER_ID" || { [ -z "$USER_ID" ] || fail_usage "Invalid user ID."; }

umask 077
TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/groot-kraken-user-data.XXXXXX")"
trap cleanup EXIT HUP INT TERM

case "$OPERATION" in
  resolve-user)
    [ -n "$LDAP_USER" ] || fail_usage "resolve-user requires --ldap."
    if resolve_subject; then
      set_fact "identity" '{"resolved":true}'
    else
      mark_fact_failed "IDENTITY_INDETERMINATE"
    fi
    ;;
  context)
    if resolve_subject; then
      query_context
    else
      mark_fact_failed "IDENTITY_INDETERMINATE"
    fi
    ;;
  role-incompatibilities)
    if resolve_subject; then
      query_role_incompatibilities
    else
      mark_fact_failed "IDENTITY_INDETERMINATE"
    fi
    ;;
  *) fail_usage "Unsupported operation: $OPERATION" ;;
esac

render_result
