#!/bin/bash

set -euo pipefail
umask 077

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALLER="$SCRIPT_DIRECTORY/../scripts/install.sh"
SOURCE_SCRIPT="$(CDPATH= cd -- "$SCRIPT_DIRECTORY/../scripts" && pwd -P)/run-groot-queue.sh"
TEMPORARY_DIRECTORY="$(mktemp -d -t groot-queue-install-test.XXXXXX)"
trap 'rm -rf -- "$TEMPORARY_DIRECTORY"' EXIT HUP INT TERM

TEST_HOME="$TEMPORARY_DIRECTORY/home"
TARGET_SCRIPT="$TEST_HOME/.local/bin/run-groot-queue"
STDOUT_FILE="$TEMPORARY_DIRECTORY/stdout.log"
STDERR_FILE="$TEMPORARY_DIRECTORY/stderr.log"
mkdir -p "$TEST_HOME"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    [ ! -s "$STDOUT_FILE" ] || cat "$STDOUT_FILE" >&2
    [ ! -s "$STDERR_FILE" ] || cat "$STDERR_FILE" >&2
    exit 1
}

run_installer() {
    HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:/usr/bin:/bin" \
        /bin/bash "$INSTALLER" >"$STDOUT_FILE" 2>"$STDERR_FILE"
}

assert_installed_wrapper() {
    [ -f "$TARGET_SCRIPT" ] || fail 'installed launcher is not a regular file'
    [ ! -L "$TARGET_SCRIPT" ] || fail 'installed launcher must not be a mutable symlink'
    [ -x "$TARGET_SCRIPT" ] || fail 'installed launcher is not executable'
    grep -Fq "$SOURCE_SCRIPT" "$TARGET_SCRIPT" || fail 'installed wrapper points to unexpected source'
}

run_installer
assert_installed_wrapper
HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:/usr/bin:/bin" \
    "$TARGET_SCRIPT" --help >"$STDOUT_FILE" 2>"$STDERR_FILE"
grep -q 'run-groot-queue' "$STDOUT_FILE" || fail 'installed wrapper cannot execute launcher help'

cat > "$TEST_HOME/.local/bin/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$*"
STUB
chmod 700 "$TEST_HOME/.local/bin/claude"
HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:/usr/bin:/bin" \
    "$TARGET_SCRIPT" --provider claude setup --help >"$STDOUT_FILE" 2>"$STDERR_FILE"
grep -q '/groot-queue setup --help' "$STDOUT_FILE" || fail 'installed wrapper did not resolve plugin skill before launching child'
printf 'ok - initial install creates a stable executable wrapper\n'

before_checksum="$(shasum "$TARGET_SCRIPT" | cut -d' ' -f1)"
run_installer
after_checksum="$(shasum "$TARGET_SCRIPT" | cut -d' ' -f1)"
[ "$before_checksum" = "$after_checksum" ] || fail 'idempotent install changed wrapper content'
printf 'ok - repeated install is a no-op for the same source\n'

rm -f -- "$TARGET_SCRIPT"
printf 'previous launcher\n' > "$TARGET_SCRIPT"
printf 'y\n' | HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:/usr/bin:/bin" \
    /bin/bash "$INSTALLER" >"$STDOUT_FILE" 2>"$STDERR_FILE"
assert_installed_wrapper
printf 'ok - confirmed replacement publishes expected wrapper\n'

rm -f -- "$TARGET_SCRIPT"
mkdir -p "$TEMPORARY_DIRECTORY/target-directory"
ln -s "$TEMPORARY_DIRECTORY/target-directory" "$TARGET_SCRIPT"
printf 'y\n' | HOME="$TEST_HOME" PATH="$TEST_HOME/.local/bin:/usr/bin:/bin" \
    /bin/bash "$INSTALLER" >"$STDOUT_FILE" 2>"$STDERR_FILE"
assert_installed_wrapper
printf 'ok - symlink-to-directory is replaced at target path\n'

rm -f -- "$TARGET_SCRIPT"
mkdir -p "$TARGET_SCRIPT"
set +e
run_installer
installer_status=$?
set -e
[ "$installer_status" -eq 1 ] || fail 'directory collision should fail with exit 1'
[ -d "$TARGET_SCRIPT" ] || fail 'directory collision modified existing directory'
printf 'ok - directory collision fails without partial installation\n'

printf 'All install tests passed.\n'
