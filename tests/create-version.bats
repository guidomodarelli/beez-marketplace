#!/usr/bin/env bats

setup() {
  repository_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  test_root="$(mktemp -d)"
  repo_dir="$test_root/repo"
  mkdir -p \
    "$repo_dir/scripts" \
    "$repo_dir/plugins/groot-kit/.claude-plugin" \
    "$repo_dir/plugins/groot-kit/.codex-plugin"

  cp "$repository_root/scripts/create-version.js" "$repo_dir/scripts/create-version.js"
  cat > "$repo_dir/plugins/groot-kit/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "groot-kit",
  "version": "1.12.0"
}
JSON
  cat > "$repo_dir/plugins/groot-kit/.codex-plugin/plugin.json" <<'JSON'
{
  "name": "groot-kit",
  "version": "1.12.0"
}
JSON

  git -C "$repo_dir" -c init.defaultBranch=main init -q
  git -C "$repo_dir" config user.name "Create Version Test"
  git -C "$repo_dir" config user.email "create-version-test@example.com"
  git -C "$repo_dir" add -A
  git -C "$repo_dir" commit -qm "Initialize fixture"

  remote_dir="$test_root/remote.git"
  git -c init.defaultBranch=main init -q --bare "$remote_dir"
  git -C "$repo_dir" remote add origin "$remote_dir"
  git -C "$repo_dir" push -q origin main
  unset FORCE_COLOR NO_COLOR
  cd "$repo_dir"
}

remote_head() {
  git -C "$remote_dir" rev-parse --verify --quiet "refs/heads/$1"
}

teardown() {
  cd "$repository_root"
  rm -rf "$test_root"
}

@test "auto-detects one changed plugin and commits all current changes" {
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md
  printf '%s\n' 'staged change' > staged.txt
  git add staged.txt
  printf '%s\n' 'untracked change' > untracked.txt

  run bash -c "printf '1\\n' | node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected changed plugin: groot-kit"* ]]
  [[ "$output" != *"Select a plugin by number"* ]]
  [ "$(node -p "require('./plugins/groot-kit/.claude-plugin/plugin.json').version")" = "1.12.1" ]
  [ "$(node -p "require('./plugins/groot-kit/.codex-plugin/plugin.json').version")" = "1.12.1" ]
  [ "$(git log -1 --pretty=%s)" = 'Bump the version number from 1.12.0 to 1.12.1 in both "plugin.json" files for the "groot-kit" plugin' ]
  git log -1 --pretty=%B | grep -Fxq 'Co-Authored-By: Claude Code <noreply@anthropic.com>'
  git show --format= --name-only HEAD | grep -Fxq 'plugins/groot-kit/docs/change.md'
  git show --format= --name-only HEAD | grep -Fxq 'staged.txt'
  git show --format= --name-only HEAD | grep -Fxq 'untracked.txt'
  [ -z "$(git status --porcelain)" ]
}

@test "auto-detects plugin changed in branch history" {
  git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
  git switch -q -c feature/groot-kit-change
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'committed plugin change' > plugins/groot-kit/docs/committed.md
  git add plugins/groot-kit/docs/committed.md
  git commit -qm "Change Groot Kit"

  run bash -c "printf '1\\n' | node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected changed plugin: groot-kit"* ]]
  [[ "$output" != *"Select a plugin by number"* ]]
  [ "$(node -p "require('./plugins/groot-kit/.claude-plugin/plugin.json').version")" = "1.12.1" ]
  [ -z "$(git status --porcelain)" ]
}

@test "keeps plugin menu when multiple plugins changed" {
  mkdir -p \
    plugins/groot-kit/docs \
    plugins/other-plugin/.claude-plugin \
    plugins/other-plugin/.codex-plugin
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md
  cat > plugins/other-plugin/.claude-plugin/plugin.json <<'JSON'
{
  "name": "other-plugin",
  "version": "2.0.0"
}
JSON
  cat > plugins/other-plugin/.codex-plugin/plugin.json <<'JSON'
{
  "name": "other-plugin",
  "version": "2.0.0"
}
JSON

  run bash -c "printf '1\\n1\\n' | node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected changed plugins:"* ]]
  [[ "$output" == *"Select a plugin by number"* ]]
  [ -z "$(git status --porcelain)" ]
}

@test "pushes new feature branch and sets upstream" {
  git switch -q -c feature/groot-kit-change
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "printf '1\\n' | node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Pushed "feature/groot-kit-change" to origin'* ]]
  [ "$(remote_head feature/groot-kit-change)" = "$(git rev-parse HEAD)" ]
  [ "$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}')" = "origin/feature/groot-kit-change" ]
}

@test "pushes to existing upstream branch" {
  git switch -q -c feature/groot-kit-change
  git push -q -u origin HEAD
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "printf '2\\n' | node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [ "$(node -p "require('./plugins/groot-kit/.claude-plugin/plugin.json').version")" = "1.13.0" ]
  [ "$(remote_head feature/groot-kit-change)" = "$(git rev-parse HEAD)" ]
}

@test "skips push on default branch" {
  initial_remote_main="$(remote_head main)"
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "printf '1\\n' | node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Skipped push: "main" is a default branch'* ]]
  [ "$(remote_head main)" = "$initial_remote_main" ]
  [ "$(git log -1 --pretty=%s)" = 'Bump the version number from 1.12.0 to 1.12.1 in both "plugin.json" files for the "groot-kit" plugin' ]
}

@test "reports push failure and keeps local commit" {
  git switch -q -c feature/groot-kit-change
  git remote set-url origin "$test_root/missing-remote.git"
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "printf '1\\n' | node scripts/create-version.js"

  [ "$status" -eq 1 ]
  [[ "$output" == *'Version bump commit was created but "git push -u origin HEAD" failed for branch "feature/groot-kit-change"'* ]]
  [ "$(git log -1 --pretty=%s)" = 'Bump the version number from 1.12.0 to 1.12.1 in both "plugin.json" files for the "groot-kit" plugin' ]
  [ -z "$(git status --porcelain)" ]
}

@test "prints plain output when stdout is not a terminal" {
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "printf '1\\n' | node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e['* ]]
  [[ "$output" == *"╭─ 📦 Plugin"* ]]
  [[ "$output" == *"1.12.0 → 1.12.1"* ]]
}

@test "colors output when FORCE_COLOR is set" {
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "printf '1\\n' | FORCE_COLOR=1 node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[32m'* ]]
}

@test "NO_COLOR overrides FORCE_COLOR" {
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "printf '1\\n' | FORCE_COLOR=1 NO_COLOR=1 node scripts/create-version.js"

  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e['* ]]
}

@test "dry run previews bump without writing, committing or pushing" {
  git switch -q -c feature/groot-kit-change
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md
  initial_head="$(git rev-parse HEAD)"
  initial_status="$(git status --porcelain)"

  run bash -c "printf '1\\n' | node scripts/create-version.js --dry-run"

  [ "$status" -eq 0 ]
  [[ "$output" == *"🧪 DRY RUN"* ]]
  [[ "$output" == *"Would update plugins/groot-kit/.claude-plugin/plugin.json"* ]]
  [[ "$output" == *'Would commit all current changes: Bump the version number from 1.12.0 to 1.12.1'* ]]
  [[ "$output" == *'Would push "feature/groot-kit-change" to origin (git push -u origin HEAD)'* ]]
  [ "$(node -p "require('./plugins/groot-kit/.claude-plugin/plugin.json').version")" = "1.12.0" ]
  [ "$(node -p "require('./plugins/groot-kit/.codex-plugin/plugin.json').version")" = "1.12.0" ]
  [ "$(git rev-parse HEAD)" = "$initial_head" ]
  [ "$(git status --porcelain)" = "$initial_status" ]
  [ -z "$(remote_head feature/groot-kit-change)" ]
}

@test "dry run shorthand works with plugin name on default branch" {
  run bash -c "printf '3\\n' | node scripts/create-version.js -n groot-kit"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1.12.0 → 2.0.0"* ]]
  [[ "$output" == *'Would skip push: "main" is a default branch'* ]]
  [ "$(node -p "require('./plugins/groot-kit/.claude-plugin/plugin.json').version")" = "1.12.0" ]
  [ "$(git log -1 --pretty=%s)" = "Initialize fixture" ]
}

@test "rejects unknown options" {
  run bash -c "node scripts/create-version.js --force"

  [ "$status" -eq 1 ]
  [[ "$output" == *'Unknown option "--force". Supported options: --dry-run, -n'* ]]
}

@test "prints help without touching the repository" {
  run bash -c "node scripts/create-version.js -h"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"--bump <kind>"* ]]
  [[ "$output" == *"--set <version>"* ]]
  [ "$(git log -1 --pretty=%s)" = "Initialize fixture" ]
}

@test "bumps without prompts using --bump" {
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "node scripts/create-version.js groot-kit --bump minor < /dev/null"

  [ "$status" -eq 0 ]
  [[ "$output" != *"Select an option"* ]]
  [ "$(node -p "require('./plugins/groot-kit/.claude-plugin/plugin.json').version")" = "1.13.0" ]
  [ "$(node -p "require('./plugins/groot-kit/.codex-plugin/plugin.json').version")" = "1.13.0" ]
}

@test "sets exact version using --set=value" {
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "node scripts/create-version.js --set=3.1.4 < /dev/null"

  [ "$status" -eq 0 ]
  [ "$(node -p "require('./plugins/groot-kit/.claude-plugin/plugin.json').version")" = "3.1.4" ]
}

@test "combines dry run with --set" {
  mkdir -p plugins/groot-kit/docs
  printf '%s\n' 'plugin change' > plugins/groot-kit/docs/change.md

  run bash -c "node scripts/create-version.js -n --set 2.0.0 < /dev/null"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1.12.0 → 2.0.0"* ]]
  [ "$(node -p "require('./plugins/groot-kit/.claude-plugin/plugin.json').version")" = "1.12.0" ]
}

@test "rejects invalid --bump and --set values" {
  run bash -c "node scripts/create-version.js --bump huge"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Invalid --bump value "huge". Expected one of: patch, minor, major'* ]]

  run bash -c "node scripts/create-version.js --set 1.2"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Invalid --set value "1.2". Expected MAJOR.MINOR.PATCH.'* ]]
}

@test "rejects --bump with --set and missing values" {
  run bash -c "node scripts/create-version.js --bump patch --set 2.0.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Options --bump and --set cannot be used together."* ]]

  run bash -c "node scripts/create-version.js --bump --dry-run"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Option "--bump" requires a value.'* ]]
}
