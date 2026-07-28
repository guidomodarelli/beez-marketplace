#!/usr/bin/env bats

setup() {
    umask 077

    SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$BATS_TEST_FILENAME")" && pwd -P)"
    INSTALLER="$SCRIPT_DIRECTORY/../scripts/install.sh"
    SOURCE_SCRIPT="$(CDPATH= cd -- "$SCRIPT_DIRECTORY/../scripts" && pwd -P)/run-groot-queue.sh"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    TARGET_SCRIPT="$TEST_HOME/.local/bin/run-groot-queue"
    STDOUT_FILE="$BATS_TEST_TMPDIR/stdout.log"
    STDERR_FILE="$BATS_TEST_TMPDIR/stderr.log"

    mkdir -p "$TEST_HOME"
}

run_installer() {
    HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:/usr/bin:/bin" \
        /bin/bash "$INSTALLER" >"$STDOUT_FILE" 2>"$STDERR_FILE"
}

run_installer_with_confirmation() {
    printf 'y\n' | HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:/usr/bin:/bin" \
        /bin/bash "$INSTALLER" >"$STDOUT_FILE" 2>"$STDERR_FILE"
}

run_installed_launcher() {
    HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:/usr/bin:/bin" \
        "$TARGET_SCRIPT" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
}

assert_command_succeeded() {
    if [ "$status" -ne 0 ]; then
        printf 'Expected command to succeed, got exit %s.\n' "$status" >&2
        [ ! -s "$STDOUT_FILE" ] || cat "$STDOUT_FILE" >&2
        [ ! -s "$STDERR_FILE" ] || cat "$STDERR_FILE" >&2
        return 1
    fi
}

assert_installed_wrapper() {
    [ -f "$TARGET_SCRIPT" ] || {
        printf 'Installed launcher is not a regular file.\n' >&2
        return 1
    }
    [ ! -L "$TARGET_SCRIPT" ] || {
        printf 'Installed launcher must not be a mutable symlink.\n' >&2
        return 1
    }
    [ -x "$TARGET_SCRIPT" ] || {
        printf 'Installed launcher is not executable.\n' >&2
        return 1
    }
    grep -Fq "$SOURCE_SCRIPT" "$TARGET_SCRIPT" || {
        printf 'Installed wrapper points to an unexpected source.\n' >&2
        return 1
    }
}

@test "initial install creates a stable executable wrapper that forwards commands" {
    run run_installer
    assert_command_succeeded
    assert_installed_wrapper

    run run_installed_launcher --help
    assert_command_succeeded
    grep -q 'run-groot-queue' "$STDOUT_FILE"

    cat > "$TEST_HOME/.local/bin/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$*"
STUB
    chmod 700 "$TEST_HOME/.local/bin/claude"

    run run_installed_launcher --provider claude setup --help
    assert_command_succeeded
    grep -q '/groot-queue setup --help' "$STDOUT_FILE"
}

@test "repeated install is a no-op for the same source" {
    run run_installer
    assert_command_succeeded
    before_checksum="$(shasum "$TARGET_SCRIPT" | cut -d' ' -f1)"

    run run_installer
    assert_command_succeeded
    after_checksum="$(shasum "$TARGET_SCRIPT" | cut -d' ' -f1)"

    [ "$before_checksum" = "$after_checksum" ]
    grep -Fq 'run-groot-queue ya apunta al launcher actual' "$STDOUT_FILE"
    ! grep -Fq 'run-groot-queue instalado →' "$STDOUT_FILE"
}

@test "confirmed replacement publishes the expected wrapper" {
    mkdir -p "$(dirname -- "$TARGET_SCRIPT")"
    printf 'previous launcher\n' > "$TARGET_SCRIPT"

    run run_installer_with_confirmation
    assert_command_succeeded
    assert_installed_wrapper
}

@test "symlink to a directory is replaced at the target path" {
    mkdir -p "$(dirname -- "$TARGET_SCRIPT")" "$BATS_TEST_TMPDIR/target-directory"
    ln -s "$BATS_TEST_TMPDIR/target-directory" "$TARGET_SCRIPT"

    run run_installer_with_confirmation
    assert_command_succeeded
    assert_installed_wrapper
}

@test "directory collision fails without partial installation" {
    mkdir -p "$TARGET_SCRIPT"

    run run_installer

    [ "$status" -eq 1 ]
    [ -d "$TARGET_SCRIPT" ]
}
