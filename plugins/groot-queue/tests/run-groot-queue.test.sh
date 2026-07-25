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
GRID_PLUGIN_DIRECTORY="$TEMP_DIRECTORY/grid-sharing-plugin"
FURY_PLUGIN_DIRECTORY="$TEMP_DIRECTORY/fury-services-plugin"
INVENTORY_LOG="$TEMP_DIRECTORY/inventory.log"
MCP_LOG="$TEMP_DIRECTORY/mcp.log"
CHILD_LOG="$TEMP_DIRECTORY/child.log"
CURL_LOG="$TEMP_DIRECTORY/curl.log"
STDOUT_FILE="$TEMP_DIRECTORY/stdout.log"
STDERR_FILE="$TEMP_DIRECTORY/stderr.log"
mkdir -p \
  "$FAKE_BIN" \
  "$GRID_PLUGIN_DIRECTORY/skills/grid" \
  "$FURY_PLUGIN_DIRECTORY/.claude-plugin" \
  "$FURY_PLUGIN_DIRECTORY/.codex-plugin" \
  "$FURY_PLUGIN_DIRECTORY/skills/fury-services-documentation"
printf '%s\n' '# Grid runner fixture' > "$GRID_PLUGIN_DIRECTORY/skills/grid/SKILL.md"
printf '%s\n' '# Fury services documentation runner fixture' > \
  "$FURY_PLUGIN_DIRECTORY/skills/fury-services-documentation/SKILL.md"
ln -s "$REAL_JQ" "$FAKE_BIN/jq"

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
  mode=""
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
  mode=""
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

cat > "$FAKE_BIN/copilot" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'copilot child args=%s\n' "$*" >> "$CHILD_LOG"
printf 'provider=%s\n' "${GROOT_QUEUE_ACTIVE_PROVIDER:-unset}" >> "$CHILD_LOG"
printf 'readiness=%s\n' "${GROOT_QUEUE_READINESS_RESULT_FILE:-unset}" >> "$CHILD_LOG"
printf 'legacy_preflight=%s\n' "${GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE:-unset}" >> "$CHILD_LOG"
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
  if [ -f "$INVENTORY_LOG" ]; then
    printf '%s\n' '--- inventory log ---' >&2
    /bin/cat "$INVENTORY_LOG" >&2
  fi
  if [ -f "$MCP_LOG" ]; then
    printf '%s\n' '--- MCP log ---' >&2
    /bin/cat "$MCP_LOG" >&2
  fi
  if [ -f "$CHILD_LOG" ]; then
    printf '%s\n' '--- child log ---' >&2
    /bin/cat "$CHILD_LOG" >&2
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
  : > "$MCP_LOG"
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
  LAST_STATUS=$?
  set -e
}

run_runner --help
assert_equal 0 "$LAST_STATUS" "global help should succeed"
assert_empty_file "$INVENTORY_LOG" "global help must not invoke checker inventory"
assert_empty_file "$MCP_LOG" "global help must not inspect Fury MCP"
assert_empty_file "$CURL_LOG" "global help must not invoke Grid"
assert_empty_file "$CHILD_LOG" "global help must not invoke a provider"
assert_contains "$STDOUT_FILE" 'run-groot-queue' "global help should render launcher usage"
printf 'ok - global help bypasses checker, MCP, and providers\n'

PARENT_READINESS_RESULT_FILE="$TEMP_DIRECTORY/untrusted-parent-readiness.json"
PARENT_GRID_PREFLIGHT_RESULT_FILE="$TEMP_DIRECTORY/untrusted-legacy-preflight.json"
printf '%s\n' '{"ok":true}' > "$PARENT_READINESS_RESULT_FILE"
printf '%s\n' '{"ok":true}' > "$PARENT_GRID_PREFLIGHT_RESULT_FILE"
run_runner --provider codex setup
unset PARENT_READINESS_RESULT_FILE PARENT_GRID_PREFLIGHT_RESULT_FILE
assert_equal 0 "$LAST_STATUS" "setup should invoke Codex successfully"
assert_empty_file "$INVENTORY_LOG" "setup must not invoke checker inventory"
assert_empty_file "$MCP_LOG" "setup launcher must not inspect Fury MCP"
assert_empty_file "$CURL_LOG" "setup must not invoke Grid in the launcher"
assert_contains "$CHILD_LOG" 'codex child args=' "setup should invoke Codex"
assert_contains "$CHILD_LOG" '/groot-queue setup' "setup prompt was not forwarded"
assert_contains "$CHILD_LOG" 'readiness=unset' "setup child must not receive parent or reusable readiness"
assert_contains "$CHILD_LOG" 'legacy_preflight=unset' "setup child must not trust the legacy preflight variable"
assert_contains "$CHILD_LOG" 'fury_global_install=0' "Codex setup must disable global Fury MCP installation"
printf 'ok - setup bypasses launcher gate and strips legacy readiness variables\n'

PARENT_READINESS_RESULT_FILE="$TEMP_DIRECTORY/untrusted-help-readiness.json"
PARENT_GRID_PREFLIGHT_RESULT_FILE="$TEMP_DIRECTORY/untrusted-help-preflight.json"
printf '%s\n' '{"ok":true}' > "$PARENT_READINESS_RESULT_FILE"
printf '%s\n' '{"ok":true}' > "$PARENT_GRID_PREFLIGHT_RESULT_FILE"
run_runner --provider codex list --help
unset PARENT_READINESS_RESULT_FILE PARENT_GRID_PREFLIGHT_RESULT_FILE
assert_equal 0 "$LAST_STATUS" "subcommand help should invoke Codex successfully"
assert_empty_file "$INVENTORY_LOG" "subcommand help must not invoke checker inventory"
assert_empty_file "$MCP_LOG" "subcommand help must not inspect Fury MCP"
assert_empty_file "$CURL_LOG" "subcommand help must not invoke Grid"
assert_contains "$CHILD_LOG" 'codex child args=' "list help should invoke Codex"
assert_contains "$CHILD_LOG" '/groot-queue list --help' "list help prompt was not forwarded"
assert_contains "$CHILD_LOG" 'readiness=unset' "help child must not receive parent readiness"
assert_contains "$CHILD_LOG" 'legacy_preflight=unset' "help child must not receive legacy preflight"
assert_contains "$CHILD_LOG" 'fury_global_install=0' "Codex help must disable global Fury MCP installation"
printf 'ok - subcommand help bypasses launcher gate and disables global Codex install\n'

CLAUDE_INVENTORY_SCENARIO=fury-missing
run_runner --provider claude list
unset CLAUDE_INVENTORY_SCENARIO
assert_equal 1 "$LAST_STATUS" "explicit provider missing Fury should be blocked"
assert_contains "$INVENTORY_LOG" 'claude inventory' "explicit Claude should inspect its inventory"
assert_not_contains "$INVENTORY_LOG" 'codex inventory' "explicit provider must not fall back to Codex"
assert_empty_file "$MCP_LOG" "missing Fury must block before MCP CLI inspection"
assert_empty_file "$CHILD_LOG" "failed explicit provider must not launch a child"
assert_contains "$STDERR_FILE" 'FURY_PLUGIN_NOT_INSTALLED' "runner should expose the safe Fury failure code"
printf 'ok - explicit provider missing Fury blocks before child without fallback\n'

PARENT_READINESS_RESULT_FILE="$TEMP_DIRECTORY/untrusted-operational-readiness.json"
PARENT_GRID_PREFLIGHT_RESULT_FILE="$TEMP_DIRECTORY/untrusted-operational-preflight.json"
printf '%s\n' '{"ok":true}' > "$PARENT_READINESS_RESULT_FILE"
printf '%s\n' '{"ok":true}' > "$PARENT_GRID_PREFLIGHT_RESULT_FILE"
run_runner --provider claude list
unset PARENT_READINESS_RESULT_FILE PARENT_GRID_PREFLIGHT_RESULT_FILE
assert_equal 0 "$LAST_STATUS" "successful Claude readiness should continue"
assert_contains "$INVENTORY_LOG" 'claude inventory' "Claude readiness should inspect plugin inventory"
assert_contains "$MCP_LOG" 'claude mcp' "Claude readiness should inspect Fury MCP CLI"
assert_equal 1 "$(grep -c '^claude child args=' "$CHILD_LOG")" "Claude child should launch exactly once"
assert_contains "$CHILD_LOG" '/groot-queue list' "operational prompt was not forwarded"
assert_contains "$CHILD_LOG" 'provider=claude' "child should receive active provider"
assert_contains "$CHILD_LOG" 'legacy_preflight=unset' "operational child must not receive legacy preflight"
assert_contains "$CHILD_LOG" 'readiness_valid=true mode=600 checks=15' \
  "child should receive a mode-600 schema 2 readiness result with 15 checks"
printf 'ok - Claude success launches child with private schema 2 readiness\n'

CODEX_INVENTORY_SCENARIO=fury-missing
run_runner list
unset CODEX_INVENTORY_SCENARIO
assert_equal 0 "$LAST_STATUS" "auto provider selection should reach complete Claude"
assert_contains "$INVENTORY_LOG" 'codex inventory' "auto mode should evaluate Codex first"
assert_contains "$INVENTORY_LOG" 'claude inventory' "auto mode should evaluate Claude after incomplete Codex"
assert_not_contains "$MCP_LOG" 'codex mcp' "Codex missing Fury must not reach MCP CLI inspection"
assert_contains "$MCP_LOG" 'claude mcp' "complete Claude should inspect Fury MCP"
assert_equal 1 "$(grep -c '/ping$' "$CURL_LOG")" "operational auto must probe Grid only for selected Claude"
assert_not_contains "$CHILD_LOG" 'copilot child' "unsupported Copilot must not be selected"
assert_not_contains "$CHILD_LOG" 'codex child args=' "incomplete Codex must not receive the prompt"
assert_equal 1 "$(grep -c '^claude child args=' "$CHILD_LOG")" "Claude should be selected exactly once"
assert_contains "$CHILD_LOG" 'provider=claude' "auto mode should expose Claude as active provider"
printf 'ok - auto avoids Copilot readiness, rejects Fury-missing Codex, and selects Claude\n'

run_runner --provider codex stats
assert_equal 0 "$LAST_STATUS" "complete explicit Codex should launch"
assert_contains "$INVENTORY_LOG" 'codex inventory' "Codex readiness should inspect plugin inventory"
assert_contains "$MCP_LOG" 'codex mcp' "Codex readiness should inspect Fury MCP CLI"
assert_not_contains "$INVENTORY_LOG" 'claude inventory' "explicit Codex must not inspect Claude"
assert_equal 1 "$(grep -c '^codex child args=' "$CHILD_LOG")" "Codex child should launch exactly once"
assert_contains "$CHILD_LOG" 'provider=codex' "Codex child should receive active provider"
assert_contains "$CHILD_LOG" 'readiness_valid=true mode=600 checks=15' \
  "Codex child should validate the complete readiness file"
assert_contains "$CHILD_LOG" 'fury_global_install=0' \
  "operational Codex must disable global Fury MCP installation"
printf 'ok - explicit complete Codex launches with private readiness and global install disabled\n'

run_invalid_case() {
  local description="$1"
  shift
  run_runner "$@"
  assert_equal 2 "$LAST_STATUS" "$description should fail with exit 2"
  assert_empty_file "$INVENTORY_LOG" "$description must fail before checker inventory"
  assert_empty_file "$MCP_LOG" "$description must fail before MCP inspection"
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
