#!/usr/bin/env bats

bats_require_minimum_version 1.13.0

load 'test_helper/eval-runner'

setup() {
    unset GROOT_MARKETPLACE_EVAL_MODEL
    setup_eval_runner_fixture
}

@test "uses the default model" {
    run_eval_runner

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CLAUDE_ARGS_LOG" | tr -d ' ')" -ge 1 ]
    grep -q -- '--model claude-sonnet-4-6' "$CLAUDE_ARGS_LOG"
}

@test "uses the model override" {
    GROOT_MARKETPLACE_EVAL_MODEL='prefixed-model'

    run_eval_runner

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CLAUDE_ARGS_LOG" | tr -d ' ')" -ge 1 ]
    grep -q -- '--model prefixed-model' "$CLAUDE_ARGS_LOG"
}

@test "removed provider is rejected before invoking Claude" {
    local removed_provider="co""pilot"

    run --separate-stderr env \
        "PATH=${STUB_BIN}:${PATH}" \
        "CLAUDE_ARGS_LOG=${CLAUDE_ARGS_LOG}" \
        "GROOT_MARKETPLACE_EVAL_PROVIDER=${removed_provider}" \
        "${EVAL_RUNNER}" --jobs 1 "${SKILL_DIR}"

    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Invalid provider '${removed_provider}'"* ]]
    [[ ! -s "$CLAUDE_ARGS_LOG" ]]
}

@test "rejects null assertions before invoking Claude" {
    local config_file="${SKILL_DIR}/evals/eval-config.json"
    jq '.test_cases[0].assertions = null' "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    run_eval_runner

    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Invalid eval-config.json"* ]]
    [[ ! -s "$CLAUDE_ARGS_LOG" ]]
}

@test "rejects missing assertions before invoking Claude" {
    local config_file="${SKILL_DIR}/evals/eval-config.json"
    jq 'del(.test_cases[0].assertions)' "$config_file" > "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"

    run_eval_runner

    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Invalid eval-config.json"* ]]
    [[ ! -s "$CLAUDE_ARGS_LOG" ]]
}

@test "reports infrastructure failure as JSONL" {
    install_failures_touch_stub

    run_eval_runner

    [ "$status" -eq 1 ]
    [[ ! -s "$CLAUDE_ARGS_LOG" ]]

    local jsonl_output="$output"
    run jq -e 'select(
        .event == "case"
        and .id == "contract"
        and .status == "failed"
        and .failed_assertions[0].type == "infrastructure"
    )' <<< "$jsonl_output"
    [ "$status" -eq 0 ]

    run jq -e 'select(
        .event == "summary"
        and .total == 1
        and .passed == 0
        and .failed == 1
    )' <<< "$jsonl_output"
    [ "$status" -eq 0 ]
}

@test "reports infrastructure failure in pretty output" {
    install_failures_touch_stub

    run_eval_runner --pretty

    [ "$status" -eq 1 ]
    [[ ! -s "$CLAUDE_ARGS_LOG" ]]
    [[ "$output" == *"INFRASTRUCTURE FAILURE"* ]]
    [[ "$output" == *"FAILED"* ]]
}
