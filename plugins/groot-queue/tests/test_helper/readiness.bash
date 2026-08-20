#!/usr/bin/env bash

setup_readiness_fixture() {
  umask 077
  TEST_ROOT="$BATS_TEST_TMPDIR/readiness"
  CHECKER="$BATS_TEST_DIRNAME/../skills/groot-queue/scripts/check-groot-queue-readiness.sh"
  REAL_JQ="$(command -v jq)"
  REAL_PERL="$(command -v perl)"
  FAKE_BIN="$TEST_ROOT/bin"
  GRID_PLUGIN_DIRECTORY="$TEST_ROOT/grid-sharing-plugin"
  FURY_PLUGIN_DIRECTORY="$TEST_ROOT/fury-services-plugin"
  FURY_PLUGIN_WITHOUT_SKILL_DIRECTORY="$TEST_ROOT/fury-services-plugin-without-skill"
  GRID_PLUGIN_SYMLINK_SKILL_DIRECTORY="$TEST_ROOT/grid-plugin-symlink-skill"
  FURY_PLUGIN_SYMLINK_SKILL_DIRECTORY="$TEST_ROOT/fury-plugin-symlink-skill"
  PROVIDER_LOG="$TEST_ROOT/provider.log"
  CURL_LOG="$TEST_ROOT/curl.log"
  STDOUT_FILE="$TEST_ROOT/stdout.json"
  STDERR_FILE="$TEST_ROOT/stderr.log"
  mkdir -p "$FAKE_BIN" "$GRID_PLUGIN_DIRECTORY/skills/grid"
  printf '%s\n' '# Grid test fixture' > "$GRID_PLUGIN_DIRECTORY/skills/grid/SKILL.md"
  ln -s "$REAL_JQ" "$FAKE_BIN/jq"
}

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

initialize_plugin_fixtures() {
write_fury_fixture "$FURY_PLUGIN_DIRECTORY" true
write_fury_fixture "$FURY_PLUGIN_WITHOUT_SKILL_DIRECTORY" false
write_fury_fixture "$FURY_PLUGIN_SYMLINK_SKILL_DIRECTORY" false

mkdir -p "$GRID_PLUGIN_SYMLINK_SKILL_DIRECTORY/skills/grid"
printf '%s\n' '# Grid symlink target fixture' > "$TEST_ROOT/grid-skill-target.md"
ln -s "$TEST_ROOT/grid-skill-target.md" \
  "$GRID_PLUGIN_SYMLINK_SKILL_DIRECTORY/skills/grid/SKILL.md"
printf '%s\n' '# Fury symlink target fixture' > "$TEST_ROOT/fury-skill-target.md"
ln -s "$TEST_ROOT/fury-skill-target.md" \
  "$FURY_PLUGIN_SYMLINK_SKILL_DIRECTORY/skills/fury-services-documentation/SKILL.md"
}

write_command_stubs() {
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

chmod 700 "$FAKE_BIN/claude" "$FAKE_BIN/codex" "$FAKE_BIN/curl"
}

readiness_fail() {
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
  [ "$actual" = "$expected" ] || readiness_fail "$message (expected=$expected actual=$actual)"
}

assert_json() {
  local filter="$1"
  local message="$2"
  jq -e "$filter" "$STDOUT_FILE" >/dev/null || readiness_fail "$message"
}

assert_empty_file() {
  local file_path="$1"
  local message="$2"
  [ ! -s "$file_path" ] || readiness_fail "$message"
}

assert_nonempty_file() {
  local file_path="$1"
  local message="$2"
  [ -s "$file_path" ] || readiness_fail "$message"
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
  /bin/rm -rf -- "$TEST_ROOT/curl-state"
  mkdir -p "$TEST_ROOT/curl-state"
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
    CURL_STATE_DIRECTORY="$TEST_ROOT/curl-state" \
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
  jq -e 'type == "object"' "$STDOUT_FILE" >/dev/null || readiness_fail "checker stdout must be valid JSON"
  if grep -Eq 'PRIVATE_|SECRET_' "$STDOUT_FILE"; then
    readiness_fail "checker stdout leaked a private fixture"
  fi
  if grep -Eq 'PRIVATE_|SECRET_' "$STDERR_FILE"; then
    readiness_fail "checker stderr leaked a private fixture"
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

setup() {
  setup_readiness_fixture
  initialize_plugin_fixtures
  write_command_stubs
  TEST_PATH="$FAKE_BIN:/usr/bin:/bin"
  LAST_STATUS=0
}

create_reuse_result() {
  REUSE_FILE="$TEST_ROOT/reusable-result.json"
  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_equal 0 "$LAST_STATUS" "reuse fixture creation should succeed"
  cp "$STDOUT_FILE" "$REUSE_FILE"
  chmod 600 "$REUSE_FILE"
}
