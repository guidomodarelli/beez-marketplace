#!/usr/bin/env bash

setup_launcher_fixture() {
  RUNNER="$BATS_TEST_DIRNAME/../scripts/run-groot-queue.sh"
  REAL_JQ="$(command -v jq)"
  TEST_ROOT="$BATS_TEST_TMPDIR/launcher"
  FAKE_BIN="$TEST_ROOT/bin"
  GRID_PLUGIN_DIRECTORY="$TEST_ROOT/grid-sharing-plugin"
  FURY_PLUGIN_DIRECTORY="$TEST_ROOT/fury-services-plugin"
  INVENTORY_LOG="$TEST_ROOT/inventory.log"
  MCP_LOG="$TEST_ROOT/mcp.log"
  CHILD_LOG="$TEST_ROOT/child.log"
  CURL_LOG="$TEST_ROOT/curl.log"
  STDOUT_FILE="$TEST_ROOT/stdout.log"
  STDERR_FILE="$TEST_ROOT/stderr.log"
  TEST_PATH="$FAKE_BIN:/usr/bin:/bin"
  RUN_STATUS=0

  mkdir -p \
    "$FAKE_BIN" \
    "$GRID_PLUGIN_DIRECTORY/skills/grid" \
    "$FURY_PLUGIN_DIRECTORY/.claude-plugin" \
    "$FURY_PLUGIN_DIRECTORY/.codex-plugin" \
    "$FURY_PLUGIN_DIRECTORY/skills/fury-services-documentation"
  chmod 700 "$TEST_ROOT" "$FAKE_BIN"
  printf '%s\n' '# Grid runner fixture' > "$GRID_PLUGIN_DIRECTORY/skills/grid/SKILL.md"
  printf '%s\n' '# Fury services documentation runner fixture' > \
    "$FURY_PLUGIN_DIRECTORY/skills/fury-services-documentation/SKILL.md"
  ln -s "$REAL_JQ" "$FAKE_BIN/jq"

  create_plugin_fixtures
  create_provider_stubs
  reset_run_state
}

create_plugin_fixtures() {
  cat > "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fury-services",
  "version": "1.4.0",
  "description": "Fury services fixture"
}
JSON

  cat > "$FURY_PLUGIN_DIRECTORY/.codex-plugin/plugin.json" <<'JSON'
{
  "name": "fury-services",
  "version": "1.4.0",
  "description": "Fury services fixture",
  "skills": "./skills/",
  "mcpServers": "./.mcp.json"
}
JSON

  cat > "$FURY_PLUGIN_DIRECTORY/.mcp.json" <<'JSON'
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

create_provider_stubs() {
  cat > "$FAKE_BIN/claude" <<'STUB'
#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "list" ] && [ "${3:-}" = "--json" ] && [ "$#" -eq 3 ]; then
  printf '%s\n' 'claude inventory' >> "$INVENTORY_LOG"
  case "${CLAUDE_INVENTORY:-success}" in
    command-failure) exit 9 ;;
    fury-missing)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" \
        '[{id:"grid-sharing@tech-plugins-marketplace",enabled:true,version:"1.2.3",installPath:$grid_path}]'
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
  printf '%s\n' 'claude mcp' >> "$MCP_LOG"
  printf '%s\n' 'plugin:fury-services:fury: mcp-remote-proxy https://mcp-services-gateway.furycloud.io/v1/servers/fury --headers x-origin fury-services-plugin --timeout 300 - ✔ Connected'
  exit 0
fi

printf 'claude child args=%s\n' "$*" >> "$CHILD_LOG"
printf 'provider=%s\n' "${GROOT_QUEUE_ACTIVE_PROVIDER:-unset}" >> "$CHILD_LOG"
printf 'readiness=%s\n' "${GROOT_QUEUE_READINESS_RESULT_FILE:-unset}" >> "$CHILD_LOG"
printf 'legacy_preflight=%s\n' "${GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE:-unset}" >> "$CHILD_LOG"
printf 'fury_global_install=%s\n' "${FURY_CODEX_MCP_GLOBAL_INSTALL:-unset}" >> "$CHILD_LOG"
if [ -n "${GROOT_QUEUE_READINESS_RESULT_FILE:-}" ]; then
  if stat -f '%Lp' "$GROOT_QUEUE_READINESS_RESULT_FILE" >/dev/null 2>&1; then
    mode="$(stat -f '%Lp' "$GROOT_QUEUE_READINESS_RESULT_FILE")"
  else
    mode="$(stat -c '%a' "$GROOT_QUEUE_READINESS_RESULT_FILE")"
  fi
  jq -e '
    .schema_version == 2 and
    .scope == "shell" and
    .provider == "claude" and
    .ok == true and
    .exit_code == 0 and
    (.checks | map(.name)) == [
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
    ]
  ' "$GROOT_QUEUE_READINESS_RESULT_FILE" >/dev/null
  [ "$mode" = "600" ]
  printf 'readiness_valid=true mode=%s checks=15\n' "$mode" >> "$CHILD_LOG"
fi
printf 'claude child complete\n'
STUB

  cat > "$FAKE_BIN/codex" <<'STUB'
#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "list" ] \
  && [ "${3:-}" = "--marketplace" ] && [ "${4:-}" = "tech-plugins-marketplace" ] \
  && [ "${5:-}" = "--json" ] && [ "$#" -eq 5 ]; then
  printf '%s\n' 'codex inventory' >> "$INVENTORY_LOG"
  case "${CODEX_INVENTORY:-success}" in
    command-failure) exit 9 ;;
    fury-missing)
      jq -nc --arg grid_path "$FAKE_GRID_PLUGIN_INSTALL_PATH" \
        '{installed:[{pluginId:"grid-sharing@tech-plugins-marketplace",installed:true,enabled:true,version:"1.2.3",source:{path:$grid_path}}]}'
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
  printf '%s\n' 'codex mcp' >> "$MCP_LOG"
  jq -nc '[{name:"fury",enabled:true,disabled_reason:null,transport:{type:"stdio",command:"mcp-remote-proxy",args:["https://mcp-services-gateway.furycloud.io/v1/servers/fury","--headers","x-origin","fury-services-plugin","--timeout","300"]}}]'
  exit 0
fi

printf 'codex child args=%s\n' "$*" >> "$CHILD_LOG"
printf 'provider=%s\n' "${GROOT_QUEUE_ACTIVE_PROVIDER:-unset}" >> "$CHILD_LOG"
printf 'readiness=%s\n' "${GROOT_QUEUE_READINESS_RESULT_FILE:-unset}" >> "$CHILD_LOG"
printf 'legacy_preflight=%s\n' "${GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE:-unset}" >> "$CHILD_LOG"
printf 'fury_global_install=%s\n' "${FURY_CODEX_MCP_GLOBAL_INSTALL:-unset}" >> "$CHILD_LOG"
if [ -n "${GROOT_QUEUE_READINESS_RESULT_FILE:-}" ]; then
  if stat -f '%Lp' "$GROOT_QUEUE_READINESS_RESULT_FILE" >/dev/null 2>&1; then
    mode="$(stat -f '%Lp' "$GROOT_QUEUE_READINESS_RESULT_FILE")"
  else
    mode="$(stat -c '%a' "$GROOT_QUEUE_READINESS_RESULT_FILE")"
  fi
  jq -e '
    .schema_version == 2 and
    .scope == "shell" and
    .provider == "codex" and
    .ok == true and
    .exit_code == 0 and
    (.checks | length) == 15
  ' "$GROOT_QUEUE_READINESS_RESULT_FILE" >/dev/null
  [ "$mode" = "600" ]
  printf 'readiness_valid=true mode=%s checks=15\n' "$mode" >> "$CHILD_LOG"
fi
printf 'codex child complete\n'
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

  chmod 700 "$FAKE_BIN/claude" "$FAKE_BIN/codex" "$FAKE_BIN/curl"
}

reset_run_state() {
  : > "$INVENTORY_LOG"
  : > "$MCP_LOG"
  : > "$CHILD_LOG"
  : > "$CURL_LOG"
  : > "$STDOUT_FILE"
  : > "$STDERR_FILE"
}

run_launcher() {
  reset_run_state
  set +e
  PATH="$TEST_PATH" \
    INVENTORY_LOG="$INVENTORY_LOG" \
    MCP_LOG="$MCP_LOG" \
    CHILD_LOG="$CHILD_LOG" \
    CURL_LOG="$CURL_LOG" \
    FAKE_GRID_PLUGIN_INSTALL_PATH="$GRID_PLUGIN_DIRECTORY" \
    FAKE_FURY_PLUGIN_INSTALL_PATH="$FURY_PLUGIN_DIRECTORY" \
    CLAUDE_INVENTORY="${CLAUDE_INVENTORY_SCENARIO:-success}" \
    CODEX_INVENTORY="${CODEX_INVENTORY_SCENARIO:-success}" \
    GROOT_QUEUE_READINESS_RESULT_FILE="${PARENT_READINESS_RESULT_FILE:-}" \
    GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE="${PARENT_GRID_PREFLIGHT_RESULT_FILE:-}" \
    bash "$RUNNER" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
  RUN_STATUS=$?
  set -e
}

create_untrusted_parent_results() {
  PARENT_READINESS_RESULT_FILE="$TEST_ROOT/untrusted-parent-readiness.json"
  PARENT_GRID_PREFLIGHT_RESULT_FILE="$TEST_ROOT/untrusted-legacy-preflight.json"
  printf '%s\n' '{"ok":true}' > "$PARENT_READINESS_RESULT_FILE"
  printf '%s\n' '{"ok":true}' > "$PARENT_GRID_PREFLIGHT_RESULT_FILE"
}

dump_launcher_logs() {
  local file_path
  for file_path in "$STDOUT_FILE" "$STDERR_FILE" "$INVENTORY_LOG" "$MCP_LOG" "$CHILD_LOG" "$CURL_LOG"; do
    printf '%s\n' "--- $file_path ---" >&2
    if [ -f "$file_path" ]; then
      /bin/cat "$file_path" >&2
    fi
  done
}

fail_with_logs() {
  printf 'FAIL: %s\n' "$1" >&2
  dump_launcher_logs
  return 1
}

assert_status() {
  local expected_status="$1"
  local message="$2"
  [ "$RUN_STATUS" -eq "$expected_status" ] || \
    fail_with_logs "$message (expected=$expected_status actual=$RUN_STATUS)"
}

assert_file_empty() {
  local file_path="$1"
  local message="$2"
  [ ! -s "$file_path" ] || fail_with_logs "$message"
}

assert_file_contains() {
  local file_path="$1"
  local expected_text="$2"
  local message="$3"
  grep -Fq -- "$expected_text" "$file_path" || fail_with_logs "$message"
}

assert_file_excludes() {
  local file_path="$1"
  local unexpected_text="$2"
  local message="$3"
  if grep -Fq -- "$unexpected_text" "$file_path"; then
    fail_with_logs "$message"
  fi
}

assert_match_count() {
  local expected_count="$1"
  local pattern="$2"
  local file_path="$3"
  local message="$4"
  local actual_count
  actual_count="$(grep -Ec -- "$pattern" "$file_path" || true)"
  [ "$actual_count" -eq "$expected_count" ] || \
    fail_with_logs "$message (expected=$expected_count actual=$actual_count)"
}

assert_fixed_count() {
  local expected_count="$1"
  local text="$2"
  local file_path="$3"
  local message="$4"
  local actual_count
  actual_count="$(grep -Fc -- "$text" "$file_path" || true)"
  [ "$actual_count" -eq "$expected_count" ] || \
    fail_with_logs "$message (expected=$expected_count actual=$actual_count)"
}

assert_invalid_launcher_case() {
  local description="$1"
  shift
  run_launcher "$@"
  assert_status 2 "$description should fail with exit 2"
  assert_file_empty "$INVENTORY_LOG" "$description must fail before checker inventory"
  assert_file_empty "$MCP_LOG" "$description must fail before MCP inspection"
  assert_file_empty "$CURL_LOG" "$description must fail before Grid"
  assert_file_empty "$CHILD_LOG" "$description must fail before provider invocation"
}
