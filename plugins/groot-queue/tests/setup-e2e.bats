#!/usr/bin/env bats

setup() {
    umask 077

    SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$BATS_TEST_FILENAME")" && pwd -P)"
    PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIRECTORY/../../.." && pwd -P)"
    RUNNER="$SCRIPT_DIRECTORY/../scripts/run-groot-queue.sh"
    MODEL="${GROOT_QUEUE_E2E_MODEL:-claude-sonnet-5}"
    STDOUT_FILE="$BATS_TEST_TMPDIR/stdout.log"
    STDERR_FILE="$BATS_TEST_TMPDIR/stderr.log"
}

hash_file() {
    if [ -f "$1" ]; then
        shasum "$1" | cut -d' ' -f1
    else
        printf 'missing'
    fi
}

run_real_setup() {
    "$RUNNER" --provider claude --model "$MODEL" setup >"$STDOUT_FILE" 2>"$STDERR_FILE"
}

assert_setup_output() {
    local expected_output="$1"

    grep -q "$expected_output" "$STDOUT_FILE" || {
        printf 'Setup output did not contain: %s\n' "$expected_output" >&2
        return 1
    }
}

assert_setup_output_excludes() {
    local unexpected_output="$1"

    if grep -qF "$unexpected_output" "$STDOUT_FILE"; then
        printf 'Setup output unexpectedly contained: %s\n' "$unexpected_output" >&2
        return 1
    fi
}

@test "real setup executes shell readiness and FuryDocs discovery without config mutations" {
    if [ "${RUN_GROOT_QUEUE_E2E:-0}" != "1" ]; then
        skip 'set RUN_GROOT_QUEUE_E2E=1 to run real Claude setup wiring'
    fi

    claude_settings_before="$(hash_file "$HOME/.claude/settings.json")"
    claude_plugins_before="$(hash_file "$HOME/.claude/plugins/installed_plugins.json")"
    codex_config_before="$(hash_file "$HOME/.codex/config.toml")"
    project_settings_local_before="$(hash_file "$PROJECT_ROOT/.claude/settings.local.json")"

    run run_real_setup
    if [ "$status" -ne 0 ]; then
        printf 'Real setup failed with exit %s.\n' "$status" >&2
        [ ! -s "$STDERR_FILE" ] || tail -n 40 "$STDERR_FILE" >&2
        return 1
    fi

    [ "$claude_settings_before" = "$(hash_file "$HOME/.claude/settings.json")" ]
    [ "$claude_plugins_before" = "$(hash_file "$HOME/.claude/plugins/installed_plugins.json")" ]
    [ "$codex_config_before" = "$(hash_file "$HOME/.codex/config.toml")" ]
    [ "$project_settings_local_before" = "$(hash_file "$PROJECT_ROOT/.claude/settings.local.json")" ]

    assert_setup_output 'Setup — Groot Queue'
    assert_setup_output 'Grid Sharing plugin'
    assert_setup_output 'Fury plugin'
    assert_setup_output 'FuryDocs component'
    assert_setup_output 'FuryDocs required tools'
    assert_setup_output 'Setup completo'
    assert_setup_output_excludes 'Setup incompleto'
    assert_setup_output_excludes 'Permisos ACLI Claude'
    assert_setup_output_excludes 'crear `.claude/settings.local.json`'
}
