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
  cd "$repo_dir"
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
