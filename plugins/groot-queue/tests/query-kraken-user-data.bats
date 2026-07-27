#!/usr/bin/env bats

load 'test_helper/kraken-user-data.bash'

setup() {
  setup_kraken_user_data_fixture
}

teardown() {
  teardown_kraken_user_data_fixture
}

@test "resolve-user validates exact LDAP and returns no identifier" {
  run run_kraken_user_data resolve-user --ldap test_user

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "complete" and .facts.identity.resolved == true and .subject_fingerprint == "redacted"' "resolve-user should return sanitized success"
  ! grep -Eq 'test_user|"id"[[:space:]]*:[[:space:]]*123' "$STDOUT_FILE"
  [ ! -s "$STDERR_FILE" ]
  assert_kraken_count 1 '/aggregator/integration/v1/users?' "lookup should execute once"
}

@test "context returns strict normalized facts after one lookup" {
  run run_kraken_user_data context --ldap test_user --facts account-status,roles,permissions,temporary-status,context-accesses,silos

  [ "$status" -eq 0 ]
  assert_kraken_json '
    .status == "complete" and
    .facts["account-status"].state == "active" and
    .facts.roles.keys == ["ROLE_A","ROLE_B"] and
    .facts.permissions.count == 1 and
    .facts["temporary-status"].active == true and
    .facts["context-accesses"].items == [{"key":"context-key","active":true}] and
    .facts.silos.items == [{"key":"SILO_KEY","active":true}]
  ' "context should project all supported facts"
  assert_kraken_count 7 '^GET ' "lookup plus six facts should execute exactly once each"
}

@test "user ID bypasses LDAP lookup" {
  run run_kraken_user_data context --user-id 123 --facts roles

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "complete" and .facts.roles.count == 2' "user ID context should succeed"
  assert_kraken_count 0 '/aggregator/integration/v1/users?' "user ID should not call lookup"
  assert_kraken_count 1 '/user/123/roles' "roles should execute once"
}

@test "invalid subject fails before curl" {
  run run_kraken_user_data context --ldap 'bad user;token' --facts roles

  [ "$status" -eq 64 ]
  [ ! -s "$CURL_LOG" ]
  grep -q 'Invalid LDAP' "$STDERR_FILE"
}

@test "unsafe JSON integer user ID fails before curl" {
  run run_kraken_user_data context --user-id 9007199254740992 --facts account-status

  [ "$status" -eq 64 ]
  [ ! -s "$CURL_LOG" ]
  grep -q 'Invalid user ID' "$STDERR_FILE"
}

@test "unsupported fact is indeterminate without guessing a schema" {
  run run_kraken_user_data context --user-id 123 --facts ssff-status

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and (.warnings | index("UNSUPPORTED_FACT_CONTRACT")) != null' "unsupported contract should stay indeterminate"
  [ ! -s "$CURL_LOG" ]
}

@test "forbidden response is indeterminate and hides body" {
  KRAKEN_TEST_SCENARIO=forbidden
  run run_kraken_user_data context --user-id 123 --facts roles

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and (.warnings | index("UPSTREAM_FORBIDDEN")) != null' "403 should be indeterminate"
  ! grep -q 'private forbidden body' "$STDOUT_FILE"
  ! grep -q 'private forbidden body' "$STDERR_FILE"
  assert_kraken_count 1 '/user/123/roles' "403 must not retry"
}

@test "GET retries one transient status and then succeeds" {
  KRAKEN_TEST_SCENARIO=retry-status
  run run_kraken_user_data context --user-id 123 --facts account-status

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "complete" and .facts["account-status"].state == "active" and .source_results[0].attempts == 2' "GET should recover after one retry"
  assert_kraken_count 2 '/integration/v1/users/status?' "GET should execute exactly twice"
}

@test "transport failure retries GET once and remains indeterminate" {
  KRAKEN_TEST_SCENARIO=transport
  run run_kraken_user_data context --user-id 123 --facts account-status

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and (.warnings | index("UPSTREAM_TRANSPORT_ERROR")) != null and (.facts | has("account-status") | not)' "transport failure must not imply account state"
  assert_kraken_count 2 '/integration/v1/users/status?' "transport failure should retry GET exactly once"
}

@test "duplicate facts execute one request" {
  run run_kraken_user_data context --user-id 123 --facts roles,roles

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "complete" and .facts.roles.count == 2' "duplicate facts should still succeed"
  assert_kraken_count 1 '/user/123/roles' "duplicate fact should execute once"
}

@test "schema mismatch is indeterminate rather than inactive" {
  KRAKEN_TEST_SCENARIO=invalid-status
  run run_kraken_user_data context --user-id 123 --facts account-status

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and (.warnings | index("INVALID_ACCOUNT_STATUS_RESPONSE")) != null and (.facts | has("account-status") | not)' "invalid status response must not imply inactivity"
}

@test "role incompatibilities validate candidates and expose conflict state" {
  run run_kraken_user_data role-incompatibilities --user-id 123 --candidate-role-keys ROLE_NEW

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "incompatible" and .facts.role_incompatibilities.evaluated_roles == ["ROLE_NEW"] and .facts.role_incompatibilities.conflicts == [{"role":"ROLE_NEW","incompatible_with":["ROLE_A"]}]' "role conflict should be normalized"
  assert_kraken_count 1 '^POST .*/users/assign_roles/check$' "assignment check should execute once"
}

@test "POST incompatibility check never retries" {
  KRAKEN_TEST_SCENARIO=post-error
  run run_kraken_user_data role-incompatibilities --user-id 123 --candidate-role-keys ROLE_NEW

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and (.warnings | index("ROLE_INCOMPATIBILITIES_INDETERMINATE")) != null' "POST error should be indeterminate"
  assert_kraken_count 1 '^POST .*/users/assign_roles/check$' "POST must not retry"
  ! grep -q 'private post body' "$STDOUT_FILE"
}

@test "unexpected role response is indeterminate" {
  KRAKEN_TEST_SCENARIO=invalid-incompatibilities
  run run_kraken_user_data role-incompatibilities --user-id 123 --candidate-role-keys ROLE_NEW

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and (.warnings | index("INVALID_ROLE_INCOMPATIBILITIES_RESPONSE")) != null' "unexpected role should invalidate response"
}

@test "duplicate role keys are normalized before POST" {
  run run_kraken_user_data role-incompatibilities --user-id 123 --candidate-role-keys ROLE_NEW,ROLE_NEW

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "incompatible" and .facts.role_incompatibilities.evaluated_roles == ["ROLE_NEW"]' "duplicate candidates should be deduplicated"
  assert_kraken_count 1 '^POST .*/users/assign_roles/check$' "deduplicated check should execute once"
}
