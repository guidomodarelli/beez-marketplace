#!/bin/bash

set -euo pipefail
umask 077

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CHECKER="$SCRIPT_DIRECTORY/../skills/groot-queue/scripts/check-groot-queue-readiness.sh"
REAL_JQ="$(command -v jq)"
TEMP_DIRECTORY="$(mktemp -d -t check-groot-queue-readiness-test.XXXXXX)"
trap 'rm -rf -- "$TEMP_DIRECTORY"' EXIT HUP INT TERM
chmod 700 "$TEMP_DIRECTORY"

FAKE_BIN="$TEMP_DIRECTORY/bin"
PLUGIN_DIRECTORY="$TEMP_DIRECTORY/grid-sharing-plugin"
PROVIDER_LOG="$TEMP_DIRECTORY/provider.log"
INVENTORY_FIXTURE_LOG="$TEMP_DIRECTORY/inventory-fixture.json"
CURL_LOG="$TEMP_DIRECTORY/curl.log"
STDOUT_FILE="$TEMP_DIRECTORY/stdout.json"
STDERR_FILE="$TEMP_DIRECTORY/stderr.log"
mkdir -p "$FAKE_BIN" "$PLUGIN_DIRECTORY/skills/grid"
printf '%s\n' '# Grid test fixture' > "$PLUGIN_DIRECTORY/skills/grid/SKILL.md"
ln -s "$REAL_JQ" "$FAKE_BIN/jq"

cat > "$FAKE_BIN/claude" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'claude %s\n' "$*" >> "$PROVIDER_LOG"
case "${INVENTORY_SCENARIO:-success}" in
  missing) printf '%s\n' '[]' ;;
  disabled)
    jq -nc --arg path "$FAKE_PLUGIN_INSTALL_PATH" '[{id:"grid-sharing@tech-plugins-marketplace",enabled:false,version:"1.2.3",installPath:$path}]'
    ;;
  invalid) printf '%s\n' '{"unexpected":true}' ;;
  *)
    jq -nc --arg path "$FAKE_PLUGIN_INSTALL_PATH" '[{id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$path}]' | tee "$INVENTORY_FIXTURE_LOG"
    ;;
esac
STUB

cat > "$FAKE_BIN/codex" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'codex %s\n' "$*" >> "$PROVIDER_LOG"
case "${INVENTORY_SCENARIO:-success}" in
  missing) printf '%s\n' '{"installed":[]}' ;;
  disabled)
    jq -nc --arg path "$FAKE_PLUGIN_INSTALL_PATH" '{installed:[{pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:false,version:"1.2.3",source:{path:$path}}]}'
    ;;
  invalid) printf '%s\n' '[]' ;;
  *)
    jq -nc --arg path "$FAKE_PLUGIN_INSTALL_PATH" '{installed:[{pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$path}}]}'
    ;;
esac
STUB

cat > "$FAKE_BIN/copilot" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'copilot %s\n' "$*" >> "$PROVIDER_LOG"
exit 0
STUB

cat > "$FAKE_BIN/curl" <<'STUB'
#!/bin/bash
set -euo pipefail

output_file=""
headers_file=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output|--dump-header|--url|--request|--proto|--connect-timeout|--max-time|--max-redirs|--header|--write-out)
      option_name="$1"
      option_value="${2:-}"
      case "$option_name" in
        --output) output_file="$option_value" ;;
        --dump-header) headers_file="$option_value" ;;
        --url) url="$option_value" ;;
        *) ;;
      esac
      shift 2
      ;;
    --silent|--show-error) shift ;;
    *) shift ;;
  esac
done

printf '%s\n' "$url" >> "$CURL_LOG"
: > "$headers_file"

endpoint="unknown"
case "$url" in
  */ping) endpoint="ping" ;;
  */skill/version*) endpoint="version" ;;
  */api/v1/me) endpoint="identity" ;;
  */api/v1/documents\?*) endpoint="list" ;;
  */api/v1/documents/*) endpoint="document" ;;
esac

scenario="${HTTP_SCENARIO:-success}"
status=200
body='{}'
case "$endpoint" in
  ping) body='pong' ;;
  version) body='{"up_to_date":true,"update_required":false,"version":"1.2.4"}' ;;
  identity) body='{"caller_id":"PRIVATE_CALLER_FIXTURE","ldap":"private_ldap_fixture","email":"private@example.test","auth_path":"vpn","is_public":false,"token":"SECRET_TOKEN_FIXTURE"}' ;;
  list) body='{"documents":[]}' ;;
  document) body='{"doc_id":"01KWVJRP5DBAN5RD41PDQ518D1","title":"PRIVATE_BODY_FIXTURE","doc_type":"markdown","content_storage":"s3","body":"PRIVATE_DOCUMENT_BODY_FIXTURE"}' ;;
  *) status=404 ;;
esac

case "$scenario:$endpoint" in
  identity-401:identity) status=401 ; body='{"message":"PRIVATE_401_BODY"}' ;;
  document-403:document) status=403 ; body='{"message":"PRIVATE_403_BODY"}' ;;
  document-404:document) status=404 ; body='{"message":"PRIVATE_404_BODY"}' ;;
  rate-limit:version)
    status=429
    body='{"message":"PRIVATE_RATE_LIMIT_BODY"}'
    printf 'Retry-After: 000120\r\nX-Private: SECRET_HEADER_FIXTURE\r\n' > "$headers_file"
    ;;
  service-retry:ping)
    attempt_file="$CURL_STATE_DIRECTORY/ping-attempt"
    attempt=0
    if [ -f "$attempt_file" ]; then
      attempt="$(< "$attempt_file")"
    fi
    attempt=$((attempt + 1))
    printf '%s\n' "$attempt" > "$attempt_file"
    if [ "$attempt" -eq 1 ]; then
      status=503
      body='{"message":"PRIVATE_503_BODY"}'
    fi
    ;;
  transport:ping) exit 28 ;;
  invalid-version:version) body='not-json-version' ;;
  incompatible-version:version) body='{"up_to_date":false,"update_required":true,"version":"2.0.0"}' ;;
  invalid-identity:identity) body='not-json-identity' ;;
  invalid-list:list) body='not-json-list' ;;
  invalid-document:document) body='not-json-document' ;;
  *) ;;
esac

printf '%s' "$body" > "$output_file"
printf '%s' "$status"
STUB

chmod 700 "$FAKE_BIN/claude" "$FAKE_BIN/codex" "$FAKE_BIN/copilot" "$FAKE_BIN/curl"

TEST_PATH="$FAKE_BIN:/usr/bin:/bin"
LAST_STATUS=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [ -f "$STDOUT_FILE" ]; then
    printf '%s\n' '--- captured stdout ---' >&2
    /bin/cat "$STDOUT_FILE" >&2
  fi
  if [ -f "$STDERR_FILE" ]; then
    printf '%s\n' '--- captured stderr ---' >&2
    /bin/cat "$STDERR_FILE" >&2
  fi
  if [ -s "$INVENTORY_FIXTURE_LOG" ]; then
    printf '%s\n' '--- inventory fixture ---' >&2
    /bin/cat "$INVENTORY_FIXTURE_LOG" >&2
  fi
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [ "$actual" = "$expected" ] || fail "$message (expected=$expected actual=$actual)"
}

assert_json() {
  local filter="$1"
  local message="$2"
  jq -e "$filter" "$STDOUT_FILE" >/dev/null || fail "$message"
}

assert_empty_file() {
  local file_path="$1"
  local message="$2"
  [ ! -s "$file_path" ] || fail "$message"
}

assert_nonempty_file() {
  local file_path="$1"
  local message="$2"
  [ -s "$file_path" ] || fail "$message"
}

reset_run_state() {
  : > "$PROVIDER_LOG"
  : > "$CURL_LOG"
  : > "$STDOUT_FILE"
  : > "$STDERR_FILE"
  rm -rf -- "$TEMP_DIRECTORY/curl-state"
  mkdir -p "$TEMP_DIRECTORY/curl-state"
}

run_checker() {
  local provider="$1"
  local inventory_scenario="$2"
  local http_scenario="$3"
  local install_path="$4"
  shift 4
  reset_run_state
  set +e
  PATH="$TEST_PATH" \
    PROVIDER_LOG="$PROVIDER_LOG" \
    INVENTORY_FIXTURE_LOG="$INVENTORY_FIXTURE_LOG" \
    CURL_LOG="$CURL_LOG" \
    CURL_STATE_DIRECTORY="$TEMP_DIRECTORY/curl-state" \
    FAKE_PLUGIN_INSTALL_PATH="$install_path" \
    INVENTORY_SCENARIO="$inventory_scenario" \
    HTTP_SCENARIO="$http_scenario" \
    bash "$CHECKER" --provider "$provider" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
  LAST_STATUS=$?
  set -e

  assert_equal "1" "$(wc -l < "$STDOUT_FILE" | tr -d ' ')" "checker stdout must contain exactly one line"
  jq -e 'type == "object"' "$STDOUT_FILE" >/dev/null || fail "checker stdout must be valid JSON"
}

assert_failure() {
  local expected_exit="$1"
  local expected_code="$2"
  assert_equal "$expected_exit" "$LAST_STATUS" "unexpected checker exit code"
  assert_json ".ok == false and .exit_code == $expected_exit and any(.failures[]; .code == \"$expected_code\")" "missing expected failure $expected_code"
}

run_checker claude success success "$PLUGIN_DIRECTORY"
assert_equal 0 "$LAST_STATUS" "Claude success should exit zero"
assert_json '.ok == true and .provider == "claude" and .source == "fresh" and (.checks | length) == 9 and all(.checks[]; .ok == true)' "Claude success contract is invalid"
if grep -Eq 'PRIVATE_|SECRET_|grid-sharing-plugin' "$STDOUT_FILE"; then
  fail "checker stdout leaked a body, identity, token, or plugin path fixture"
fi
printf 'ok - Claude success and privacy contract\n'

run_checker codex success success "$PLUGIN_DIRECTORY"
assert_equal 0 "$LAST_STATUS" "Codex success should exit zero"
assert_json '.ok == true and .provider == "codex" and all(.checks[]; .status == "passed")' "Codex success contract is invalid"
printf 'ok - Codex success contract\n'

run_checker claude missing success "$PLUGIN_DIRECTORY"
assert_failure 10 PLUGIN_NOT_INSTALLED
printf 'ok - missing plugin fails closed\n'

run_checker claude disabled success "$PLUGIN_DIRECTORY"
assert_failure 10 PLUGIN_DISABLED
printf 'ok - disabled plugin fails closed\n'

MISSING_SKILL_DIRECTORY="$TEMP_DIRECTORY/plugin-without-skill"
mkdir -p "$MISSING_SKILL_DIRECTORY"
run_checker claude success success "$MISSING_SKILL_DIRECTORY"
assert_failure 10 REQUIRED_SKILL_UNAVAILABLE
printf 'ok - missing required skill fails closed\n'

run_checker copilot success success "$PLUGIN_DIRECTORY"
assert_failure 2 PROVIDER_INVENTORY_UNSUPPORTED
assert_empty_file "$PROVIDER_LOG" "Copilot inventory must not be inferred from CLI execution"
printf 'ok - Copilot inventory is unsupported\n'

run_checker claude success identity-401 "$PLUGIN_DIRECTORY"
assert_failure 22 GRID_IDENTITY_UNAVAILABLE
assert_json 'any(.checks[]; .name == "identity" and .http_status == 401 and .attempts == 1)' "identity 401 metadata is invalid"
printf 'ok - identity 401 maps to exit 22\n'

run_checker claude success document-403 "$PLUGIN_DIRECTORY"
assert_failure 24 REQUIRED_DOCUMENT_FORBIDDEN
printf 'ok - document 403 maps to exit 24\n'

run_checker claude success document-404 "$PLUGIN_DIRECTORY"
assert_failure 24 REQUIRED_DOCUMENT_NOT_FOUND
printf 'ok - document 404 maps to exit 24\n'

run_checker claude success rate-limit "$PLUGIN_DIRECTORY"
assert_failure 25 GRID_RATE_LIMITED
assert_json 'any(.checks[]; .name == "skill_version" and .http_status == 429 and .attempts == 1 and .retry_after_seconds == 120)' "Retry-After must be sanitized and must not trigger a retry"
if grep -Eq '000120|SECRET_HEADER_FIXTURE|PRIVATE_RATE_LIMIT_BODY' "$STDOUT_FILE"; then
  fail "rate-limit output leaked unsanitized headers or response body"
fi
printf 'ok - rate limiting preserves only sanitized Retry-After\n'

run_checker claude success service-retry "$PLUGIN_DIRECTORY"
assert_equal 0 "$LAST_STATUS" "one transient 5xx should recover"
assert_json 'any(.checks[]; .name == "ping" and .attempts == 2 and .http_status == 200)' "ping should report exactly two attempts"
assert_equal 2 "$(grep -c '/ping$' "$CURL_LOG")" "5xx must be retried exactly once"
printf 'ok - 5xx retries exactly once\n'

run_checker claude success transport "$PLUGIN_DIRECTORY"
assert_failure 20 GRID_TRANSPORT_FAILED
assert_json 'any(.checks[]; .name == "ping" and .attempts == 2 and .http_status == null)' "transport failure should report two attempts without HTTP status"
assert_equal 2 "$(grep -c '/ping$' "$CURL_LOG")" "transport failure must be retried exactly once"
printf 'ok - transport failure maps to exit 20\n'

run_checker claude success invalid-version "$PLUGIN_DIRECTORY"
assert_failure 21 PLUGIN_VERSION_RESPONSE_INVALID
printf 'ok - invalid version response maps to exit 21\n'

run_checker claude success invalid-identity "$PLUGIN_DIRECTORY"
assert_failure 22 GRID_IDENTITY_RESPONSE_INVALID
printf 'ok - invalid identity response maps to exit 22\n'

run_checker claude success invalid-list "$PLUGIN_DIRECTORY"
assert_failure 23 GENERAL_READ_RESPONSE_INVALID
printf 'ok - invalid document list maps to exit 23\n'

run_checker claude success invalid-document "$PLUGIN_DIRECTORY"
assert_failure 24 REQUIRED_DOCUMENT_RESPONSE_INVALID
printf 'ok - invalid required document maps to exit 24\n'

run_checker claude success incompatible-version "$PLUGIN_DIRECTORY"
assert_failure 21 PLUGIN_VERSION_INCOMPATIBLE
printf 'ok - incompatible plugin version maps to exit 21\n'

REUSE_FILE="$TEMP_DIRECTORY/reusable-result.json"
run_checker claude success success "$PLUGIN_DIRECTORY"
cp "$STDOUT_FILE" "$REUSE_FILE"
chmod 600 "$REUSE_FILE"
run_checker claude success success "$PLUGIN_DIRECTORY" --reuse-result "$REUSE_FILE"
assert_equal 0 "$LAST_STATUS" "valid reuse should succeed"
assert_json '.ok == true and .source == "reused" and .provider == "claude"' "valid reuse should be marked reused"
assert_empty_file "$PROVIDER_LOG" "valid reuse must not call provider inventory"
assert_empty_file "$CURL_LOG" "valid reuse must not call Grid"
printf 'ok - successful result is reused without new calls\n'

jq '.checked_at_epoch = 0' "$REUSE_FILE" > "$TEMP_DIRECTORY/stale-result.json"
chmod 600 "$TEMP_DIRECTORY/stale-result.json"
run_checker claude success success "$PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/stale-result.json"
assert_equal 0 "$LAST_STATUS" "stale reuse should run a fresh successful check"
assert_json '.source == "fresh" and .ok == true' "stale reuse must not be trusted"
assert_nonempty_file "$PROVIDER_LOG" "stale reuse must re-run provider inventory"
assert_nonempty_file "$CURL_LOG" "stale reuse must re-run Grid checks"
printf 'ok - stale result triggers a fresh preflight\n'

jq '.checks[0].ok = false' "$REUSE_FILE" > "$TEMP_DIRECTORY/tampered-result.json"
chmod 600 "$TEMP_DIRECTORY/tampered-result.json"
run_checker claude success success "$PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/tampered-result.json"
assert_equal 0 "$LAST_STATUS" "tampered reuse should run a fresh successful check"
assert_json '.source == "fresh" and .ok == true' "tampered reuse must not be trusted"
assert_nonempty_file "$PROVIDER_LOG" "tampered reuse must re-run provider inventory"
printf 'ok - tampered result triggers a fresh preflight\n'

cp "$REUSE_FILE" "$TEMP_DIRECTORY/unsafe-mode.json"
chmod 644 "$TEMP_DIRECTORY/unsafe-mode.json"
run_checker claude success success "$PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/unsafe-mode.json"
assert_failure 70 REUSE_RESULT_FILE_UNSAFE
assert_empty_file "$PROVIDER_LOG" "unsafe mode must fail before provider inventory"
assert_empty_file "$CURL_LOG" "unsafe mode must fail before Grid calls"
printf 'ok - unsafe reuse mode maps to exit 70\n'

ln -s "$REUSE_FILE" "$TEMP_DIRECTORY/unsafe-link.json"
run_checker claude success success "$PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/unsafe-link.json"
assert_failure 70 REUSE_RESULT_FILE_UNSAFE
assert_empty_file "$PROVIDER_LOG" "symlink reuse path must fail before provider inventory"
printf 'ok - unsafe reuse path maps to exit 70\n'

if [ "$(id -u)" -eq 0 ]; then
  cp "$REUSE_FILE" "$TEMP_DIRECTORY/unsafe-owner.json"
  chown 65534 "$TEMP_DIRECTORY/unsafe-owner.json"
  run_checker claude success success "$PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/unsafe-owner.json"
  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  printf 'ok - unsafe reuse owner maps to exit 70\n'
else
  printf 'ok - unsafe reuse owner skipped (requires portable owner change)\n'
fi

printf 'All check-groot-queue-readiness tests passed.\n'
