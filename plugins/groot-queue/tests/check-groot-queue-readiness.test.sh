#!/bin/bash

set -euo pipefail
umask 077

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CHECKER="$SCRIPT_DIRECTORY/../skills/groot-queue/scripts/check-groot-queue-readiness.sh"
REAL_JQ="$(command -v jq)"
REAL_PERL="$(command -v perl)"
TEMP_DIRECTORY="$(mktemp -d -t check-groot-queue-readiness-test.XXXXXX)"
trap 'rm -rf -- "$TEMP_DIRECTORY"' EXIT HUP INT TERM
chmod 700 "$TEMP_DIRECTORY"

FAKE_BIN="$TEMP_DIRECTORY/bin"
GRID_PLUGIN_DIRECTORY="$TEMP_DIRECTORY/grid-sharing-plugin"
FURY_PLUGIN_DIRECTORY="$TEMP_DIRECTORY/fury-services-plugin"
FURY_PLUGIN_WITHOUT_SKILL_DIRECTORY="$TEMP_DIRECTORY/fury-services-plugin-without-skill"
GRID_PLUGIN_SYMLINK_SKILL_DIRECTORY="$TEMP_DIRECTORY/grid-plugin-symlink-skill"
FURY_PLUGIN_SYMLINK_SKILL_DIRECTORY="$TEMP_DIRECTORY/fury-plugin-symlink-skill"
PROVIDER_LOG="$TEMP_DIRECTORY/provider.log"
CURL_LOG="$TEMP_DIRECTORY/curl.log"
STDOUT_FILE="$TEMP_DIRECTORY/stdout.json"
STDERR_FILE="$TEMP_DIRECTORY/stderr.log"
mkdir -p "$FAKE_BIN" "$GRID_PLUGIN_DIRECTORY/skills/grid"
printf '%s\n' '# Grid test fixture' > "$GRID_PLUGIN_DIRECTORY/skills/grid/SKILL.md"
ln -s "$REAL_JQ" "$FAKE_BIN/jq"

write_fury_fixture() {
  local fixture_directory="$1"
  local include_required_skill="$2"

  rm -rf -- "$fixture_directory"
  mkdir -p \
    "$fixture_directory/.claude-plugin" \
    "$fixture_directory/.codex-plugin" \
    "$fixture_directory/skills/fury-services-documentation"

  if [ "$include_required_skill" = "true" ]; then
    printf '%s\n' '# Fury services documentation fixture' > \
      "$fixture_directory/skills/fury-services-documentation/SKILL.md"
  fi

  cat > "$fixture_directory/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fury-services",
  "version": "1.4.0",
  "description": "Fury services fixture"
}
JSON

  cat > "$fixture_directory/.codex-plugin/plugin.json" <<'JSON'
{
  "name": "fury-services",
  "version": "1.4.0",
  "description": "Fury services fixture",
  "skills": "./skills/",
  "mcpServers": "./.mcp.json"
}
JSON

  cat > "$fixture_directory/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "fury": {
      "command": "mcp-remote-proxy",
      "args": [
        "https://mcp-services-gateway.furycloud.io/v1/servers/fury",
        "--headers",
        "x-origin",
        "fury-services-plugin",
        "--timeout",
        "300"
      ]
    }
  }
}
JSON
}

write_fury_fixture "$FURY_PLUGIN_DIRECTORY" true
write_fury_fixture "$FURY_PLUGIN_WITHOUT_SKILL_DIRECTORY" false
write_fury_fixture "$FURY_PLUGIN_SYMLINK_SKILL_DIRECTORY" false

mkdir -p "$GRID_PLUGIN_SYMLINK_SKILL_DIRECTORY/skills/grid"
printf '%s\n' '# Grid symlink target fixture' > "$TEMP_DIRECTORY/grid-skill-target.md"
ln -s "$TEMP_DIRECTORY/grid-skill-target.md" \
  "$GRID_PLUGIN_SYMLINK_SKILL_DIRECTORY/skills/grid/SKILL.md"
printf '%s\n' '# Fury symlink target fixture' > "$TEMP_DIRECTORY/fury-skill-target.md"
ln -s "$TEMP_DIRECTORY/fury-skill-target.md" \
  "$FURY_PLUGIN_SYMLINK_SKILL_DIRECTORY/skills/fury-services-documentation/SKILL.md"

cat > "$FAKE_BIN/claude" <<'STUB'
#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "list" ] && [ "${3:-}" = "--json" ] && [ "$#" -eq 3 ]; then
  printf '%s\n' 'claude plugin list' >> "$PROVIDER_LOG"
  case "${CLAUDE_INVENTORY_SCENARIO:-success}" in
    command-failure) exit 9 ;;
    invalid-response) printf '%s\n' '{"unexpected":true}' ;;
    grid-missing)
      jq -nc --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '[{id:"fury-services@tech-plugins-marketplace",enabled:true,version:"1.4.0",installPath:$fury_path}]'
      ;;
    grid-disabled)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '[
          {id:"grid-sharing@tech-plugins-marketplace",enabled:false,version:"1.2.3",installPath:$grid_path},
          {id:"fury-services@tech-plugins-marketplace",enabled:true,version:"1.4.0",installPath:$fury_path}
        ]'
      ;;
    grid-ambiguous)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '[
          {id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$grid_path},
          {id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$grid_path},
          {id:"fury-services@tech-plugins-marketplace",enabled:true,version:"1.4.0",installPath:$fury_path}
        ]'
      ;;
    grid-invalid)
      jq -nc --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '[
          {id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:"relative/path"},
          {id:"fury-services@tech-plugins-marketplace",enabled:true,version:"1.4.0",installPath:$fury_path}
        ]'
      ;;
    fury-missing)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" \
        '[{id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$grid_path}]'
      ;;
    fury-disabled)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '[
          {id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$grid_path},
          {id:"fury-services@tech-plugins-marketplace",enabled:false,version:"1.4.0",installPath:$fury_path}
        ]'
      ;;
    fury-ambiguous)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '[
          {id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$grid_path},
          {id:"fury-services@tech-plugins-marketplace",enabled:true,version:"1.4.0",installPath:$fury_path},
          {id:"fury-services@tech-plugins-marketplace",enabled:true,version:"1.4.0",installPath:$fury_path}
        ]'
      ;;
    fury-invalid)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '[
          {id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$grid_path},
          {id:"fury-services@tech-plugins-marketplace",enabled:true,version:"not-semver",installPath:$fury_path}
        ]'
      ;;
    *)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '[
          {id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$grid_path},
          {id:"fury-services@tech-plugins-marketplace",enabled:true,version:"1.4.0",installPath:$fury_path}
        ]'
      ;;
  esac
  exit 0
fi

if [ "${1:-}" = "mcp" ] && [ "${2:-}" = "list" ] && [ "$#" -eq 2 ]; then
  printf '%s\n' 'claude mcp list' >> "$PROVIDER_LOG"
  expected='plugin:fury-services:fury: mcp-remote-proxy https://mcp-services-gateway.furycloud.io/v1/servers/fury --headers x-origin fury-services-plugin --timeout 300'
  case "${CLAUDE_MCP_SCENARIO:-success}" in
    command-failure) exit 8 ;;
    not-configured) printf '%s\n' 'No MCP servers configured.' ;;
    disconnected) printf '%s\n' "$expected - ✘ Failed to connect" ;;
    legacy-connected) printf '%s\n' "$expected - ✓ Connected" ;;
    invalid-response) printf '%s\n%s\n' "$expected - ✔ Connected" "$expected - ✔ Connected" ;;
    *) printf '%s\n' "$expected - ✔ Connected" ;;
  esac
  exit 0
fi

printf 'unexpected claude invocation: %s\n' "$*" >&2
exit 64
STUB

cat > "$FAKE_BIN/codex" <<'STUB'
#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "list" ] \
  && [ "${3:-}" = "--marketplace" ] && [ "${4:-}" = "tech-plugins-marketplace" ] \
  && [ "${5:-}" = "--json" ] && [ "$#" -eq 5 ]; then
  printf '%s\n' 'codex plugin list' >> "$PROVIDER_LOG"
  case "${CODEX_INVENTORY_SCENARIO:-success}" in
    command-failure) exit 9 ;;
    invalid-response) printf '%s\n' '[]' ;;
    grid-missing)
      jq -nc --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '{installed:[{pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:true,version:"1.4.0",source:{path:$fury_path}}]}'
      ;;
    grid-disabled)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '{installed:[
          {pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:false,version:"1.2.3",source:{path:$grid_path}},
          {pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:true,version:"1.4.0",source:{path:$fury_path}}
        ]}'
      ;;
    grid-ambiguous)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '{installed:[
          {pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$grid_path}},
          {pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$grid_path}},
          {pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:true,version:"1.4.0",source:{path:$fury_path}}
        ]}'
      ;;
    grid-invalid)
      jq -nc --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '{installed:[
          {pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:"relative/path"}},
          {pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:true,version:"1.4.0",source:{path:$fury_path}}
        ]}'
      ;;
    fury-missing)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" \
        '{installed:[{pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$grid_path}}]}'
      ;;
    fury-disabled)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '{installed:[
          {pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$grid_path}},
          {pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:false,version:"1.4.0",source:{path:$fury_path}}
        ]}'
      ;;
    fury-ambiguous)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '{installed:[
          {pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$grid_path}},
          {pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:true,version:"1.4.0",source:{path:$fury_path}},
          {pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:true,version:"1.4.0",source:{path:$fury_path}}
        ]}'
      ;;
    fury-invalid)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '{installed:[
          {pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$grid_path}},
          {pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:true,version:"not-semver",source:{path:$fury_path}}
        ]}'
      ;;
    *)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" --arg fury_path "$FAKE_FURY_PLUGIN_INSTALL_PATH" \
        '{installed:[
          {pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$grid_path}},
          {pluginId:"fury-services@tech-plugins-marketplace",installed:true,enabled:true,version:"1.4.0",source:{path:$fury_path}}
        ]}'
      ;;
  esac
  exit 0
fi

if [ "${1:-}" = "mcp" ] && [ "${2:-}" = "list" ] && [ "${3:-}" = "--json" ] && [ "$#" -eq 3 ]; then
  printf '%s\n' 'codex mcp list' >> "$PROVIDER_LOG"
  case "${CODEX_MCP_SCENARIO:-success}" in
    command-failure) exit 8 ;;
    not-configured) printf '%s\n' '[]' ;;
    disconnected)
      jq -nc '[{name:"fury",enabled:false,disabled_reason:"connection unavailable",transport:{type:"stdio",command:"mcp-remote-proxy",args:["https://mcp-services-gateway.furycloud.io/v1/servers/fury","--headers","x-origin","fury-services-plugin","--timeout","300"]}}]'
      ;;
    invalid-response) printf '%s\n' '{"unexpected":true}' ;;
    *)
      jq -nc '[{name:"fury",enabled:true,disabled_reason:null,transport:{type:"stdio",command:"mcp-remote-proxy",args:["https://mcp-services-gateway.furycloud.io/v1/servers/fury","--headers","x-origin","fury-services-plugin","--timeout","300"]}}]'
      ;;
  esac
  exit 0
fi

printf 'unexpected codex invocation: %s\n' "$*" >&2
exit 64
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
  if [ -f "$PROVIDER_LOG" ]; then
    printf '%s\n' '--- provider log ---' >&2
    /bin/cat "$PROVIDER_LOG" >&2
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

command_count() {
  local exact_line="$1"
  local count

  count="$(grep -Fxc -- "$exact_line" "$PROVIDER_LOG" || true)"
  printf '%s' "$count"
}

assert_provider_calls() {
  local provider="$1"
  local expected_inventory_count="$2"
  local expected_mcp_count="$3"

  assert_equal "$expected_inventory_count" "$(command_count "$provider plugin list")" \
    "$provider inventory call count is invalid"
  assert_equal "$expected_mcp_count" "$(command_count "$provider mcp list")" \
    "$provider MCP call count is invalid"
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
  local mcp_scenario="$3"
  local http_scenario="$4"
  local grid_install_path="$5"
  local fury_install_path="$6"
  shift 6

  reset_run_state
  set +e
  PATH="$TEST_PATH" \
    PROVIDER_LOG="$PROVIDER_LOG" \
    CURL_LOG="$CURL_LOG" \
    CURL_STATE_DIRECTORY="$TEMP_DIRECTORY/curl-state" \
    FAKE_GRID_PLUGIN_INSTALL_PATH="$grid_install_path" \
    FAKE_FURY_PLUGIN_INSTALL_PATH="$fury_install_path" \
    CLAUDE_INVENTORY_SCENARIO="${CLAUDE_INVENTORY_SCENARIO_OVERRIDE:-$inventory_scenario}" \
    CODEX_INVENTORY_SCENARIO="${CODEX_INVENTORY_SCENARIO_OVERRIDE:-$inventory_scenario}" \
    CLAUDE_MCP_SCENARIO="${CLAUDE_MCP_SCENARIO_OVERRIDE:-$mcp_scenario}" \
    CODEX_MCP_SCENARIO="${CODEX_MCP_SCENARIO_OVERRIDE:-$mcp_scenario}" \
    HTTP_SCENARIO="$http_scenario" \
    bash "$CHECKER" --provider "$provider" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
  LAST_STATUS=$?
  set -e

  assert_equal "1" "$(wc -l < "$STDOUT_FILE" | tr -d ' ')" \
    "checker stdout must contain exactly one line"
  jq -e 'type == "object"' "$STDOUT_FILE" >/dev/null || fail "checker stdout must be valid JSON"
  if grep -Eq 'PRIVATE_|SECRET_' "$STDOUT_FILE"; then
    fail "checker stdout leaked a private fixture"
  fi
  if grep -Eq 'PRIVATE_|SECRET_' "$STDERR_FILE"; then
    fail "checker stderr leaked a private fixture"
  fi
}

assert_failure() {
  local expected_exit="$1"
  local expected_code="$2"

  assert_equal "$expected_exit" "$LAST_STATUS" "unexpected checker exit code"
  assert_json ".ok == false and .exit_code == $expected_exit and any(.failures[]; .code == \"$expected_code\")" \
    "missing expected failure $expected_code"
}

EXPECTED_CHECK_NAMES='[
  "dependencies",
  "configuration",
  "provider_inventory",
  "grid_plugin",
  "grid_required_skill",
  "fury_plugin",
  "fury_required_skill",
  "fury_manifest",
  "fury_mcp_declaration",
  "fury_mcp_cli",
  "ping",
  "skill_version",
  "identity",
  "general_read",
  "required_document"
]'

run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_equal 0 "$LAST_STATUS" "Claude success should exit zero"
assert_json ".schema_version == 2 and .scope == \"shell\" and .ok == true and .exit_code == 0 and .provider == \"claude\" and .source == \"fresh\" and (.checks | map(.name)) == $EXPECTED_CHECK_NAMES and all(.checks[]; .ok == true and .status == \"passed\")" \
  "Claude success contract is invalid"
assert_provider_calls claude 1 1
if grep -Eq 'PRIVATE_|SECRET_|grid-sharing-plugin|fury-services-plugin' "$STDOUT_FILE"; then
  fail "checker stdout leaked a body, identity, token, or plugin path fixture"
fi
if grep -Eq 'PRIVATE_|SECRET_|grid-sharing-plugin|fury-services-plugin' "$STDERR_FILE"; then
  fail "checker stderr leaked a body, identity, token, or plugin path fixture"
fi
printf 'ok - Claude schema 2 success, one inventory call, and privacy contract\n'

run_checker claude success legacy-connected success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_equal 0 "$LAST_STATUS" "Claude legacy connected marker should succeed"
assert_json ".schema_version == 2 and .scope == \"shell\" and .ok == true and .exit_code == 0 and .provider == \"claude\" and (.checks | map(.name)) == $EXPECTED_CHECK_NAMES and all(.checks[]; .status == \"passed\")" \
  "Claude legacy connected marker success contract is invalid"
assert_provider_calls claude 1 1
printf 'ok - Claude legacy U+2713 connected marker is accepted\n'

run_checker codex success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_equal 0 "$LAST_STATUS" "Codex success should exit zero"
assert_json ".schema_version == 2 and .scope == \"shell\" and .ok == true and .exit_code == 0 and .provider == \"codex\" and (.checks | map(.name)) == $EXPECTED_CHECK_NAMES and all(.checks[]; .status == \"passed\")" \
  "Codex success contract is invalid"
assert_provider_calls codex 1 1
printf 'ok - Codex schema 2 success and one inventory call\n'

run_checker claude grid-missing success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 PLUGIN_NOT_INSTALLED
printf 'ok - missing Grid plugin fails closed\n'

run_checker claude grid-disabled success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 PLUGIN_DISABLED
printf 'ok - disabled Grid plugin fails closed\n'

run_checker claude grid-ambiguous success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 PLUGIN_INVENTORY_AMBIGUOUS
printf 'ok - ambiguous Grid inventory fails closed\n'

run_checker claude grid-invalid success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 PLUGIN_INVENTORY_INVALID
printf 'ok - invalid Grid inventory metadata fails closed\n'

GRID_PLUGIN_WITHOUT_SKILL_DIRECTORY="$TEMP_DIRECTORY/grid-plugin-without-skill"
mkdir -p "$GRID_PLUGIN_WITHOUT_SKILL_DIRECTORY"
run_checker claude success success success "$GRID_PLUGIN_WITHOUT_SKILL_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 REQUIRED_SKILL_UNAVAILABLE
printf 'ok - missing Grid required skill fails closed\n'

run_checker claude success success success "$GRID_PLUGIN_SYMLINK_SKILL_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 REQUIRED_SKILL_UNAVAILABLE
printf 'ok - symlinked Grid required skill fails closed\n'

run_checker claude fury-missing success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_PLUGIN_NOT_INSTALLED
assert_json 'all(.checks[] | select(.name == "fury_required_skill" or .name == "fury_manifest" or .name == "fury_mcp_declaration" or .name == "fury_mcp_cli"); .status == "not_run" and .failure_code == "FURY_PLUGIN_NOT_INSTALLED")' \
  "missing Fury plugin must block all dependent Fury checks"
assert_provider_calls claude 1 0
assert_empty_file "$CURL_LOG" "missing Fury plugin must short-circuit before Grid HTTP probes"
printf 'ok - missing Fury plugin fails closed before MCP CLI and Grid probes\n'

run_checker claude fury-disabled success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_PLUGIN_DISABLED
printf 'ok - disabled Fury plugin fails closed\n'

run_checker claude fury-ambiguous success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_PLUGIN_INVENTORY_AMBIGUOUS
printf 'ok - ambiguous Fury inventory fails closed\n'

run_checker claude fury-invalid success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_PLUGIN_INVENTORY_INVALID
printf 'ok - invalid Fury metadata fails closed\n'

run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_WITHOUT_SKILL_DIRECTORY"
assert_failure 10 FURY_REQUIRED_SKILL_UNAVAILABLE
printf 'ok - missing Fury required skill fails closed\n'

run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_SYMLINK_SKILL_DIRECTORY"
assert_failure 10 FURY_REQUIRED_SKILL_UNAVAILABLE
printf 'ok - symlinked Fury required skill fails closed\n'

mv "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json" "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json.saved"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MANIFEST_UNAVAILABLE
mv "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json.saved" "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json"
printf 'ok - unavailable Claude Fury manifest fails closed\n'

printf '%s\n' '{"name":"wrong","version":"1.4.0"}' > "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MANIFEST_INVALID
write_fury_fixture "$FURY_PLUGIN_DIRECTORY" true
printf 'ok - invalid Claude Fury manifest fails closed\n'

jq '.version = "9.9.9"' "$FURY_PLUGIN_DIRECTORY/.codex-plugin/plugin.json" > "$TEMP_DIRECTORY/codex-version-mismatch.json"
mv "$TEMP_DIRECTORY/codex-version-mismatch.json" "$FURY_PLUGIN_DIRECTORY/.codex-plugin/plugin.json"
run_checker codex success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MANIFEST_INVALID
write_fury_fixture "$FURY_PLUGIN_DIRECTORY" true
printf 'ok - provider manifest version mismatch fails closed\n'

mv "$FURY_PLUGIN_DIRECTORY/.mcp.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json.saved"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_DECLARATION_UNAVAILABLE
mv "$FURY_PLUGIN_DIRECTORY/.mcp.json.saved" "$FURY_PLUGIN_DIRECTORY/.mcp.json"
printf 'ok - unavailable Fury MCP declaration fails closed\n'

jq '.mcpServers.fury.args[-1] = "301"' "$FURY_PLUGIN_DIRECTORY/.mcp.json" > "$TEMP_DIRECTORY/invalid-mcp-declaration.json"
mv "$TEMP_DIRECTORY/invalid-mcp-declaration.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_DECLARATION_INVALID
write_fury_fixture "$FURY_PLUGIN_DIRECTORY" true
printf 'ok - invalid Fury MCP declaration fails closed\n'

run_checker claude success command-failure success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_CLI_CHECK_FAILED
printf 'ok - Claude MCP CLI command failure is reported\n'

run_checker claude success not-configured success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_NOT_CONFIGURED
printf 'ok - Claude Fury MCP not configured is reported\n'

run_checker claude success disconnected success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_CONNECTION_UNAVAILABLE
printf 'ok - Claude Fury MCP disconnection is reported\n'

run_checker claude success invalid-response success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_CLI_RESPONSE_INVALID
printf 'ok - Claude invalid MCP response is reported\n'

run_checker codex success command-failure success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_CLI_CHECK_FAILED
printf 'ok - Codex MCP CLI command failure is reported\n'

run_checker codex success not-configured success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_NOT_CONFIGURED
printf 'ok - Codex Fury MCP not configured is reported\n'

run_checker codex success disconnected success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_CONNECTION_UNAVAILABLE
printf 'ok - Codex Fury MCP disconnection is reported\n'

run_checker codex success invalid-response success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 FURY_MCP_CLI_RESPONSE_INVALID
printf 'ok - Codex invalid MCP response is reported\n'

run_checker copilot success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 2 PROVIDER_INVENTORY_UNSUPPORTED
assert_empty_file "$PROVIDER_LOG" "Copilot inventory must not be inferred from CLI execution"
assert_empty_file "$CURL_LOG" "unsupported Copilot must short-circuit before Grid HTTP probes"
printf 'ok - Copilot inventory is unsupported and skips Grid probes\n'

run_checker claude success success identity-401 "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 22 GRID_IDENTITY_UNAVAILABLE
assert_json 'any(.checks[]; .name == "identity" and .http_status == 401 and .attempts == 1)' \
  "identity 401 metadata is invalid"
printf 'ok - identity 401 maps to exit 22\n'

run_checker claude success success document-403 "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 24 REQUIRED_DOCUMENT_FORBIDDEN
printf 'ok - document 403 maps to exit 24\n'

run_checker claude success success document-404 "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 24 REQUIRED_DOCUMENT_NOT_FOUND
printf 'ok - document 404 maps to exit 24\n'

run_checker claude success success rate-limit "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 25 GRID_RATE_LIMITED
assert_json 'any(.checks[]; .name == "skill_version" and .http_status == 429 and .attempts == 1 and .retry_after_seconds == 120)' \
  "Retry-After must be sanitized and must not trigger a retry"
if grep -Eq '000120|SECRET_HEADER_FIXTURE|PRIVATE_RATE_LIMIT_BODY' "$STDOUT_FILE"; then
  fail "rate-limit output leaked unsanitized headers or response body"
fi
printf 'ok - rate limiting preserves only sanitized Retry-After\n'

run_checker claude success success service-retry "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_equal 0 "$LAST_STATUS" "one transient 5xx should recover"
assert_json 'any(.checks[]; .name == "ping" and .attempts == 2 and .http_status == 200)' \
  "ping should report exactly two attempts"
assert_equal 2 "$(grep -c '/ping$' "$CURL_LOG")" "5xx must be retried exactly once"
printf 'ok - 5xx retries exactly once\n'

run_checker claude success success transport "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 20 GRID_TRANSPORT_FAILED
assert_json 'any(.checks[]; .name == "ping" and .attempts == 2 and .http_status == null)' \
  "transport failure should report two attempts without HTTP status"
assert_equal 2 "$(grep -c '/ping$' "$CURL_LOG")" "transport failure must be retried exactly once"
printf 'ok - transport failure maps to exit 20\n'

run_checker claude success success invalid-version "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 21 PLUGIN_VERSION_RESPONSE_INVALID
printf 'ok - invalid version response maps to exit 21\n'

run_checker claude success success incompatible-version "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 21 PLUGIN_VERSION_INCOMPATIBLE
printf 'ok - incompatible plugin version maps to exit 21\n'

run_checker claude success success invalid-identity "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 22 GRID_IDENTITY_RESPONSE_INVALID
printf 'ok - invalid identity response maps to exit 22\n'

run_checker claude success success invalid-list "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 23 GENERAL_READ_RESPONSE_INVALID
printf 'ok - invalid document list maps to exit 23\n'

run_checker claude success success invalid-document "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 24 REQUIRED_DOCUMENT_RESPONSE_INVALID
printf 'ok - invalid required document maps to exit 24\n'

REUSE_FILE="$TEMP_DIRECTORY/reusable-result.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
cp "$STDOUT_FILE" "$REUSE_FILE"
chmod 600 "$REUSE_FILE"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$REUSE_FILE"
assert_equal 0 "$LAST_STATUS" "valid schema 2 reuse should succeed"
assert_json ".schema_version == 2 and .scope == \"shell\" and .source == \"reused\" and .provider == \"claude\" and (.checks | map(.name)) == $EXPECTED_CHECK_NAMES" \
  "valid schema 2 reuse should preserve the complete contract"
assert_empty_file "$PROVIDER_LOG" "valid reuse must not call provider inventory or MCP CLI"
assert_empty_file "$CURL_LOG" "valid reuse must not call Grid"
printf 'ok - valid schema 2 result is reused without external calls\n'

jq '.schema_version = 1' "$REUSE_FILE" > "$TEMP_DIRECTORY/schema-1-result.json"
chmod 600 "$TEMP_DIRECTORY/schema-1-result.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/schema-1-result.json"
assert_equal 0 "$LAST_STATUS" "schema 1 reuse should fall back to a fresh successful check"
assert_json '.schema_version == 2 and .source == "fresh" and .ok == true' \
  "schema 1 reuse must not be trusted"
assert_nonempty_file "$PROVIDER_LOG" "schema 1 reuse must re-run inventory and MCP checks"
assert_nonempty_file "$CURL_LOG" "schema 1 reuse must re-run Grid checks"
printf 'ok - schema 1 reuse is rejected and refreshed\n'

jq '.checked_at_epoch = 0' "$REUSE_FILE" > "$TEMP_DIRECTORY/stale-result.json"
chmod 600 "$TEMP_DIRECTORY/stale-result.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/stale-result.json"
assert_equal 0 "$LAST_STATUS" "stale reuse should run a fresh successful check"
assert_json '.source == "fresh" and .ok == true' "stale reuse must not be trusted"
assert_nonempty_file "$PROVIDER_LOG" "stale reuse must re-run provider checks"
assert_nonempty_file "$CURL_LOG" "stale reuse must re-run Grid checks"
printf 'ok - stale result triggers a fresh preflight\n'

jq '.checks[0].ok = false' "$REUSE_FILE" > "$TEMP_DIRECTORY/tampered-result.json"
chmod 600 "$TEMP_DIRECTORY/tampered-result.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/tampered-result.json"
assert_equal 0 "$LAST_STATUS" "tampered reuse should run a fresh successful check"
assert_json '.source == "fresh" and .ok == true' "tampered reuse must not be trusted"
assert_nonempty_file "$PROVIDER_LOG" "tampered reuse must re-run provider checks"
printf 'ok - tampered result triggers a fresh preflight\n'

cp "$REUSE_FILE" "$TEMP_DIRECTORY/unsafe-mode.json"
chmod 644 "$TEMP_DIRECTORY/unsafe-mode.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/unsafe-mode.json"
assert_failure 70 REUSE_RESULT_FILE_UNSAFE
assert_empty_file "$PROVIDER_LOG" "unsafe mode must fail before provider calls"
assert_empty_file "$CURL_LOG" "unsafe mode must fail before Grid calls"
printf 'ok - unsafe reuse mode maps to exit 70\n'

cp "$REUSE_FILE" "$TEMP_DIRECTORY/unsafe-group-write.json"
chmod 0620 "$TEMP_DIRECTORY/unsafe-group-write.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/unsafe-group-write.json"
assert_failure 70 REUSE_RESULT_FILE_UNSAFE
assert_empty_file "$PROVIDER_LOG" "mode 0620 must fail before provider calls"
assert_empty_file "$CURL_LOG" "mode 0620 must fail before Grid calls"
printf 'ok - mode 0620 reuse fails closed before external calls\n'

UNSAFE_PARENT_DIRECTORY="$TEMP_DIRECTORY/unsafe-parent"
mkdir "$UNSAFE_PARENT_DIRECTORY"
chmod 0770 "$UNSAFE_PARENT_DIRECTORY"
cp "$REUSE_FILE" "$UNSAFE_PARENT_DIRECTORY/reusable-result.json"
chmod 0600 "$UNSAFE_PARENT_DIRECTORY/reusable-result.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$UNSAFE_PARENT_DIRECTORY/reusable-result.json"
assert_failure 70 REUSE_RESULT_FILE_UNSAFE
assert_empty_file "$PROVIDER_LOG" "unsafe parent mode must fail before provider calls"
assert_empty_file "$CURL_LOG" "unsafe parent mode must fail before Grid calls"
printf 'ok - unsafe reuse parent mode maps to exit 70\n'

PRIVATE_PARENT_DIRECTORY="$TEMP_DIRECTORY/private-parent"
SYMLINKED_PARENT_DIRECTORY="$TEMP_DIRECTORY/symlinked-parent"
mkdir "$PRIVATE_PARENT_DIRECTORY"
chmod 0700 "$PRIVATE_PARENT_DIRECTORY"
cp "$REUSE_FILE" "$PRIVATE_PARENT_DIRECTORY/reusable-result.json"
chmod 0600 "$PRIVATE_PARENT_DIRECTORY/reusable-result.json"
ln -s "$PRIVATE_PARENT_DIRECTORY" "$SYMLINKED_PARENT_DIRECTORY"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$SYMLINKED_PARENT_DIRECTORY/reusable-result.json"
assert_failure 70 REUSE_RESULT_FILE_UNSAFE
assert_empty_file "$PROVIDER_LOG" "symlinked parent must fail before provider calls"
assert_empty_file "$CURL_LOG" "symlinked parent must fail before Grid calls"
printf 'ok - symlinked reuse parent maps to exit 70\n'

ln -s "$REUSE_FILE" "$TEMP_DIRECTORY/unsafe-link.json"
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/unsafe-link.json"
assert_failure 70 REUSE_RESULT_FILE_UNSAFE
assert_empty_file "$PROVIDER_LOG" "symlink reuse path must fail before provider calls"
printf 'ok - unsafe reuse path maps to exit 70\n'

if [ "$(id -u)" -eq 0 ]; then
  cp "$REUSE_FILE" "$TEMP_DIRECTORY/unsafe-owner.json"
  chown 65534 "$TEMP_DIRECTORY/unsafe-owner.json"
  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEMP_DIRECTORY/unsafe-owner.json"
  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  printf 'ok - unsafe reuse owner maps to exit 70\n'

  UNSAFE_OWNER_PARENT_DIRECTORY="$TEMP_DIRECTORY/unsafe-owner-parent"
  mkdir "$UNSAFE_OWNER_PARENT_DIRECTORY"
  cp "$REUSE_FILE" "$UNSAFE_OWNER_PARENT_DIRECTORY/reusable-result.json"
  chmod 0700 "$UNSAFE_OWNER_PARENT_DIRECTORY"
  chmod 0600 "$UNSAFE_OWNER_PARENT_DIRECTORY/reusable-result.json"
  chown 65534 "$UNSAFE_OWNER_PARENT_DIRECTORY"
  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$UNSAFE_OWNER_PARENT_DIRECTORY/reusable-result.json"
  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  assert_empty_file "$PROVIDER_LOG" "unsafe parent owner must fail before provider calls"
  assert_empty_file "$CURL_LOG" "unsafe parent owner must fail before Grid calls"
  printf 'ok - unsafe reuse parent owner maps to exit 70\n'
else
  printf 'ok - unsafe reuse owner skipped (requires portable owner change)\n'
  printf 'ok - unsafe reuse parent owner skipped (requires portable owner change)\n'
fi

RACE_REUSE_FILE="$TEMP_DIRECTORY/race-reuse-result.json"
RACE_MALICIOUS_FILE="$TEMP_DIRECTORY/race-malicious-result.json"
RACE_MARKER_FILE="$TEMP_DIRECTORY/race-triggered"
cp "$REUSE_FILE" "$RACE_REUSE_FILE"
jq '.provider = "codex"' "$REUSE_FILE" > "$RACE_MALICIOUS_FILE"
chmod 600 "$RACE_REUSE_FILE" "$RACE_MALICIOUS_FILE"
cat > "$FAKE_BIN/perl" <<'STUB'
#!/bin/bash
set -euo pipefail
if [ "$#" -eq 2 ] && [ -n "${RACE_REUSE_FILE:-}" ] && [ ! -e "$RACE_MARKER_FILE" ]; then
  rm -f -- "$RACE_REUSE_FILE"
  ln -s "$RACE_MALICIOUS_FILE" "$RACE_REUSE_FILE"
  : > "$RACE_MARKER_FILE"
fi
exec "$REAL_PERL" "$@"
STUB
chmod 700 "$FAKE_BIN/perl"
export REAL_PERL RACE_REUSE_FILE RACE_MALICIOUS_FILE RACE_MARKER_FILE
run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$RACE_REUSE_FILE"
unset RACE_REUSE_FILE RACE_MALICIOUS_FILE RACE_MARKER_FILE
rm -f -- "$FAKE_BIN/perl"
assert_equal 0 "$LAST_STATUS" "path replacement after FD open must not change reused result"
assert_json '.provider == "claude" and .source == "reused" and .ok == true' \
  "checker must consume the original descriptor snapshot"
[ -L "$TEMP_DIRECTORY/race-reuse-result.json" ] || fail "race fixture did not replace original path"
assert_empty_file "$PROVIDER_LOG" "descriptor snapshot reuse must not call provider inventory"
assert_empty_file "$CURL_LOG" "descriptor snapshot reuse must not call Grid"
printf 'ok - path replacement after FD open cannot alter reused snapshot\n'

CODEX_INVENTORY_SCENARIO_OVERRIDE=fury-missing
CLAUDE_INVENTORY_SCENARIO_OVERRIDE=success
run_checker auto success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
unset CODEX_INVENTORY_SCENARIO_OVERRIDE CLAUDE_INVENTORY_SCENARIO_OVERRIDE
assert_equal 0 "$LAST_STATUS" "auto should select the first complete provider"
assert_json '.provider == "claude" and .ok == true and .schema_version == 2' \
  "auto should reject Grid-only Codex and select complete Claude"
assert_provider_calls codex 1 0
assert_provider_calls claude 1 1
assert_equal 1 "$(grep -c '/ping$' "$CURL_LOG")" "auto must run Grid HTTP probes only for selected Claude"
printf 'ok - auto short-circuits incomplete Codex and probes selected Claude only\n'

run_checker claude command-failure success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
assert_failure 10 PROVIDER_INVENTORY_FAILED
assert_json 'all(.checks[] | select(
  .name == "grid_plugin" or
  .name == "grid_required_skill" or
  .name == "fury_plugin" or
  .name == "fury_required_skill" or
  .name == "fury_manifest" or
  .name == "fury_mcp_declaration" or
  .name == "fury_mcp_cli"
); .status == "not_run" and .failure_code == "PROVIDER_INVENTORY_FAILED")' \
  "provider inventory failure must propagate to every dependent not-run check"
assert_provider_calls claude 1 0
assert_empty_file "$CURL_LOG" "provider inventory failure must short-circuit before Grid HTTP probes"
printf 'ok - provider inventory failure propagates and skips Grid probes\n'

printf 'All check-groot-queue-readiness tests passed.\n'
