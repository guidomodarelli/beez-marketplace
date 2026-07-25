#!/bin/bash

set -euo pipefail
umask 077

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER="$SCRIPT_DIRECTORY/../scripts/run-groot-queue.sh"
REAL_JQ="$(command -v jq)"
TEMP_DIRECTORY="$(mktemp -d -t run-groot-queue-test.XXXXXX)"
trap 'rm -rf -- "$TEMP_DIRECTORY"' EXIT HUP INT TERM
chmod 700 "$TEMP_DIRECTORY"

FAKE_BIN="$TEMP_DIRECTORY/bin"
PLUGIN_DIRECTORY="$TEMP_DIRECTORY/grid-sharing-plugin"
INVENTORY_LOG="$TEMP_DIRECTORY/inventory.log"
CHILD_LOG="$TEMP_DIRECTORY/child.log"
CURL_LOG="$TEMP_DIRECTORY/curl.log"
STDOUT_FILE="$TEMP_DIRECTORY/stdout.log"
STDERR_FILE="$TEMP_DIRECTORY/stderr.log"
mkdir -p "$FAKE_BIN" "$PLUGIN_DIRECTORY/skills/grid"
printf '%s\n' '# Grid runner fixture' > "$PLUGIN_DIRECTORY/skills/grid/SKILL.md"
ln -s "$REAL_JQ" "$FAKE_BIN/jq"

cat > "$FAKE_BIN/claude" <<'STUB'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "list" ]; then
  printf 'claude inventory\n' >> "$INVENTORY_LOG"
  if [ "${CLAUDE_INVENTORY:-success}" = "success" ]; then
    jq -nc --arg path "$FAKE_PLUGIN_INSTALL_PATH" '[{id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$path}]'
  else
    printf '%s\n' '[]'
  fi
  exit 0
fi

printf 'claude child args=%s\n' "$*" >> "$CHILD_LOG"
printf 'provider=%s\n' "${GROOT_QUEUE_ACTIVE_PROVIDER:-unset}" >> "$CHILD_LOG"
printf 'preflight=%s\n' "${GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE:-unset}" >> "$CHILD_LOG"
if [ -n "${GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE:-}" ]; then
  mode=""
  if stat -f '%Lp' "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE" >/dev/null 2>&1; then
    mode="$(stat -f '%Lp' "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE")"
  else
    mode="$(stat -c '%a' "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE")"
  fi
  jq -e '.ok == true and .exit_code == 0 and .provider == "claude"' "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE" >/dev/null
  [ "$mode" = "600" ]
  printf 'preflight_valid=true mode=%s\n' "$mode" >> "$CHILD_LOG"
fi
printf 'claude child complete\n'
STUB

cat > "$FAKE_BIN/codex" <<'STUB'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "list" ]; then
  printf 'codex inventory\n' >> "$INVENTORY_LOG"
  if [ "${CODEX_INVENTORY:-success}" = "success" ]; then
    jq -nc --arg path "$FAKE_PLUGIN_INSTALL_PATH" '{installed:[{pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$path}}]}'
  else
    printf '%s\n' '{"installed":[]}'
  fi
  exit 0
fi

printf 'codex child args=%s\n' "$*" >> "$CHILD_LOG"
printf 'provider=%s\n' "${GROOT_QUEUE_ACTIVE_PROVIDER:-unset}" >> "$CHILD_LOG"
printf 'preflight=%s\n' "${GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE:-unset}" >> "$CHILD_LOG"
if [ -n "${GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE:-}" ]; then
  mode=""
  if stat -f '%Lp' "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE" >/dev/null 2>&1; then
    mode="$(stat -f '%Lp' "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE")"
  else
    mode="$(stat -c '%a' "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE")"
  fi
  jq -e '.ok == true and .exit_code == 0 and .provider == "codex"' "$GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE" >/dev/null
  [ "$mode" = "600" ]
  printf 'preflight_valid=true mode=%s\n' "$mode" >> "$CHILD_LOG"
fi
printf 'codex child complete\n'
STUB

cat > "$FAKE_BIN/copilot" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'copilot child args=%s\n' "$*" >> "$CHILD_LOG"
printf 'copilot child complete\n'
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
case "$url" in
  */ping) body='pong' ;;
  */skill/version*) body='{"up_to_date":true,"update_required":false,"version":"1.2.4"}' ;;
  */api/v1/me) body='{"caller_id":"runner","ldap":"runner","email":"runner@example.test","auth_path":"vpn","is_public":false}' ;;
  */api/v1/documents\?*) body='{"documents":[]}' ;;
  */api/v1/documents/*) body='{"doc_id":"01KWVJRP5DBAN5RD41PDQ518D1","title":"Fixture","doc_type":"markdown","content_storage":"s3"}' ;;
  *) body='{}' ;;
esac
printf '%s' "$body" > "$output_file"
printf '200'
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
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [ "$actual" = "$expected" ] || fail "$message (expected=$expected actual=$actual)"
}

assert_empty_file() {
  local file_path="$1"
  local message="$2"
  [ ! -s "$file_path" ] || fail "$message"
}

assert_contains() {
  local file_path="$1"
  local expected="$2"
  local message="$3"
  grep -Fq -- "$expected" "$file_path" || fail "$message"
}

assert_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  local message="$3"
  if grep -Fq -- "$unexpected" "$file_path"; then
    fail "$message"
  fi
}

reset_run_state() {
  : > "$INVENTORY_LOG"
  : > "$CHILD_LOG"
  : > "$CURL_LOG"
  : > "$STDOUT_FILE"
  : > "$STDERR_FILE"
}

run_runner() {
  reset_run_state
  set +e
  PATH="$TEST_PATH" \
    INVENTORY_LOG="$INVENTORY_LOG" \
    CHILD_LOG="$CHILD_LOG" \
    CURL_LOG="$CURL_LOG" \
    FAKE_PLUGIN_INSTALL_PATH="$PLUGIN_DIRECTORY" \
    CLAUDE_INVENTORY="${CLAUDE_INVENTORY_SCENARIO:-success}" \
    CODEX_INVENTORY="${CODEX_INVENTORY_SCENARIO:-success}" \
    bash "$RUNNER" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
  LAST_STATUS=$?
  set -e
}

run_runner --help
assert_equal 0 "$LAST_STATUS" "global help should succeed"
assert_empty_file "$INVENTORY_LOG" "global help must not invoke checker inventory"
assert_empty_file "$CURL_LOG" "global help must not invoke Grid"
assert_empty_file "$CHILD_LOG" "global help must not invoke a provider"
assert_contains "$STDOUT_FILE" 'run-groot-queue' "global help should render launcher usage"
printf 'ok - global help bypasses checker and providers\n'

run_runner --provider claude setup
assert_equal 0 "$LAST_STATUS" "setup should invoke provider successfully"
assert_empty_file "$INVENTORY_LOG" "setup must not invoke checker inventory"
assert_empty_file "$CURL_LOG" "setup must not invoke Grid preflight in launcher"
assert_contains "$CHILD_LOG" 'claude child args=' "setup should invoke Claude"
assert_contains "$CHILD_LOG" '/groot-queue setup' "setup prompt was not forwarded"
assert_contains "$CHILD_LOG" 'preflight=unset' "setup child must not receive a reusable preflight file"
printf 'ok - setup bypasses checker and forwards prompt\n'

run_runner --provider codex list --help
assert_equal 0 "$LAST_STATUS" "subcommand help should invoke provider successfully"
assert_empty_file "$INVENTORY_LOG" "subcommand help must not invoke checker inventory"
assert_empty_file "$CURL_LOG" "subcommand help must not invoke Grid"
assert_contains "$CHILD_LOG" 'codex child args=' "list help should invoke Codex"
assert_contains "$CHILD_LOG" '/groot-queue list --help' "list help prompt was not forwarded"
assert_contains "$CHILD_LOG" 'preflight=unset' "help child must not receive a reusable preflight file"
printf 'ok - subcommand help bypasses checker and forwards help prompt\n'

CLAUDE_INVENTORY_SCENARIO=missing
run_runner --provider claude list
assert_equal 1 "$LAST_STATUS" "failed operational preflight should block runner"
assert_contains "$INVENTORY_LOG" 'claude inventory' "operational preflight should inspect explicit provider"
assert_empty_file "$CHILD_LOG" "failed operational preflight must not launch provider prompt"
printf 'ok - failed preflight blocks provider prompt\n'
unset CLAUDE_INVENTORY_SCENARIO

run_runner --provider claude list
assert_equal 0 "$LAST_STATUS" "successful operational preflight should continue"
assert_contains "$INVENTORY_LOG" 'claude inventory' "successful operational preflight should inspect provider"
assert_equal 1 "$(grep -c '^claude child args=' "$CHILD_LOG")" "provider child should launch exactly once"
assert_contains "$CHILD_LOG" '/groot-queue list' "operational prompt was not forwarded"
assert_contains "$CHILD_LOG" 'provider=claude' "child should receive active provider"
assert_contains "$CHILD_LOG" 'preflight_valid=true mode=600' "child should receive a mode-600 valid JSON preflight result"
printf 'ok - successful preflight launches provider once with reusable result\n'

CODEX_INVENTORY_SCENARIO=missing
run_runner --provider codex list
assert_equal 1 "$LAST_STATUS" "explicit provider failure should block runner"
assert_contains "$INVENTORY_LOG" 'codex inventory' "explicit Codex should be inspected"
assert_not_contains "$INVENTORY_LOG" 'claude inventory' "explicit provider must not fall back to Claude"
assert_empty_file "$CHILD_LOG" "explicit provider failure must not launch another provider"
printf 'ok - explicit provider never falls back\n'
unset CODEX_INVENTORY_SCENARIO

CODEX_INVENTORY_SCENARIO=missing
run_runner list
assert_equal 0 "$LAST_STATUS" "auto provider selection should reach Claude"
assert_contains "$INVENTORY_LOG" 'codex inventory' "auto mode should evaluate Codex after unsupported Copilot"
assert_contains "$INVENTORY_LOG" 'claude inventory' "auto mode should evaluate Claude after Codex failure"
assert_not_contains "$CHILD_LOG" 'copilot child' "unsupported Copilot must not be selected"
assert_not_contains "$CHILD_LOG" 'codex child args=' "failed Codex must not receive the prompt"
assert_equal 1 "$(grep -c '^claude child args=' "$CHILD_LOG")" "Claude should be selected exactly once"
assert_contains "$CHILD_LOG" 'provider=claude' "auto mode should expose Claude as active provider"
printf 'ok - auto mode skips Copilot, rejects Codex, and selects Claude\n'
unset CODEX_INVENTORY_SCENARIO

run_invalid_case() {
  local description="$1"
  shift
  run_runner "$@"
  assert_equal 2 "$LAST_STATUS" "$description should fail with exit 2"
  assert_empty_file "$INVENTORY_LOG" "$description must fail before checker inventory"
  assert_empty_file "$CURL_LOG" "$description must fail before Grid"
  assert_empty_file "$CHILD_LOG" "$description must fail before provider invocation"
}

run_invalid_case 'missing provider option value' list --provider
run_invalid_case 'missing model option value' list --model
run_invalid_case 'missing effort option value' list --reasoning-effort
run_invalid_case 'invalid provider' --provider invalid list
run_invalid_case 'invalid effort' --reasoning-effort extreme list
printf 'ok - invalid launcher options fail before providers\n'

printf 'All run-groot-queue tests passed.\n'
