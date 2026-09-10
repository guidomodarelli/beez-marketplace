#!/usr/bin/env bats

bats_require_minimum_version 1.13.0

load 'test_helper/eval-runner'

setup() {
    unset GROOT_MARKETPLACE_EVAL_MODEL
    unset CLAUDE_RESPONSE_FILE
    setup_eval_runner_fixture
}

write_mixed_action_config() {
    local config_file="${SKILL_DIR}/evals/eval-config.json"

    cat > "$config_file" <<JSON
{
  "skill": "${SKILL_NAME}",
  "test_cases": [
    {
      "id": "mixed-actions",
      "input": "Describe next steps",
      "assertions": [
        {
          "type": "not_contains_any",
          "values": [
            "[0-9][0-9]*\\..*\\[AUTO\\].*\\[MANUAL\\]",
            "[0-9][0-9]*\\..*\\[MANUAL\\].*\\[AUTO\\]",
            "- .*\\[AUTO\\].*\\[MANUAL\\]",
            "- .*\\[MANUAL\\].*\\[AUTO\\]",
            "[0-9][0-9]*\\..*automátic.*manual",
            "[0-9][0-9]*\\..*manual.*automátic",
            "- .*automátic.*manual",
            "- .*manual.*automátic",
            "\\[AUTO\\].*permis",
            "\\[AUTO\\].*permission"
          ],
          "description": "Keeps action types separate within one step"
        }
      ]
    }
  ]
}
JSON
}

run_mixed_action_assertion() {
    local response="$1"
    local response_file="${TEST_ROOT}/response.txt"

    write_mixed_action_config
    printf '%s\n' "$response" > "$response_file"
    CLAUDE_RESPONSE_FILE="$response_file"
    run_eval_runner
}

@test "rejects manual continuation after automatic step" {
    run_mixed_action_assertion $'1. [AUTO] Validate generated files.\n   [MANUAL] Decide project permissions.'

    [ "$status" -eq 1 ]
    run jq -e 'select(.event == "summary" and .passed == 0 and .failed == 1)' <<< "$output"
    [ "$status" -eq 0 ]
}

@test "rejects automatic continuation after manual step" {
    run_mixed_action_assertion $'1. [MANUAL] Decide project permissions.\n   [AUTO] Validate generated files.'

    [ "$status" -eq 1 ]
    run jq -e 'select(.event == "summary" and .passed == 0 and .failed == 1)' <<< "$output"
    [ "$status" -eq 0 ]
}

@test "rejects manual continuation after blank line" {
    run_mixed_action_assertion $'1. [AUTO] Validate generated files.\n\n   [MANUAL] Decide project permissions.'

    [ "$status" -eq 1 ]
    run jq -e 'select(.event == "summary" and .passed == 0 and .failed == 1)' <<< "$output"
    [ "$status" -eq 0 ]
}

@test "rejects automatic continuation after blank line" {
    run_mixed_action_assertion $'1. [MANUAL] Decide project permissions.\n\n   [AUTO] Validate generated files.'

    [ "$status" -eq 1 ]
    run jq -e 'select(.event == "summary" and .passed == 0 and .failed == 1)' <<< "$output"
    [ "$status" -eq 0 ]
}

@test "accepts separate numbered steps" {
    run_mixed_action_assertion $'1. [AUTO] Validate generated files.\n2. [MANUAL] Decide project permissions.'

    [ "$status" -eq 0 ]
    run jq -e 'select(.event == "summary" and .passed == 1 and .failed == 0)' <<< "$output"
    [ "$status" -eq 0 ]
}

@test "rejects both action types on one step line" {
    run_mixed_action_assertion '1. [AUTO] Validate files and [MANUAL] decide permissions.'

    [ "$status" -eq 1 ]
    run jq -e 'select(.event == "summary" and .passed == 0 and .failed == 1)' <<< "$output"
    [ "$status" -eq 0 ]
}

@test "preserves textual automatic and manual action detection" {
    run_mixed_action_assertion $'1. Validación automática de archivos.\n   Completar manualmente permisos del proyecto.'

    [ "$status" -eq 1 ]
    run jq -e 'select(.event == "summary" and .passed == 0 and .failed == 1)' <<< "$output"
    [ "$status" -eq 0 ]
}
