#!/bin/bash

set -euo pipefail
umask 077

if [ "${RUN_GROOT_QUEUE_E2E:-0}" != "1" ]; then
    printf 'SKIP: set RUN_GROOT_QUEUE_E2E=1 to run real Claude setup wiring.\n'
    exit 0
fi

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER="$SCRIPT_DIRECTORY/../scripts/run-groot-queue.sh"
MODEL="${GROOT_QUEUE_E2E_MODEL:-claude-sonnet-5}"
TEMPORARY_DIRECTORY="$(mktemp -d -t groot-queue-setup-e2e.XXXXXX)"
trap 'rm -rf -- "$TEMPORARY_DIRECTORY"' EXIT HUP INT TERM
STDOUT_FILE="$TEMPORARY_DIRECTORY/stdout.log"
STDERR_FILE="$TEMPORARY_DIRECTORY/stderr.log"

hash_file() {
    if [ -f "$1" ]; then
        shasum "$1" | cut -d' ' -f1
    else
        printf 'missing'
    fi
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    [ ! -s "$STDERR_FILE" ] || tail -n 40 "$STDERR_FILE" >&2
    exit 1
}

CLAUDE_SETTINGS_BEFORE="$(hash_file "$HOME/.claude/settings.json")"
CLAUDE_PLUGINS_BEFORE="$(hash_file "$HOME/.claude/plugins/installed_plugins.json")"
CODEX_CONFIG_BEFORE="$(hash_file "$HOME/.codex/config.toml")"

"$RUNNER" --provider claude --model "$MODEL" setup >"$STDOUT_FILE" 2>"$STDERR_FILE"

[ "$CLAUDE_SETTINGS_BEFORE" = "$(hash_file "$HOME/.claude/settings.json")" ] || fail 'Claude settings changed during setup'
[ "$CLAUDE_PLUGINS_BEFORE" = "$(hash_file "$HOME/.claude/plugins/installed_plugins.json")" ] || fail 'Claude plugin inventory changed during setup'
[ "$CODEX_CONFIG_BEFORE" = "$(hash_file "$HOME/.codex/config.toml")" ] || fail 'Codex config changed during setup'

grep -q 'Setup — Groot Queue' "$STDOUT_FILE" || fail 'setup summary was not rendered'
grep -q 'Grid Sharing plugin' "$STDOUT_FILE" || fail 'Grid shell readiness was not merged into setup'
grep -q 'Fury plugin' "$STDOUT_FILE" || fail 'Fury shell readiness was not merged into setup'
grep -q 'FuryDocs component' "$STDOUT_FILE" || fail 'FuryDocs component discovery was not rendered'
grep -q 'FuryDocs required tools' "$STDOUT_FILE" || fail 'FuryDocs tool discovery was not rendered'
grep -Eq 'Setup completo|Setup incompleto' "$STDOUT_FILE" || fail 'setup final status was not rendered'

printf 'ok - real setup executes fresh shell readiness and FuryDocs runtime discovery without config mutations\n'
