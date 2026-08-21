#!/usr/bin/env bats

load 'test_helper/readiness.bash'

@test "Claude schema 2 success preserves calls and privacy contract" {
  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_equal 0 "$LAST_STATUS" "Claude success should exit zero"
  assert_json ".schema_version == 2 and .scope == \"shell\" and .ok == true and .exit_code == 0 and .provider == \"claude\" and .source == \"fresh\" and (.checks | map(.name)) == $EXPECTED_CHECK_NAMES and all(.checks[]; .ok == true and .status == \"passed\")" \
    "Claude success contract is invalid"
  assert_provider_calls claude 1 1
  if grep -Eq 'PRIVATE_|SECRET_|grid-sharing-plugin|fury-services-plugin' "$STDOUT_FILE"; then
    readiness_fail "checker stdout leaked a body, identity, token, or plugin path fixture"
  fi
  if grep -Eq 'PRIVATE_|SECRET_|grid-sharing-plugin|fury-services-plugin' "$STDERR_FILE"; then
    readiness_fail "checker stderr leaked a body, identity, token, or plugin path fixture"
  fi
}

@test "cleanup failure does not override successful exit status" {
  cat > "$FAKE_BIN/rm" <<'STUB'
#!/bin/bash
/bin/rm "$@"
exit 91
STUB
  chmod 700 "$FAKE_BIN/rm"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_equal 0 "$LAST_STATUS" "cleanup failure must preserve successful checker exit status"
  assert_json '.ok == true and .exit_code == 0 and .provider == "claude"' \
    "cleanup failure must preserve successful JSON contract"
}

@test "Claude accepts the legacy U+2713 connected marker" {
  run_checker claude success legacy-connected success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_equal 0 "$LAST_STATUS" "Claude legacy connected marker should succeed"
  assert_json ".schema_version == 2 and .scope == \"shell\" and .ok == true and .exit_code == 0 and .provider == \"claude\" and (.checks | map(.name)) == $EXPECTED_CHECK_NAMES and all(.checks[]; .status == \"passed\")" \
    "Claude legacy connected marker success contract is invalid"
  assert_provider_calls claude 1 1
}

@test "Codex schema 2 success performs one inventory and MCP call" {
  run_checker codex success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_equal 0 "$LAST_STATUS" "Codex success should exit zero"
  assert_json ".schema_version == 2 and .scope == \"shell\" and .ok == true and .exit_code == 0 and .provider == \"codex\" and (.checks | map(.name)) == $EXPECTED_CHECK_NAMES and all(.checks[]; .status == \"passed\")" \
    "Codex success contract is invalid"
  assert_provider_calls codex 1 1
}

@test "missing Grid plugin fails closed" {
  run_checker claude grid-missing success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 PLUGIN_NOT_INSTALLED
}

@test "disabled Grid plugin fails closed" {
  run_checker claude grid-disabled success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 PLUGIN_DISABLED
}

@test "ambiguous Grid inventory fails closed" {
  run_checker claude grid-ambiguous success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 PLUGIN_INVENTORY_AMBIGUOUS
}

@test "invalid Grid inventory metadata fails closed" {
  run_checker claude grid-invalid success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 PLUGIN_INVENTORY_INVALID
}

@test "missing Grid required skill fails closed" {
  local grid_plugin_without_skill_directory="$TEST_ROOT/grid-plugin-without-skill"
  mkdir -p "$grid_plugin_without_skill_directory"

  run_checker claude success success success "$grid_plugin_without_skill_directory" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 REQUIRED_SKILL_UNAVAILABLE
}

@test "symlinked Grid required skill fails closed" {
  run_checker claude success success success "$GRID_PLUGIN_SYMLINK_SKILL_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 REQUIRED_SKILL_UNAVAILABLE
}

@test "missing Fury plugin blocks dependent checks and external calls" {
  run_checker claude fury-missing success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_failure 10 FURY_PLUGIN_NOT_INSTALLED
  assert_json 'all(.checks[] | select(.name == "fury_required_skill" or .name == "fury_manifest" or .name == "fury_mcp_declaration" or .name == "fury_mcp_cli"); .status == "not_run" and .failure_code == "FURY_PLUGIN_NOT_INSTALLED")' \
    "missing Fury plugin must block all dependent Fury checks"
  assert_provider_calls claude 1 0
  assert_empty_file "$CURL_LOG" "missing Fury plugin must short-circuit before Grid HTTP probes"
}

@test "disabled Fury plugin fails closed" {
  run_checker claude fury-disabled success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_PLUGIN_DISABLED
}

@test "ambiguous Fury inventory fails closed" {
  run_checker claude fury-ambiguous success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_PLUGIN_INVENTORY_AMBIGUOUS
}

@test "invalid Fury metadata fails closed" {
  run_checker claude fury-invalid success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_PLUGIN_INVENTORY_INVALID
}

@test "missing Fury required skill fails closed" {
  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_WITHOUT_SKILL_DIRECTORY"
  assert_failure 10 FURY_REQUIRED_SKILL_UNAVAILABLE
}

@test "symlinked Fury required skill fails closed" {
  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_SYMLINK_SKILL_DIRECTORY"
  assert_failure 10 FURY_REQUIRED_SKILL_UNAVAILABLE
}

@test "unavailable Claude Fury manifest fails closed" {
  mv "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json" "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json.saved"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MANIFEST_UNAVAILABLE
}

@test "invalid Claude Fury manifest fails closed" {
  printf '%s\n' '{"name":"wrong","version":"1.4.0"}' > "$FURY_PLUGIN_DIRECTORY/.claude-plugin/plugin.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MANIFEST_INVALID
}

@test "provider manifest version mismatch fails closed" {
  jq '.version = "9.9.9"' "$FURY_PLUGIN_DIRECTORY/.codex-plugin/plugin.json" > "$TEST_ROOT/codex-version-mismatch.json"
  mv "$TEST_ROOT/codex-version-mismatch.json" "$FURY_PLUGIN_DIRECTORY/.codex-plugin/plugin.json"

  run_checker codex success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MANIFEST_INVALID
}

@test "unavailable Fury MCP declaration fails closed" {
  mv "$FURY_PLUGIN_DIRECTORY/.mcp.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json.saved"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_DECLARATION_UNAVAILABLE
}

# El valor de `--timeout` es tolerado a propósito: fury-services lo movió entre 300 y 5 y de
# vuelta a 300 entre 0.43.0 y 0.45.1. Pinear el número exacto rompía `fury_mcp_declaration`
# en toda invocación distinta de `setup` después de cada release upstream.
@test "Fury MCP declaration tolerates any integer timeout end to end" {
  local timeout_value

  for timeout_value in 5 300 301 86400; do
    FURY_FIXTURE_TIMEOUT="$timeout_value"
    write_fury_fixture "$FURY_PLUGIN_DIRECTORY" true

    FURY_FIXTURE_TIMEOUT="$timeout_value" \
      run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

    assert_equal 0 "$LAST_STATUS" "timeout $timeout_value must be tolerated"
    assert_json '.ok == true and .exit_code == 0 and (.checks[] | select(.name == "fury_mcp_declaration") | .ok) == true and (.checks[] | select(.name == "fury_mcp_cli") | .ok) == true' \
      "timeout $timeout_value must keep both Fury MCP checks green"
  done
}

@test "Fury MCP declaration tolerates an absent timeout flag" {
  jq 'del(.mcpServers.fury.args[-2:])' "$FURY_PLUGIN_DIRECTORY/.mcp.json" > "$TEST_ROOT/no-timeout.json"
  mv "$TEST_ROOT/no-timeout.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_equal 0 "$LAST_STATUS" "an absent --timeout must be tolerated"
  assert_json '(.checks[] | select(.name == "fury_mcp_declaration") | .ok) == true' \
    "an absent --timeout must keep the declaration green"
}

@test "changed Fury MCP gateway URL fails closed" {
  jq '.mcpServers.fury.args[0] = "https://mcp-services-gateway.furycloud.io/v1/servers/fury"' \
    "$FURY_PLUGIN_DIRECTORY/.mcp.json" > "$TEST_ROOT/invalid-gateway.json"
  mv "$TEST_ROOT/invalid-gateway.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_DECLARATION_INVALID
}

@test "changed Fury MCP header value fails closed" {
  jq '.mcpServers.fury.args[3] = "unexpected-origin"' \
    "$FURY_PLUGIN_DIRECTORY/.mcp.json" > "$TEST_ROOT/invalid-header.json"
  mv "$TEST_ROOT/invalid-header.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_DECLARATION_INVALID
}

@test "non numeric Fury MCP timeout value fails closed" {
  jq '.mcpServers.fury.args[-1] = "not-a-number"' \
    "$FURY_PLUGIN_DIRECTORY/.mcp.json" > "$TEST_ROOT/invalid-timeout.json"
  mv "$TEST_ROOT/invalid-timeout.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_DECLARATION_INVALID
}

@test "unexpected extra Fury MCP argument fails closed" {
  jq '.mcpServers.fury.args += ["--unexpected-flag"]' \
    "$FURY_PLUGIN_DIRECTORY/.mcp.json" > "$TEST_ROOT/extra-arg.json"
  mv "$TEST_ROOT/extra-arg.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_DECLARATION_INVALID
}

@test "non string Fury MCP argument fails closed" {
  jq '.mcpServers.fury.args[-1] = 300' \
    "$FURY_PLUGIN_DIRECTORY/.mcp.json" > "$TEST_ROOT/numeric-arg.json"
  mv "$TEST_ROOT/numeric-arg.json" "$FURY_PLUGIN_DIRECTORY/.mcp.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_DECLARATION_INVALID
}

@test "Claude MCP CLI command failure is reported" {
  run_checker claude success command-failure success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_CLI_CHECK_FAILED
}

@test "Claude Fury MCP not configured is reported" {
  run_checker claude success not-configured success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_NOT_CONFIGURED
}

@test "Claude Fury MCP disconnection is reported" {
  run_checker claude success disconnected success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_CONNECTION_UNAVAILABLE
}

@test "Claude invalid MCP response is reported" {
  run_checker claude success invalid-response success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_CLI_RESPONSE_INVALID
}

@test "Codex MCP CLI command failure is reported" {
  run_checker codex success command-failure success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_CLI_CHECK_FAILED
}

@test "Codex Fury MCP not configured is reported" {
  run_checker codex success not-configured success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_NOT_CONFIGURED
}

@test "Codex Fury MCP disconnection is reported" {
  run_checker codex success disconnected success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_CONNECTION_UNAVAILABLE
}

@test "Codex invalid MCP response is reported" {
  run_checker codex success invalid-response success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 10 FURY_MCP_CLI_RESPONSE_INVALID
}

@test "removed provider is rejected before external calls" {
  local removed_provider="co""pilot"
  run_checker "$removed_provider" success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_failure 2 INVALID_PROVIDER
  assert_empty_file "$PROVIDER_LOG" "invalid provider must not invoke a provider CLI"
  assert_empty_file "$CURL_LOG" "invalid provider must short-circuit before Grid HTTP probes"
}

@test "identity 401 maps to exit 22" {
  run_checker claude success success identity-401 "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_failure 22 GRID_IDENTITY_UNAVAILABLE
  assert_json 'any(.checks[]; .name == "identity" and .http_status == 401 and .attempts == 1)' \
    "identity 401 metadata is invalid"
}

@test "document 403 maps to exit 24" {
  run_checker claude success success document-403 "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 24 REQUIRED_DOCUMENT_FORBIDDEN
}

@test "document 404 maps to exit 24" {
  run_checker claude success success document-404 "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 24 REQUIRED_DOCUMENT_NOT_FOUND
}

@test "rate limiting preserves only sanitized Retry-After" {
  run_checker claude success success rate-limit "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_failure 25 GRID_RATE_LIMITED
  assert_json 'any(.checks[]; .name == "skill_version" and .http_status == 429 and .attempts == 1 and .retry_after_seconds == 120)' \
    "Retry-After must be sanitized and must not trigger a retry"
  if grep -Eq '000120|SECRET_HEADER_FIXTURE|PRIVATE_RATE_LIMIT_BODY' "$STDOUT_FILE"; then
    readiness_fail "rate-limit output leaked unsanitized headers or response body"
  fi
}

@test "5xx retries exactly once and recovers" {
  run_checker claude success success service-retry "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_equal 0 "$LAST_STATUS" "one transient 5xx should recover"
  assert_json 'any(.checks[]; .name == "ping" and .attempts == 2 and .http_status == 200)' \
    "ping should report exactly two attempts"
  assert_equal 2 "$(grep -c '/ping$' "$CURL_LOG")" "5xx must be retried exactly once"
}

@test "transport failure retries once and maps to exit 20" {
  run_checker claude success success transport "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_failure 20 GRID_TRANSPORT_FAILED
  assert_json 'any(.checks[]; .name == "ping" and .attempts == 2 and .http_status == null)' \
    "transport failure should report two attempts without HTTP status"
  assert_equal 2 "$(grep -c '/ping$' "$CURL_LOG")" "transport failure must be retried exactly once"
}

@test "invalid version response maps to exit 21" {
  run_checker claude success success invalid-version "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 21 PLUGIN_VERSION_RESPONSE_INVALID
}

@test "incompatible plugin version maps to exit 21" {
  run_checker claude success success incompatible-version "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 21 PLUGIN_VERSION_INCOMPATIBLE
}

@test "invalid identity response maps to exit 22" {
  run_checker claude success success invalid-identity "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 22 GRID_IDENTITY_RESPONSE_INVALID
}

@test "invalid document list maps to exit 23" {
  run_checker claude success success invalid-list "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 23 GENERAL_READ_RESPONSE_INVALID
}

@test "invalid required document maps to exit 24" {
  run_checker claude success success invalid-document "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"
  assert_failure 24 REQUIRED_DOCUMENT_RESPONSE_INVALID
}

@test "valid schema 2 result is reused without external calls" {
  create_reuse_result

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$REUSE_FILE"

  assert_equal 0 "$LAST_STATUS" "valid schema 2 reuse should succeed"
  assert_json ".schema_version == 2 and .scope == \"shell\" and .source == \"reused\" and .provider == \"claude\" and (.checks | map(.name)) == $EXPECTED_CHECK_NAMES" \
    "valid schema 2 reuse should preserve the complete contract"
  assert_empty_file "$PROVIDER_LOG" "valid reuse must not call provider inventory or MCP CLI"
  assert_empty_file "$CURL_LOG" "valid reuse must not call Grid"
}

@test "schema 1 reuse is rejected and refreshed" {
  create_reuse_result
  jq '.schema_version = 1' "$REUSE_FILE" > "$TEST_ROOT/schema-1-result.json"
  chmod 600 "$TEST_ROOT/schema-1-result.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEST_ROOT/schema-1-result.json"

  assert_equal 0 "$LAST_STATUS" "schema 1 reuse should fall back to a fresh successful check"
  assert_json '.schema_version == 2 and .source == "fresh" and .ok == true' "schema 1 reuse must not be trusted"
  assert_nonempty_file "$PROVIDER_LOG" "schema 1 reuse must re-run inventory and MCP checks"
  assert_nonempty_file "$CURL_LOG" "schema 1 reuse must re-run Grid checks"
}

@test "stale result triggers a fresh preflight" {
  create_reuse_result
  jq '.checked_at_epoch = 0' "$REUSE_FILE" > "$TEST_ROOT/stale-result.json"
  chmod 600 "$TEST_ROOT/stale-result.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEST_ROOT/stale-result.json"

  assert_equal 0 "$LAST_STATUS" "stale reuse should run a fresh successful check"
  assert_json '.source == "fresh" and .ok == true' "stale reuse must not be trusted"
  assert_nonempty_file "$PROVIDER_LOG" "stale reuse must re-run provider checks"
  assert_nonempty_file "$CURL_LOG" "stale reuse must re-run Grid checks"
}

@test "tampered result triggers a fresh preflight" {
  create_reuse_result
  jq '.checks[0].ok = false' "$REUSE_FILE" > "$TEST_ROOT/tampered-result.json"
  chmod 600 "$TEST_ROOT/tampered-result.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEST_ROOT/tampered-result.json"

  assert_equal 0 "$LAST_STATUS" "tampered reuse should run a fresh successful check"
  assert_json '.source == "fresh" and .ok == true' "tampered reuse must not be trusted"
  assert_nonempty_file "$PROVIDER_LOG" "tampered reuse must re-run provider checks"
}

@test "unsafe reuse mode maps to exit 70 before external calls" {
  create_reuse_result
  cp "$REUSE_FILE" "$TEST_ROOT/unsafe-mode.json"
  chmod 644 "$TEST_ROOT/unsafe-mode.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEST_ROOT/unsafe-mode.json"

  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  assert_empty_file "$PROVIDER_LOG" "unsafe mode must fail before provider calls"
  assert_empty_file "$CURL_LOG" "unsafe mode must fail before Grid calls"
}

@test "group-writable reuse mode fails before external calls" {
  create_reuse_result
  cp "$REUSE_FILE" "$TEST_ROOT/unsafe-group-write.json"
  chmod 0620 "$TEST_ROOT/unsafe-group-write.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEST_ROOT/unsafe-group-write.json"

  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  assert_empty_file "$PROVIDER_LOG" "mode 0620 must fail before provider calls"
  assert_empty_file "$CURL_LOG" "mode 0620 must fail before Grid calls"
}

@test "unsafe reuse parent mode maps to exit 70" {
  create_reuse_result
  local unsafe_parent_directory="$TEST_ROOT/unsafe-parent"
  mkdir "$unsafe_parent_directory"
  chmod 0770 "$unsafe_parent_directory"
  cp "$REUSE_FILE" "$unsafe_parent_directory/reusable-result.json"
  chmod 0600 "$unsafe_parent_directory/reusable-result.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$unsafe_parent_directory/reusable-result.json"

  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  assert_empty_file "$PROVIDER_LOG" "unsafe parent mode must fail before provider calls"
  assert_empty_file "$CURL_LOG" "unsafe parent mode must fail before Grid calls"
}

@test "symlinked reuse parent maps to exit 70" {
  create_reuse_result
  local private_parent_directory="$TEST_ROOT/private-parent"
  local symlinked_parent_directory="$TEST_ROOT/symlinked-parent"
  mkdir "$private_parent_directory"
  chmod 0700 "$private_parent_directory"
  cp "$REUSE_FILE" "$private_parent_directory/reusable-result.json"
  chmod 0600 "$private_parent_directory/reusable-result.json"
  ln -s "$private_parent_directory" "$symlinked_parent_directory"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$symlinked_parent_directory/reusable-result.json"

  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  assert_empty_file "$PROVIDER_LOG" "symlinked parent must fail before provider calls"
  assert_empty_file "$CURL_LOG" "symlinked parent must fail before Grid calls"
}

@test "symlinked reuse path maps to exit 70" {
  create_reuse_result
  ln -s "$REUSE_FILE" "$TEST_ROOT/unsafe-link.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEST_ROOT/unsafe-link.json"

  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  assert_empty_file "$PROVIDER_LOG" "symlink reuse path must fail before provider calls"
}

@test "unsafe reuse owner maps to exit 70" {
  if [ "$(id -u)" -ne 0 ]; then
    skip "requires portable owner change"
  fi
  create_reuse_result
  cp "$REUSE_FILE" "$TEST_ROOT/unsafe-owner.json"
  chown 65534 "$TEST_ROOT/unsafe-owner.json"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$TEST_ROOT/unsafe-owner.json"
  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
}

@test "unsafe reuse parent owner maps to exit 70 before external calls" {
  if [ "$(id -u)" -ne 0 ]; then
    skip "requires portable owner change"
  fi
  create_reuse_result
  local unsafe_owner_parent_directory="$TEST_ROOT/unsafe-owner-parent"
  mkdir "$unsafe_owner_parent_directory"
  cp "$REUSE_FILE" "$unsafe_owner_parent_directory/reusable-result.json"
  chmod 0700 "$unsafe_owner_parent_directory"
  chmod 0600 "$unsafe_owner_parent_directory/reusable-result.json"
  chown 65534 "$unsafe_owner_parent_directory"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$unsafe_owner_parent_directory/reusable-result.json"

  assert_failure 70 REUSE_RESULT_FILE_UNSAFE
  assert_empty_file "$PROVIDER_LOG" "unsafe parent owner must fail before provider calls"
  assert_empty_file "$CURL_LOG" "unsafe parent owner must fail before Grid calls"
}

@test "path replacement after descriptor open cannot alter reused snapshot" {
  create_reuse_result
  local race_reuse_file="$TEST_ROOT/race-reuse-result.json"
  local race_malicious_file="$TEST_ROOT/race-malicious-result.json"
  local race_marker_file="$TEST_ROOT/race-triggered"
  cp "$REUSE_FILE" "$race_reuse_file"
  jq '.provider = "codex"' "$REUSE_FILE" > "$race_malicious_file"
  chmod 600 "$race_reuse_file" "$race_malicious_file"
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
  export REAL_PERL RACE_REUSE_FILE="$race_reuse_file" RACE_MALICIOUS_FILE="$race_malicious_file" RACE_MARKER_FILE="$race_marker_file"

  run_checker claude success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY" --reuse-result "$race_reuse_file"

  assert_equal 0 "$LAST_STATUS" "path replacement after FD open must not change reused result"
  assert_json '.provider == "claude" and .source == "reused" and .ok == true' \
    "checker must consume the original descriptor snapshot"
  [ -L "$race_reuse_file" ] || readiness_fail "race fixture did not replace original path"
  assert_empty_file "$PROVIDER_LOG" "descriptor snapshot reuse must not call provider inventory"
  assert_empty_file "$CURL_LOG" "descriptor snapshot reuse must not call Grid"
}

@test "auto skips incomplete Codex and probes selected Claude only" {
  CODEX_INVENTORY_SCENARIO_OVERRIDE=fury-missing
  CLAUDE_INVENTORY_SCENARIO_OVERRIDE=success

  run_checker auto success success success "$GRID_PLUGIN_DIRECTORY" "$FURY_PLUGIN_DIRECTORY"

  assert_equal 0 "$LAST_STATUS" "auto should select the first complete provider"
  assert_json '.provider == "claude" and .ok == true and .schema_version == 2' \
    "auto should reject Grid-only Codex and select complete Claude"
  assert_provider_calls codex 1 0
  assert_provider_calls claude 1 1
  assert_equal 1 "$(grep -c '/ping$' "$CURL_LOG")" "auto must run Grid HTTP probes only for selected Claude"
}

@test "provider inventory failure propagates and skips external calls" {
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
}
