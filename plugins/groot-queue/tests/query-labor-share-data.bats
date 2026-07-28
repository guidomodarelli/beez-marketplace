#!/usr/bin/env bats

load 'test_helper/labor-share-data.bash'

setup() {
  setup_labor_share_data_fixture
}

teardown() {
  teardown_labor_share_data_fixture
}

@test "execution reports uniform success without exposing assignment details" {
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '
    .schema_version == 1 and
    .operation == "execution" and
    .status == "complete" and
    .resource_fingerprint == "redacted" and
    .facts.processing == false and
    .facts.assignments.counts == {"total":2,"success":2,"fail":0} and
    .facts.assignments.result_consistency == "uniform_success" and
    .facts.assignments.scheduled_return == {"consistency":"uniform","at":"2026-08-01T12:00:00Z"} and
    .source_results == [{"source":"shipping_users_mgmt_api","status":"ok","attempts":1}] and
    .warnings == []
  ' "successful execution should publish only normalized aggregate facts"
  assert_labor_share_count 1 '/management/v1/labor-share/424242$' "execution should query the labor share once"
  assert_labor_share_private_values_hidden
}

@test "execution reports mixed assignment results" {
  LABOR_SHARE_TEST_SCENARIO=execution-mixed
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '
    .status == "complete" and
    .facts.assignments.counts == {"total":2,"success":1,"fail":1} and
    .facts.assignments.result_consistency == "mixed" and
    .facts.assignments.scheduled_return.consistency == "uniform" and
    .warnings == ["MIXED_ASSIGNMENT_RESULTS"]
  ' "mixed assignment statuses should be explicit"
  assert_labor_share_private_values_hidden
}

@test "execution reports mixed scheduled return dates" {
  LABOR_SHARE_TEST_SCENARIO=execution-mixed-dates
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '
    .status == "complete" and
    .facts.assignments.result_consistency == "uniform_success" and
    .facts.assignments.scheduled_return == {"consistency":"mixed","distinct_values":2} and
    .warnings == ["INCONSISTENT_SCHEDULED_RETURN"]
  ' "different return dates should not be collapsed into one date"
  assert_labor_share_private_values_hidden
}

@test "202 reports processing and hides the upstream body" {
  LABOR_SHARE_TEST_SCENARIO=processing
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '
    .status == "processing" and
    .facts == {"processing":true} and
    .source_results == [{"source":"shipping_users_mgmt_api","status":"processing","attempts":1}] and
    .warnings == ["LABOR_SHARE_PROCESSING"]
  ' "202 should preserve processing state"
  assert_labor_share_count 1 '/management/v1/labor-share/424242$' "202 should not retry"
  assert_labor_share_private_values_hidden
}

@test "403 is indeterminate without retrying or exposing its body" {
  LABOR_SHARE_TEST_SCENARIO=forbidden
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '.status == "indeterminate" and .facts == {} and .source_results[0].attempts == 1 and .warnings == ["UPSTREAM_FORBIDDEN"]' "403 should fail closed"
  assert_labor_share_count 1 '/management/v1/labor-share/424242$' "403 must not retry"
  assert_labor_share_private_values_hidden
}

@test "404 reports labor share not found without retrying" {
  LABOR_SHARE_TEST_SCENARIO=not-found
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '.status == "indeterminate" and .facts == {} and .source_results[0].attempts == 1 and .warnings == ["LABOR_SHARE_NOT_FOUND"]' "404 should use the domain warning"
  assert_labor_share_count 1 '/management/v1/labor-share/424242$' "404 must not retry"
  assert_labor_share_private_values_hidden
}

@test "429 reports rate limiting without retrying" {
  LABOR_SHARE_TEST_SCENARIO=rate-limited
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '.status == "indeterminate" and .facts == {} and .source_results[0].attempts == 1 and .warnings == ["UPSTREAM_RATE_LIMITED"]' "429 should remain indeterminate"
  assert_labor_share_count 1 '/management/v1/labor-share/424242$' "429 must not retry"
  assert_labor_share_private_values_hidden
}

@test "transport failure retries once and remains indeterminate" {
  LABOR_SHARE_TEST_SCENARIO=transport
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '.status == "indeterminate" and .facts == {} and .source_results[0].attempts == 2 and .warnings == ["UPSTREAM_TRANSPORT_ERROR"]' "transport failure should fail closed after retry"
  assert_labor_share_count 2 '/management/v1/labor-share/424242$' "transport failure should retry exactly once"
  assert_labor_share_private_values_hidden
}

@test "503 retries once and then publishes a successful execution" {
  LABOR_SHARE_TEST_SCENARIO=retry-503
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '.status == "complete" and .facts.assignments.counts.success == 2 and .source_results[0].attempts == 2 and .warnings == []' "transient 503 should recover"
  assert_labor_share_count 2 '/management/v1/labor-share/424242$' "503 should retry exactly once"
  assert_labor_share_private_values_hidden
}

@test "invalid execution schema remains indeterminate" {
  LABOR_SHARE_TEST_SCENARIO=invalid-execution-schema
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '.status == "indeterminate" and .facts == {} and .warnings == ["INVALID_LABOR_SHARE_RESPONSE"]' "invalid assignment fields must invalidate the response"
  assert_labor_share_private_values_hidden
}

@test "empty execution response remains indeterminate" {
  LABOR_SHARE_TEST_SCENARIO=empty-execution
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  assert_labor_share_json '.status == "indeterminate" and .facts == {} and .warnings == ["INVALID_LABOR_SHARE_RESPONSE"]' "empty execution must not imply success"
}

@test "invalid labor share ID fails before curl" {
  run run_labor_share_data execution --labor-share-id '42x'

  [ "$status" -eq 0 ]
  assert_labor_share_json '.operation == "execution" and .status == "indeterminate" and .facts == {} and .source_results[0].attempts == 0 and .warnings == ["INVALID_LABOR_SHARE_ID"]' "invalid identifier should fail closed locally"
  [ ! -s "$CURL_LOG" ]
  [ ! -s "$STDERR_FILE" ]
}

@test "ambiguous labor share IDs fail before curl" {
  run run_labor_share_data execution --labor-share-id 424242 --labor-share-id 434343

  [ "$status" -eq 0 ]
  assert_labor_share_json '.operation == "execution" and .status == "indeterminate" and .facts == {} and .source_results[0].attempts == 0 and .warnings == ["AMBIGUOUS_LABOR_SHARE_ID"]' "different identifiers should be rejected as ambiguous"
  [ ! -s "$CURL_LOG" ]
  [ ! -s "$STDERR_FILE" ]
}

@test "processes returns a normalized catalog without process IDs" {
  LABOR_SHARE_TEST_SCENARIO=processes-success
  run run_labor_share_data processes --facility-type WAREHOUSE

  [ "$status" -eq 0 ]
  assert_labor_share_json '
    .operation == "processes" and
    .status == "complete" and
    .facts.catalog.process_count == 2 and
    .facts.catalog.processes == [
      {"description":"Inbound","sub_process_count":2,"sub_processes":["Receiving","Putaway"]},
      {"description":"Outbound","sub_process_count":0,"sub_processes":[]}
    ] and
    .source_results == [{"source":"shipping_users_mgmt_api","status":"ok","attempts":1}] and
    .warnings == []
  ' "process catalog should expose descriptions but not internal IDs"
  ! grep -Eq '9101|9102|9201|9202' "$STDOUT_FILE"
  [ ! -s "$STDERR_FILE" ]
}

@test "processes 404 reports upstream resource not found without retrying" {
  LABOR_SHARE_TEST_SCENARIO=processes-not-found
  run run_labor_share_data processes --facility-type WAREHOUSE

  [ "$status" -eq 0 ]
  assert_labor_share_json '.operation == "processes" and .status == "indeterminate" and .facts == {} and .source_results[0].attempts == 1 and .warnings == ["UPSTREAM_NOT_FOUND"]' "processes 404 should not claim a labor share execution is missing"
  assert_labor_share_count 1 '/management/v1/labor-share/process/WAREHOUSE$' "processes 404 must not retry"
  assert_labor_share_private_values_hidden
}

@test "invalid facility type fails before curl" {
  run run_labor_share_data processes --facility-type OFFICE

  [ "$status" -eq 0 ]
  assert_labor_share_json '.operation == "processes" and .status == "indeterminate" and .facts == {} and .source_results[0].attempts == 0 and .warnings == ["INVALID_FACILITY_TYPE"]' "unsupported facility should fail closed locally"
  [ ! -s "$CURL_LOG" ]
  [ ! -s "$STDERR_FILE" ]
}

@test "invalid processes schema remains indeterminate" {
  LABOR_SHARE_TEST_SCENARIO=invalid-processes-schema
  run run_labor_share_data processes --facility-type SC

  [ "$status" -eq 0 ]
  assert_labor_share_json '.operation == "processes" and .status == "indeterminate" and .facts == {} and .warnings == ["INVALID_LABOR_SHARE_RESPONSE"]' "invalid subprocess fields must invalidate the catalog"
  ! grep -Eq '9101|9201' "$STDOUT_FILE"
  [ ! -s "$STDERR_FILE" ]
}

@test "curl enforces HTTPS and disables redirects" {
  run run_labor_share_data execution --labor-share-id 424242

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CURL_FLAGS_LOG" | tr -d ' ')" -eq 1 ]
  grep -q 'method=GET proto==https max_redirs=0' "$CURL_FLAGS_LOG"
  grep -q 'fail_with_body=true url=https://' "$CURL_FLAGS_LOG"
  ! grep -q 'url=http://' "$CURL_FLAGS_LOG"
  [ ! -s "$STDERR_FILE" ]
}
