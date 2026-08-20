#!/usr/bin/env bats

setup() {
    SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$BATS_TEST_FILENAME")" && pwd -P)"
    RENDERER="$SCRIPT_DIRECTORY/../skills/groot-queue/scripts/render-catalog.sh"
}

@test "catalog renders updated setup guidance and direct-command tip" {
    run /bin/bash "$RENDERER"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Verificá entorno y repará automáticamente assets faltantes o desactualizados."* ]]
    [[ "$output" == *"Ejecutá cualquier comando directamente desde esta lista."* ]]
}

@test "catalog includes each critical command exactly once" {
    run /bin/bash "$RENDERER"

    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '\*\*/groot-queue\*\* `setup`')" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '\*\*/groot-queue\*\* `derive`')" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '\*\*/groot-queue\*\* `discard`')" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '\*\*/groot-queue\*\* `analyze-history`')" -eq 1 ]
}
