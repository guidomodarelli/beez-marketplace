#!/usr/bin/env bats

setup() {
  repository_root="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  skill_dir="$repository_root/plugins/groot-kit/skills/agent-ready-setup"
  test_root="$(mktemp -d)"
  project_dir="$test_root/project"
  fake_bin="$test_root/bin"
  mkdir -p "$project_dir" "$fake_bin" "$test_root/tmp"
  export TMPDIR="$test_root/tmp"
  git -C "$project_dir" -c init.defaultBranch=main init -q
  cd "$project_dir"
  valid_node_rule_block=$'## Rules\n\n<!-- BEGIN AGENT-READY RULE REFERENCES -->\n- Read and follow `.agents/rules/coding-style.md`.\n- Read and follow `.agents/rules/security.md`.\n- Read and follow `.agents/rules/testing.md`.\n<!-- END AGENT-READY RULE REFERENCES -->'
}

write_auto_claude_response() {
  local merged_content="$1"

  jq -n \
    --arg content "$merged_content" \
    '{status:"auto", merged_content:$content, reason:"Rules are compatible and references are complete.", conflicts:[]}' \
    > "$test_root/provider-response.json"
  cat > "$fake_bin/claude" <<EOF
#!/bin/bash
cat "$test_root/provider-response.json"
EOF
  chmod +x "$fake_bin/claude"
}

teardown() {
  cd "$repository_root"
  rm -rf "$test_root"
}

@test "auto merge preserves unverified legacy-looking files and visible metadata" {
  printf '%s\n' '# Existing project instructions' > AGENTS.md
  printf '%s\n' '@AGENTS.md' > CLAUDE.md
  printf '%s\n' '# Project-owned file' > AGENTS.md.agent-ready-backup.stale
  write_auto_claude_response $'# Existing project instructions\n\n'"$valid_node_rule_block"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(cat AGENTS.md)" = $'# Existing project instructions\n\n'"$valid_node_rule_block" ]
  [ "$(cat CLAUDE.md)" = '@AGENTS.md' ]
  [ "$(cat AGENTS.md.agent-ready-backup.stale)" = '# Project-owned file' ]
  [ -f AGENTS.md.agent-ready-backup.stale ]
  [ -f .git/info/agent-ready-instructions-template.sha256 ]
  [ ! -e .agents/.agent-ready-instructions-template.sha256 ]
  hash_files=(.git/info/agent-ready-instructions-template.sha256*)
  [ "${#hash_files[@]}" -eq 1 ]
  [[ "$output" == *"Updated AGENTS.md automatically; no backup retained."* ]]

  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
exit 42
EOF
  chmod +x "$fake_bin/claude"
  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Template and AGENTS.md rule references unchanged; AI instruction merge not required."* ]]
}

@test "successful merge replaces AGENTS atomically without temporary residue" {
  printf '%s\n' '# Existing project instructions' > AGENTS.md
  write_auto_claude_response $'# Updated project instructions\n\n'"$valid_node_rule_block"
  original_inode="$(ls -di AGENTS.md | awk '{print $1}')"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  updated_inode="$(ls -di AGENTS.md | awk '{print $1}')"
  [ "$updated_inode" != "$original_inode" ]
  [ "$(cat AGENTS.md)" = $'# Updated project instructions\n\n'"$valid_node_rule_block" ]
  temporary_files=(.AGENTS.md.agent-ready-merge.*)
  [ ! -e "${temporary_files[0]}" ]
}

@test "template hash metadata is isolated per linked worktree" {
  git config user.email "agent-ready-tests@example.com"
  git config user.name "Agent Ready Tests"
  printf '%s\n' '# Initial repository content' > README.md
  git add README.md
  git commit -qm "Initialize linked worktree test"

  linked_project_dir="$test_root/linked-project"
  git worktree add -q -b linked-worktree "$linked_project_dir"
  printf '%s\n' '# Existing project instructions' > AGENTS.md
  printf '%s\n' '# Existing project instructions' > "$linked_project_dir/AGENTS.md"

  write_auto_claude_response $'# Existing project instructions\n\n'"$valid_node_rule_block"
  provider_call_log="$test_root/provider-calls.log"
  cat > "$fake_bin/claude" <<EOF
#!/bin/bash
printf '%s\\n' called >> "$provider_call_log"
cat "$test_root/provider-response.json"
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"
  [ "$status" -eq 0 ]

  cd "$linked_project_dir"
  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"
  [ "$status" -eq 0 ]

  main_git_directory="$(git -C "$project_dir" rev-parse --absolute-git-dir)"
  linked_git_directory="$(git -C "$linked_project_dir" rev-parse --absolute-git-dir)"
  main_hash_file="$main_git_directory/info/agent-ready-instructions-template.sha256"
  linked_hash_file="$linked_git_directory/info/agent-ready-instructions-template.sha256"

  [ -f "$main_hash_file" ]
  [ -f "$linked_hash_file" ]
  [ "$main_hash_file" != "$linked_hash_file" ]
  [ "$(wc -l < "$provider_call_log" | tr -d ' ')" -eq 2 ]
}

@test "provider receives dynamic Codex-readable rule catalog" {
  printf '%s\n' '# Existing project instructions' > AGENTS.md
  write_auto_claude_response $'# Existing project instructions\n\n'"$valid_node_rule_block"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$CLAUDE_PROMPT_LOG"
cat "$CLAUDE_RESPONSE_FILE"
EOF
  chmod +x "$fake_bin/claude"

  CLAUDE_PROMPT_LOG="$test_root/claude-prompt.log" \
    CLAUDE_RESPONSE_FILE="$test_root/provider-response.json" \
    PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
      --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  grep -Fq '.agents/rules/coding-style.md' "$test_root/claude-prompt.log"
  grep -Fq '.agents/rules/security.md' "$test_root/claude-prompt.log"
  grep -Fq '.agents/rules/testing.md' "$test_root/claude-prompt.log"
  ! grep -Fq '{{AGENT_READY_RULE_REFERENCES}}' "$test_root/claude-prompt.log"
}

@test "AI repairs existing Claude-only rule references" {
  cat > AGENTS.md <<'EOF'
# Existing project instructions

## Rules

@./rules/coding-style.md
@./rules/security.md
@./rules/testing.md
EOF
  write_auto_claude_response $'# Existing project instructions\n\n'"$valid_node_rule_block"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  ! grep -Eq '@[^[:space:]]*rules/|@path/to/folder' AGENTS.md
  grep -Fq -- '- Read and follow `.agents/rules/coding-style.md`.' AGENTS.md
  grep -Fq -- '- Read and follow `.agents/rules/security.md`.' AGENTS.md
  grep -Fq -- '- Read and follow `.agents/rules/testing.md`.' AGENTS.md
}

@test "new rule files are included in sync merge template" {
  dynamic_skill_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$dynamic_skill_dir"
  printf '%s\n' '# Runtime-specific rules' > "$dynamic_skill_dir/assets/stacks/node/rules/runtime.md"
  printf '%s\n' '# Existing project instructions' > AGENTS.md
  dynamic_merged_content=$'# Existing project instructions\n\n## Rules\n\n<!-- BEGIN AGENT-READY RULE REFERENCES -->\n- Read and follow `.agents/rules/coding-style.md`.\n- Read and follow `.agents/rules/runtime.md`.\n- Read and follow `.agents/rules/security.md`.\n- Read and follow `.agents/rules/testing.md`.\n<!-- END AGENT-READY RULE REFERENCES -->'
  write_auto_claude_response "$dynamic_merged_content"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$CLAUDE_PROMPT_LOG"
cat "$CLAUDE_RESPONSE_FILE"
EOF
  chmod +x "$fake_bin/claude"

  CLAUDE_PROMPT_LOG="$test_root/dynamic-prompt.log" \
    CLAUDE_RESPONSE_FILE="$test_root/provider-response.json" \
    PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
      --provider claude --stack node --skill-dir "$dynamic_skill_dir"

  [ "$status" -eq 0 ]
  grep -Fq '.agents/rules/runtime.md' "$test_root/dynamic-prompt.log"
  grep -Fq '.agents/rules/runtime.md' AGENTS.md
}

@test "human-required merge falls back with an AGENTS backup" {
  printf '%s\n' '# Existing policy' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' '{"status":"human_required","merged_content":"# Existing policy\n\n# Conflicting policy\n","reason":"Policies require a precedence decision.","conflicts":["Existing and template policies disagree."]}'
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" != "$before_hash" ]
  [[ "$output" == *"Existing and template policies disagree."* ]]
  [[ "$output" == *"Applied template fallback"* ]]
  backup_files=("$test_root"/tmp/agent-ready-backups.*/AGENTS.md.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  [ "$(cat "${backup_files[0]}")" = '# Existing policy' ]
}

@test "invalid provider output falls back to template with AGENTS backup" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' 'not-json'
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack frontend --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" != "$before_hash" ]
  [[ "$output" == *"invalid structured output"* ]]
  [[ "$output" == *"Applied template fallback"* ]]
  backup_files=("$test_root"/tmp/agent-ready-backups.*/AGENTS.md.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  [ "$(cat "${backup_files[0]}")" = '# Keep this file' ]
}

@test "matching template hash does not skip incomplete rule references" {
  cat > AGENTS.md <<'EOF'
# Existing project instructions

## Rules

<!-- BEGIN AGENT-READY RULE REFERENCES -->
- Read and follow `.agents/rules/coding-style.md`.
- Read and follow `.agents/rules/security.md`.
<!-- END AGENT-READY RULE REFERENCES -->
EOF
  mkdir -p .agents .git/info
  candidate_file="$test_root/rendered-template.md"
  bash "$skill_dir/scripts/render-instruction-template.sh" \
    --template "$skill_dir/assets/stacks/node/CLAUDE.md" \
    --rules-dir "$skill_dir/assets/stacks/node/rules" > "$candidate_file"
  shasum "$candidate_file" | cut -d ' ' -f 1 > .agents/.agent-ready-instructions-template.sha256
  write_auto_claude_response $'# Existing project instructions\n\n'"$valid_node_rule_block"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  grep -Fq -- '- Read and follow `.agents/rules/testing.md`.' AGENTS.md
  [ ! -e .agents/.agent-ready-instructions-template.sha256 ]
  [ -f .git/info/agent-ready-instructions-template.sha256 ]
  [[ "$output" != *"merge not required"* ]]
}

@test "automatic merge rejects rule paths outside managed block" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  write_auto_claude_response $'# Invalid merge\n\nPaths mentioned in notes: .agents/rules/coding-style.md, .agents/rules/security.md, .agents/rules/testing.md.\n\n## Rules\n\n<!-- BEGIN AGENT-READY RULE REFERENCES -->\n<!-- END AGENT-READY RULE REFERENCES -->'

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" != "$before_hash" ]
  [[ "$output" == *"omitted or corrupted portable rule references"* ]]
  [[ "$output" == *"Applied template fallback"* ]]
  backup_files=("$test_root"/tmp/agent-ready-backups.*/AGENTS.md.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  [ "$(cat "${backup_files[0]}")" = '# Keep this file' ]
}

@test "automatic merge fails closed when a rule reference is omitted" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  write_auto_claude_response $'# Incomplete merge\n\n## Rules\n\n<!-- BEGIN AGENT-READY RULE REFERENCES -->\n- Read and follow `.agents/rules/security.md`.\n<!-- END AGENT-READY RULE REFERENCES -->'

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" != "$before_hash" ]
  [[ "$output" == *"omitted or corrupted portable rule references"* ]]
  [[ "$output" == *"Applied template fallback"* ]]
  backup_files=("$test_root"/tmp/agent-ready-backups.*/AGENTS.md.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  [ "$(cat "${backup_files[0]}")" = '# Keep this file' ]
}

@test "automatic merge rejects Claude-only rule references" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  write_auto_claude_response $'# Invalid merge\n\n## Rules\n\n<!-- BEGIN AGENT-READY RULE REFERENCES -->\n- Read and follow `.agents/rules/coding-style.md`.\n- Read and follow `@./rules/security.md`.\n- Read and follow `.agents/rules/security.md`.\n- Read and follow `.agents/rules/testing.md`.\n<!-- END AGENT-READY RULE REFERENCES -->'

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" != "$before_hash" ]
  [[ "$output" == *"omitted or corrupted portable rule references"* ]]
  [[ "$output" == *"Applied template fallback"* ]]
  backup_files=("$test_root"/tmp/agent-ready-backups.*/AGENTS.md.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  [ "$(cat "${backup_files[0]}")" = '# Keep this file' ]
}

@test "automatic merge rejects stale rule references" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  write_auto_claude_response $'# Invalid merge\n\n## Rules\n\n<!-- BEGIN AGENT-READY RULE REFERENCES -->\n- Read and follow `.agents/rules/coding-style.md`.\n- Read and follow `.agents/rules/security.md`.\n- Read and follow `.agents/rules/testing.md`.\n- Read and follow `.agents/rules/retired.md`.\n<!-- END AGENT-READY RULE REFERENCES -->'

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" != "$before_hash" ]
  [[ "$output" == *"omitted or corrupted portable rule references"* ]]
  [[ "$output" == *"Applied template fallback"* ]]
  backup_files=("$test_root"/tmp/agent-ready-backups.*/AGENTS.md.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  [ "$(cat "${backup_files[0]}")" = '# Keep this file' ]
}

@test "fenced provider output falls back to template with AGENTS backup" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' '{"status":"auto","merged_content":"```markdown\n# Not a complete response\n```","reason":"Invalid wrapper.","conflicts":[]}'
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" != "$before_hash" ]
  [[ "$output" == *"fenced content"* ]]
  [[ "$output" == *"Applied template fallback"* ]]
  backup_files=("$test_root"/tmp/agent-ready-backups.*/AGENTS.md.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  [ "$(cat "${backup_files[0]}")" = '# Keep this file' ]
}

@test "concurrent AGENTS changes are not overwritten by a stale merge" {
  printf '%s\n' '# Original instructions' > AGENTS.md
  write_auto_claude_response $'# Model merge\n\n'"$valid_node_rule_block"
  cat > "$fake_bin/claude" <<EOF
#!/bin/bash
printf '%s\n' '# Newer user instructions' > AGENTS.md
cat "$test_root/provider-response.json"
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -ne 0 ]
  [ "$(cat AGENTS.md)" = '# Newer user instructions' ]
  [[ "$output" == *"changed before descriptor write"* ]]
}

@test "atomic replacement rejects stale descriptor write" {
  printf '%s\n' '# Original instructions' > AGENTS.md
  write_auto_claude_response $'# Model merge\n\n'"$valid_node_rule_block"
  cat > "$fake_bin/python3" <<'EOF'
#!/bin/bash
printf '%s\n' '# Newer descriptor instructions' > .AGENTS.md.new
mv .AGENTS.md.new AGENTS.md
exec /usr/bin/python3 "$@"
EOF
  chmod +x "$fake_bin/python3"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -ne 0 ]
  [ "$(cat AGENTS.md)" = '# Newer descriptor instructions' ]
  [[ "$output" == *"changed before descriptor write"* ]]
}

@test "directory lock protects against pathname replacement during atomic update" {
  printf '%s\n' '# Original instructions' > AGENTS.md
  write_auto_claude_response $'# Model merge\n\n'"$valid_node_rule_block"
  python3 - "$test_root/provider-response.json" <<'PY'
import json
import sys


response_path = sys.argv[1]
with open(response_path, encoding='utf-8') as response_file:
    response = json.load(response_file)
response['merged_content'] = (
    '# Model merge\\n\\n'
    + ('# Merge operation in progress\\n' * 250000)
    + response['merged_content'].split('# Model merge\\n\\n', 1)[-1]
)
with open(response_path, 'w', encoding='utf-8') as response_file:
    json.dump(response, response_file)
PY
  race_marker="$test_root/race-detected"
  writer_script="$test_root/replace-after-merge.py"
  cat > "$writer_script" <<'PY'
import fcntl
import glob
import os
import sys
import time


race_marker = sys.argv[1]
deadline = time.monotonic() + 30
while not glob.glob('.AGENTS.md.agent-ready-merge.*'):
    if time.monotonic() >= deadline:
        sys.exit('merge temporary file was not created')
    time.sleep(0.001)

directory_descriptor = os.open('.', os.O_RDONLY)
try:
    fcntl.flock(directory_descriptor, fcntl.LOCK_EX)
    if glob.glob('.AGENTS.md.agent-ready-merge.*'):
        open(race_marker, 'w').close()
    replacement_path = '.concurrent-agents.md'
    with open(replacement_path, 'w', encoding='utf-8') as replacement_file:
        replacement_file.write('# Newer user instructions\n')
        replacement_file.flush()
        os.fsync(replacement_file.fileno())
    os.replace(replacement_path, 'AGENTS.md')
finally:
    os.close(directory_descriptor)
PY

  PATH="$fake_bin:$PATH" bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir" \
    > "$test_root/merge-output.log" 2>&1 &
  merge_pid=$!
  python3 "$writer_script" "$race_marker" > "$test_root/writer-output.log" 2>&1 &
  writer_pid=$!

  if wait "$merge_pid"; then
    merge_status=0
  else
    merge_status=$?
  fi
  if wait "$writer_pid"; then
    writer_status=0
  else
    writer_status=$?
  fi

  [ "$merge_status" -eq 0 ]
  [ "$writer_status" -eq 0 ]
  [ ! -e "$race_marker" ]
  [ "$(cat AGENTS.md)" = '# Newer user instructions' ]
  [ ! -e .concurrent-agents.md ]
}

@test "auto merge works with Codex structured output" {
  printf '%s\n' '# Existing project instructions' > AGENTS.md
  write_auto_claude_response $'# Codex merged instructions\n\n'"$valid_node_rule_block"
  cat > "$fake_bin/codex" <<EOF
#!/bin/bash
result_file=""
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == "--output-last-message" ]]; then
    result_file="\$2"
    shift 2
  else
    shift
  fi
done
cat "$test_root/provider-response.json" > "\$result_file"
EOF
  chmod +x "$fake_bin/codex"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider codex --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(cat AGENTS.md)" = $'# Codex merged instructions\n\n'"$valid_node_rule_block" ]
}

@test "existing merge lock prevents a second provider invocation" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  mkdir -p .agents/.agent-ready-instructions.lock
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' called > "$CLAUDE_CALL_LOG"
EOF
  chmod +x "$fake_bin/claude"

  CLAUDE_CALL_LOG="$test_root/claude-called.log" PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/scripts/merge-instructions.sh" \
      --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 2 ]
  [ ! -e "$test_root/claude-called.log" ]
  [[ "$output" == *"another instruction merge is running"* ]]
}

@test "missing AGENTS is created from template without invoking provider" {
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' called > "$CLAUDE_CALL_LOG"
EOF
  chmod +x "$fake_bin/claude"

  CLAUDE_CALL_LOG="$test_root/claude-called.log" PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/scripts/merge-instructions.sh" \
      --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ -f AGENTS.md ]
  grep -Fq '# [Project Name]' AGENTS.md
  [ ! -e "$test_root/claude-called.log" ]
}

@test "automatic sync hook runs upgrade, projection, and merge in order" {
  source_dir="$test_root/agent-ready-setup"
  event_log="$test_root/hook-events.log"
  merge_log="$test_root/hook-merge.log"
  mkdir -p \
    "$source_dir/assets/common/hooks" \
    "$source_dir/assets/codex" \
    "$source_dir/assets/stacks/frontend/hooks" \
    "$source_dir/scripts"
  touch "$source_dir/SKILL.md"
  cp "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
    "$source_dir/assets/common/hooks/sync-marketplace.sh"
  printf '%s\n' '{}' > "$source_dir/assets/common/settings.json"
  printf '%s\n' '{}' > "$source_dir/assets/codex/hooks.json"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
printf 'merge\n' >> "$EVENT_LOG"
printf '%s\n' "$*" > "$MERGE_LOG"
EOF
  chmod +x "$source_dir/scripts/merge-instructions.sh"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
printf 'fury\n' >> "$EVENT_LOG"
EOF
  chmod +x "$fake_bin/fury"
  printf '%s\n' '{"dependencies":{"react":"1.0.0"}}' > package.json

  EVENT_LOG="$event_log" \
    MERGE_LOG="$merge_log" \
    AGENT_READY_SETUP_SKILL_DIR="$source_dir" \
    PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$event_log")" = "fury" ]
  [ "$(sed -n '2p' "$event_log")" = "merge" ]
  [ "$(wc -l < "$event_log")" -eq 2 ]
  grep -Fq -- "Sync hook updated; restarting with latest version." <<< "$output"
  [ -f .agents/hooks/sync-marketplace.sh ]
  cmp -s .agents/hooks/sync-marketplace.sh "$source_dir/assets/common/hooks/sync-marketplace.sh"
  grep -Fq -- "--provider claude --stack frontend --skill-dir $source_dir" "$merge_log"
}

@test "automatic sync hook preserves session when merge needs human review" {
  source_dir="$test_root/agent-ready-setup"
  mkdir -p \
    "$source_dir/assets/common/hooks" \
    "$source_dir/assets/codex" \
    "$source_dir/assets/stacks/node/hooks" \
    "$source_dir/scripts"
  touch "$source_dir/SKILL.md"
  cp "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
    "$source_dir/assets/common/hooks/sync-marketplace.sh"
  printf '%s\n' '{}' > "$source_dir/assets/common/settings.json"
  printf '%s\n' '{}' > "$source_dir/assets/codex/hooks.json"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
[[ "${AGENT_READY_SETUP_NON_INTERACTIVE:-0}" == "1" ]] || exit 99
exit 2
EOF
  chmod +x "$source_dir/scripts/merge-instructions.sh"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$fake_bin/fury"
  printf '%s\n' '{}' > package.json

  AGENT_READY_SETUP_SKILL_DIR="$source_dir" PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack node
  [ "$status" -eq 0 ]
  [[ "$output" == *"requires human review"* ]]
}
