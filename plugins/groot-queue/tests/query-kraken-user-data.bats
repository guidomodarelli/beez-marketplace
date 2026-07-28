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

@test "silos publishes a complete single-page response" {
  run run_kraken_user_data context --user-id 123 --facts silos

  [ "$status" -eq 0 ]
  assert_kraken_json '
    .status == "complete" and
    .facts.silos.items == [{"key":"SILO_KEY","active":true}] and
    .facts.silos.count == 1 and
    .warnings == []
  ' "complete silos response should publish the normalized fact"
  assert_kraken_count 1 '/core/v1/users/123/silos?page=0&size=1000' "silos should request the configured page once"
}

@test "paginated silos collects every page before publishing the fact" {
  KRAKEN_TEST_SCENARIO=paginated-silos
  run run_kraken_user_data context --user-id 123 --facts silos

  [ "$status" -eq 0 ]
  assert_kraken_json '
    .status == "complete" and
    .facts.silos.count == 1001 and
    any(.facts.silos.items[]; .key == "SILO_1" and .active == true) and
    any(.facts.silos.items[]; .key == "SILO_1001" and .active == false) and
    (.source_results | length) == 2 and
    all(.source_results[];
      .source == "silos" and
      .status == "ok" and
      (keys | sort) == ["attempts","authority","source","status"]
    ) and
    .warnings == []
  ' "paginated silos should publish the complete sanitized collection"
  assert_kraken_count 1 '/silos?page=0&size=1000' "first silos page should execute once"
  assert_kraken_count 1 '/silos?page=1&size=1000' "second silos page should execute once"
  assert_kraken_count 0 '/silos?page=2' "silos should stop after the advertised pages"
}

@test "paginated silos retries only the failing page" {
  KRAKEN_TEST_SCENARIO=retry-paginated-silos
  run run_kraken_user_data context --user-id 123 --facts silos

  [ "$status" -eq 0 ]
  assert_kraken_json '
    .status == "complete" and
    .facts.silos.count == 1001 and
    (.source_results | length) == 2 and
    .source_results[0].attempts == 1 and
    .source_results[1].attempts == 2
  ' "later silos page should recover without repeating earlier pages"
  assert_kraken_count 1 '/silos?page=0&size=1000' "successful first page should not repeat"
  assert_kraken_count 2 '/silos?page=1&size=1000' "transient second page should retry once"
}

@test "paginated silos failure discards earlier pages" {
  KRAKEN_TEST_SCENARIO=failed-paginated-silos
  run run_kraken_user_data context --user-id 123 --facts silos

  [ "$status" -eq 0 ]
  assert_kraken_json '
    .status == "indeterminate" and
    .warnings == ["SILOS_INDETERMINATE","UPSTREAM_ERROR"] and
    (.facts | has("silos") | not) and
    (.source_results | length) == 2 and
    .source_results[0].status == "ok" and
    .source_results[1].status == "upstream_error" and
    .source_results[1].attempts == 2
  ' "failed later page must invalidate the complete silos fact"
  ! grep -q 'private silos page error' "$STDOUT_FILE"
  ! grep -q 'private silos page error' "$STDERR_FILE"
  assert_kraken_count 1 '/silos?page=0&size=1000' "first page should execute once"
  assert_kraken_count 2 '/silos?page=1&size=1000' "failed page should retry once"
  assert_kraken_count 0 '/silos?page=2' "pages after failure should not execute"
}

@test "paginated silos failure makes mixed context partial" {
  KRAKEN_TEST_SCENARIO=failed-paginated-silos
  run run_kraken_user_data context --user-id 123 --facts roles,silos

  [ "$status" -eq 0 ]
  assert_kraken_json '
    .status == "partial" and
    .facts.roles.count == 2 and
    (.facts | has("silos") | not) and
    (.warnings | index("SILOS_INDETERMINATE")) != null
  ' "failed silos pagination should preserve successful facts"
}

@test "mutated silos metadata is treated as truncated" {
  KRAKEN_TEST_SCENARIO=mutated-paginated-silos
  run run_kraken_user_data context --user-id 123 --facts silos

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and .warnings == ["SILOS_TRUNCATED"] and (.facts | has("silos") | not)' "mutated paging metadata should fail closed"
}

@test "invalid later silos schema remains distinct from truncation" {
  KRAKEN_TEST_SCENARIO=invalid-later-silos
  run run_kraken_user_data context --user-id 123 --facts silos

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and .warnings == ["INVALID_SILOS_RESPONSE"] and (.facts | has("silos") | not)' "invalid later schema should keep its warning"
}

@test "duplicate silos IDs across pages fail closed" {
  KRAKEN_TEST_SCENARIO=duplicate-paginated-silos
  run run_kraken_user_data context --user-id 123 --facts silos

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and .warnings == ["SILOS_TRUNCATED"] and (.facts | has("silos") | not)' "duplicate IDs should invalidate paginated silos"
}

@test "silos page limit fails before requesting another page" {
  KRAKEN_TEST_SCENARIO=excessive-silos-pages
  run run_kraken_user_data context --user-id 123 --facts silos

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and .warnings == ["SILOS_TRUNCATED"] and (.facts | has("silos") | not)' "excessive pagination should fail closed"
  assert_kraken_count 1 '/silos?page=0&size=1000' "only metadata page should execute"
  assert_kraken_count 0 '/silos?page=1' "page limit should stop traversal"
}

@test "paginated account status finds the requested user on a later page" {
  KRAKEN_TEST_SCENARIO=paginated-account-status
  run run_kraken_user_data context --user-id 123 --facts account-status

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "complete" and .facts["account-status"].state == "active" and (.source_results | length) == 2' "account status should validate all pages"
  assert_kraken_count 1 '/status?ids=123&page=0&size=100' "first status page should execute once"
  assert_kraken_count 1 '/status?ids=123&page=1&size=100' "second status page should execute once"
}

@test "paginated temporary status finds the attribute on a later page" {
  KRAKEN_TEST_SCENARIO=paginated-temporary-status
  run run_kraken_user_data context --user-id 123 --facts temporary-status

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "complete" and .facts["temporary-status"].active == true and .facts["temporary-status"].values == ["labour-share"] and (.source_results | length) == 2' "temporary status should not infer absence from the first page"
  assert_kraken_count 1 '/attribute-values-admin?key=tmp_user_status&page=0&size=200' "first attribute page should execute once"
  assert_kraken_count 1 '/attribute-values-admin?key=tmp_user_status&page=1&size=200' "second attribute page should execute once"
}

@test "empty complete temporary status is inactive" {
  KRAKEN_TEST_SCENARIO=empty-temporary-status
  run run_kraken_user_data context --user-id 123 --facts temporary-status

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "complete" and .facts["temporary-status"] == {"active":false,"values":[],"source":"sot"}' "only complete global absence should produce inactive"
  assert_kraken_count 1 '/attribute-values-admin?key=tmp_user_status&page=0&size=200' "empty collection should use one page"
}

@test "temporary status page failure never implies inactivity" {
  KRAKEN_TEST_SCENARIO=failed-paginated-temporary-status
  run run_kraken_user_data context --user-id 123 --facts temporary-status

  [ "$status" -eq 0 ]
  assert_kraken_json '.status == "indeterminate" and (.facts | has("temporary-status") | not) and (.warnings | index("TEMPORARY_STATUS_INDETERMINATE")) != null' "partial temporary status must not become inactive"
  ! grep -q 'private temporary status page error' "$STDOUT_FILE"
  ! grep -q 'private temporary status page error' "$STDERR_FILE"
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
