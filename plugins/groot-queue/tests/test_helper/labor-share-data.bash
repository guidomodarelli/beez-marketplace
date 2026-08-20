setup_labor_share_data_fixture() {
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/groot-labor-share-test.XXXXXX")"
  FAKE_BIN="$TEST_ROOT/bin"
  CURL_LOG="$TEST_ROOT/curl.log"
  CURL_STATE_DIRECTORY="$TEST_ROOT/curl-state"
  CURL_FLAGS_LOG="$TEST_ROOT/curl-flags.log"
  STDOUT_FILE="$TEST_ROOT/stdout"
  STDERR_FILE="$TEST_ROOT/stderr"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../skills/groot-queue/scripts/query-labor-share-data.sh"
  REAL_JQ="$(command -v jq)"

  mkdir -p "$FAKE_BIN" "$CURL_STATE_DIRECTORY"
  : > "$CURL_LOG"
  : > "$CURL_FLAGS_LOG"
  ln -s "$REAL_JQ" "$FAKE_BIN/jq"

  cat > "$FAKE_BIN/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
output_file=""
url=""
proto=""
max_redirs=""
max_filesize=""
fail_with_body=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --request) method="$2"; shift 2 ;;
    --output) output_file="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --proto) proto="$2"; shift 2 ;;
    --max-redirs) max_redirs="$2"; shift 2 ;;
    --max-filesize) max_filesize="$2"; shift 2 ;;
    --connect-timeout|--max-time|--header|--write-out) shift 2 ;;
    --fail-with-body) fail_with_body=true; shift ;;
    --silent|--show-error) shift ;;
    *) shift ;;
  esac
done

printf '%s %s\n' "$method" "$url" >> "$CURL_LOG"
printf 'method=%s proto=%s max_redirs=%s max_filesize=%s fail_with_body=%s url=%s\n' \
  "$method" "$proto" "$max_redirs" "$max_filesize" "$fail_with_body" "$url" >> "$CURL_FLAGS_LOG"

[ "$method" = "GET" ]
[ "$proto" = "=https" ]
[ "$max_redirs" = "0" ]
[ -n "$max_filesize" ]
[ "$fail_with_body" = "true" ]
case "$url" in
  https://*) ;;
  *) exit 2 ;;
esac

scenario="${LABOR_SHARE_TEST_SCENARIO:-execution-success}"
status=200
body='[
  {"id":7001,"user_id":8001,"fullname":"Private Person","operational_process":"Picking","message":"private assignment message","status":"SUCCESS","return_date":"2026-08-01T12:00:00Z"},
  {"id":7002,"user_id":8002,"fullname":"Another Private Person","operational_process":null,"message":null,"status":"SUCCESS","return_date":"2026-08-01T12:00:00Z"}
]'

case "$url" in
  *'/management/v1/labor-share/process/'*)
    body='[
      {"id":9101,"description":"Inbound","sub_processes":[{"id":9201,"description":"Receiving"},{"id":9202,"description":"Putaway"}]},
      {"id":9102,"description":"Outbound","sub_processes":[]}
    ]'
    ;;
  *'/management/v1/labor-share/'*) ;;
  *)
    status=404
    body='{"message":"private unexpected URL body"}'
    ;;
esac

case "$scenario" in
  execution-success) ;;
  execution-mixed)
    body='[
      {"id":7001,"user_id":8001,"fullname":"Private Person","operational_process":"Picking","message":"private assignment message","status":"SUCCESS","return_date":"2026-08-01T12:00:00Z"},
      {"id":7002,"user_id":8002,"fullname":"Another Private Person","operational_process":"Packing","message":"private failure message","status":"FAIL","return_date":"2026-08-01T12:00:00Z"}
    ]'
    ;;
  execution-mixed-dates)
    body='[
      {"id":7001,"user_id":8001,"fullname":"Private Person","operational_process":"Picking","message":null,"status":"SUCCESS","return_date":"2026-08-01T12:00:00Z"},
      {"id":7002,"user_id":8002,"fullname":"Another Private Person","operational_process":"Packing","message":null,"status":"SUCCESS","return_date":"2026-08-02T12:00:00.123Z"}
    ]'
    ;;
  processing)
    status=202
    body='{"labor_share_id":424242,"message":"private processing body"}'
    ;;
  forbidden)
    status=403
    body='{"labor_share_id":424242,"user_id":8001,"message":"private forbidden body"}'
    ;;
  not-found)
    status=404
    body='{"labor_share_id":424242,"message":"private not found body"}'
    ;;
  rate-limited)
    status=429
    body='{"message":"private rate limit body"}'
    ;;
  transport)
    exit 28
    ;;
  retry-503)
    attempt_file="$CURL_STATE_DIRECTORY/retry-503-attempt"
    attempt=0
    [ ! -f "$attempt_file" ] || attempt="$(< "$attempt_file")"
    attempt=$((attempt + 1))
    printf '%s\n' "$attempt" > "$attempt_file"
    if [ "$attempt" -eq 1 ]; then
      status=503
      body='{"message":"private retry body"}'
    fi
    ;;
  invalid-execution-schema)
    body='[{"id":7001,"user_id":8001,"fullname":"Private Person","status":"UNKNOWN","return_date":"not-a-date"}]'
    ;;
  mixed-invalid-execution-schema)
    body='[
      {"id":7001,"user_id":8001,"fullname":"Private Person","status":"SUCCESS","return_date":"2026-08-01T12:00:00Z"},
      {"id":7002,"user_id":8002,"fullname":"Another Private Person","status":"UNKNOWN","return_date":"not-a-date"}
    ]'
    ;;
  empty-execution)
    body='[]'
    ;;
  processes-success) ;;
  processes-not-found)
    status=404
    body='{"message":"private not found body"}'
    ;;
  invalid-processes-schema)
    body='[{"id":9101,"description":"Inbound","sub_processes":[{"id":"9201","description":"Receiving"}]}]'
    ;;
esac

printf '%s' "$body" > "$output_file"
printf '%s' "$status"
if [ "$status" -ge 400 ]; then
  exit 22
fi
STUB
  chmod 700 "$FAKE_BIN/curl"
}

teardown_labor_share_data_fixture() {
  rm -rf -- "$TEST_ROOT"
}

run_labor_share_data() {
  PATH="$FAKE_BIN:/usr/bin:/bin" \
    CURL_LOG="$CURL_LOG" \
    CURL_STATE_DIRECTORY="$CURL_STATE_DIRECTORY" \
    CURL_FLAGS_LOG="$CURL_FLAGS_LOG" \
    REAL_JQ="$REAL_JQ" \
    LABOR_SHARE_TEST_SCENARIO="${LABOR_SHARE_TEST_SCENARIO:-execution-success}" \
    bash "$SCRIPT_PATH" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
}

labor_share_test_fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$STDOUT_FILE" ] || { printf '%s\n' '--- stdout ---' >&2; /bin/cat "$STDOUT_FILE" >&2; }
  [ ! -f "$STDERR_FILE" ] || { printf '%s\n' '--- stderr ---' >&2; /bin/cat "$STDERR_FILE" >&2; }
  [ ! -f "$CURL_LOG" ] || { printf '%s\n' '--- curl log ---' >&2; /bin/cat "$CURL_LOG" >&2; }
  [ ! -f "$CURL_FLAGS_LOG" ] || { printf '%s\n' '--- curl flags ---' >&2; /bin/cat "$CURL_FLAGS_LOG" >&2; }
  return 1
}

assert_labor_share_json() {
  local filter="$1"
  local message="$2"
  "$REAL_JQ" -e "$filter" "$STDOUT_FILE" >/dev/null || labor_share_test_fail "$message"
}

assert_labor_share_count() {
  local expected="$1"
  local pattern="$2"
  local message="$3"
  local actual
  actual="$(grep -c -- "$pattern" "$CURL_LOG" || true)"
  [ "$actual" -eq "$expected" ] || labor_share_test_fail "$message (expected=$expected actual=$actual)"
}

assert_labor_share_private_values_hidden() {
  local private_pattern='424242|7001|7002|8001|8002|Private Person|Another Private Person|private assignment message|private failure message|private processing body|private forbidden body|private not found body|private rate limit body|private retry body|prod--shipping-users-mgmt-api\.legacy\.furyapps\.io|management/v1/labor-share'
  ! grep -E "$private_pattern" "$STDOUT_FILE" >/dev/null || labor_share_test_fail "stdout exposed private labor share data"
  ! grep -E "$private_pattern" "$STDERR_FILE" >/dev/null || labor_share_test_fail "stderr exposed private labor share data"
}
