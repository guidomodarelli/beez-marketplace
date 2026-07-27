setup_kraken_user_data_fixture() {
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/groot-kraken-test.XXXXXX")"
  FAKE_BIN="$TEST_ROOT/bin"
  CURL_LOG="$TEST_ROOT/curl.log"
  CURL_STATE_DIRECTORY="$TEST_ROOT/curl-state"
  STDOUT_FILE="$TEST_ROOT/stdout"
  STDERR_FILE="$TEST_ROOT/stderr"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../skills/groot-queue/scripts/query-kraken-user-data.sh"
  REAL_JQ="$(command -v jq)"

  mkdir -p "$FAKE_BIN" "$CURL_STATE_DIRECTORY"
  : > "$CURL_LOG"
  ln -s "$REAL_JQ" "$FAKE_BIN/jq"

  cat > "$FAKE_BIN/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
output_file=""
url=""
request_body_file=""
proto=""
max_redirs=""
max_filesize=""
fail_with_body=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --request) method="$2"; shift 2 ;;
    --output) output_file="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --data-binary) request_body_file="${2#@}"; shift 2 ;;
    --proto) proto="$2"; shift 2 ;;
    --max-redirs) max_redirs="$2"; shift 2 ;;
    --max-filesize) max_filesize="$2"; shift 2 ;;
    --connect-timeout|--max-time|--header|--write-out) shift 2 ;;
    --fail-with-body) fail_with_body=true; shift ;;
    --silent|--show-error) shift ;;
    *) shift ;;
  esac
done

[ "$proto" = "=https" ]
[ "$max_redirs" = "0" ]
[ -n "$max_filesize" ]
[ "$fail_with_body" = "true" ]

printf '%s %s\n' "$method" "$url" >> "$CURL_LOG"
scenario="${KRAKEN_TEST_SCENARIO:-success}"
status=200
body='{}'

case "$url" in
  *'/aggregator/integration/v1/users?'*)
    body='{"id":123,"active":true,"accounts":[{"account_id":"test_user","account_type":"LDAP"}]}'
    ;;
  *'/integration/v1/users/status?'*)
    body='{"results":[{"id":123,"active":true}],"paging":{"page":0,"size":100,"total_pages":1,"total":1}}'
    ;;
  *'/internal/kraken/auth-core/user/123/roles')
    body='["ROLE_A","ROLE_B"]'
    ;;
  *'/api/v0/users/123/permissions')
    body='{"results":[{"id":50,"key":"permission-key","application_key":"application-key"}]}'
    ;;
  *'/attribute-values-admin?'*)
    body='{"results":[{"attribute_key":"tmp_user_status","values":[{"id":100,"value":"labour-share"}]}],"paging":{"page":0,"size":200,"total":1}}'
    ;;
  *'/users/123/context-accesses')
    body='[{"id":100,"key":"context-key","active":true}]'
    ;;
  *'/core/v1/users/123/silos?'*)
    body='{"results":[{"id":3,"key":"SILO_KEY","active":true}],"paging":{"page":0,"size":1000,"total_pages":1,"total":1}}'
    ;;
  *'/users/assign_roles/check')
    if [ -n "$request_body_file" ]; then
      "$REAL_JQ" -e '.user_id == 123 and .new_assignments == ["ROLE_NEW"]' "$request_body_file" >/dev/null
    fi
    body='[{"role":"ROLE_NEW","can_assign":false,"incompatibilities":["ROLE_A"]}]'
    ;;
  *) status=404; body='{"message":"private not found body"}' ;;
esac

case "$scenario" in
  forbidden)
    status=403
    body='{"message":"private forbidden body"}'
    ;;
  invalid-status)
    case "$url" in
      *'/integration/v1/users/status?'*) body='{"results":[]}' ;;
    esac
    ;;
  retry-status)
    case "$url" in
      *'/integration/v1/users/status?'*)
        attempt_file="$CURL_STATE_DIRECTORY/status-attempt"
        attempt=0
        [ ! -f "$attempt_file" ] || attempt="$(< "$attempt_file")"
        attempt=$((attempt + 1))
        printf '%s\n' "$attempt" > "$attempt_file"
        if [ "$attempt" -eq 1 ]; then
          status=503
          body='{"message":"private retry body"}'
        fi
        ;;
    esac
    ;;
  transport)
    case "$url" in
      *'/integration/v1/users/status?'*) exit 28 ;;
    esac
    ;;
  post-error)
    case "$url" in
      *'/users/assign_roles/check') status=503; body='{"message":"private post body"}' ;;
    esac
    ;;
  invalid-incompatibilities)
    case "$url" in
      *'/users/assign_roles/check') body='[{"role":"UNEXPECTED","can_assign":true,"incompatibilities":[]}]' ;;
    esac
    ;;
esac

printf '%s' "$body" > "$output_file"
printf '%s' "$status"
STUB
  chmod 700 "$FAKE_BIN/curl"
}

teardown_kraken_user_data_fixture() {
  rm -rf -- "$TEST_ROOT"
}

run_kraken_user_data() {
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    CURL_LOG="$CURL_LOG" \
    CURL_STATE_DIRECTORY="$CURL_STATE_DIRECTORY" \
    REAL_JQ="$REAL_JQ" \
    KRAKEN_TEST_SCENARIO="${KRAKEN_TEST_SCENARIO:-success}" \
    "$SCRIPT_PATH" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
}

kraken_test_fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$STDOUT_FILE" ] || { printf '%s\n' '--- stdout ---' >&2; /bin/cat "$STDOUT_FILE" >&2; }
  [ ! -f "$STDERR_FILE" ] || { printf '%s\n' '--- stderr ---' >&2; /bin/cat "$STDERR_FILE" >&2; }
  [ ! -f "$CURL_LOG" ] || { printf '%s\n' '--- curl log ---' >&2; /bin/cat "$CURL_LOG" >&2; }
  return 1
}

assert_kraken_json() {
  local filter="$1"
  local message="$2"
  "$REAL_JQ" -e "$filter" "$STDOUT_FILE" >/dev/null || kraken_test_fail "$message"
}

assert_kraken_count() {
  local expected="$1"
  local pattern="$2"
  local message="$3"
  local actual
  actual="$(grep -c -- "$pattern" "$CURL_LOG" || true)"
  [ "$actual" -eq "$expected" ] || kraken_test_fail "$message (expected=$expected actual=$actual)"
}
