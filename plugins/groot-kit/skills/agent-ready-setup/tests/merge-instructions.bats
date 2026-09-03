#!/usr/bin/env bats

setup() {
  repository_root="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  skill_dir="$repository_root/plugins/groot-kit/skills/agent-ready-setup"
  test_root="$(mktemp -d)"
  project_dir="$test_root/project"
  fake_bin="$test_root/bin"
  mkdir -p "$project_dir" "$fake_bin"
  git -C "$project_dir" -c init.defaultBranch=main init -q
  cd "$project_dir"
}

teardown() {
  cd "$repository_root"
  rm -rf "$test_root"
}

@test "auto merge updates AGENTS and creates a backup without confirmation" {
  printf '%s\n' '# Existing project instructions' > AGENTS.md
  printf '%s\n' '@AGENTS.md' > CLAUDE.md
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' '{"status":"auto","merged_content":"# Existing project instructions\n\n# New template rule\n","reason":"Template rule is additive.","conflicts":[]}'
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(cat AGENTS.md)" = $'# Existing project instructions\n\n# New template rule' ]
  [ "$(cat CLAUDE.md)" = '@AGENTS.md' ]
  backup_files=(AGENTS.md.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  [ -f .agents/.agent-ready-instructions-template.sha256 ]
  [[ "$output" == *"Updated AGENTS.md automatically"* ]]

  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
exit 42
EOF
  chmod +x "$fake_bin/claude"
  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Template unchanged; AI instruction merge not required."* ]]
}

@test "human-required merge preserves AGENTS without a TTY" {
  printf '%s\n' '# Existing policy' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' '{"status":"human_required","merged_content":"# Existing policy\n\n# Conflicting policy\n","reason":"Policies require a precedence decision.","conflicts":["Existing and template policies disagree."]}'
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 2 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" = "$before_hash" ]
  [[ "$output" == *"Existing and template policies disagree."* ]]
  [[ "$output" == *"Human confirmation required"* ]]
  backup_files=(AGENTS.md.agent-ready-backup.*)
  [ ! -e "${backup_files[0]}" ]
}

@test "invalid provider output fails closed without changing AGENTS" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' 'not-json'
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack frontend --skill-dir "$skill_dir"

  [ "$status" -ne 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" = "$before_hash" ]
  [[ "$output" == *"invalid structured output"* ]]
}

@test "fenced provider output fails closed without changing AGENTS" {
  printf '%s\n' '# Keep this file' > AGENTS.md
  before_hash="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' '{"status":"auto","merged_content":"```markdown\n# Not a complete response\n```","reason":"Invalid wrapper.","conflicts":[]}'
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -ne 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" = "$before_hash" ]
  [[ "$output" == *"fenced content"* ]]
}

@test "concurrent AGENTS changes are not overwritten by a stale merge" {
  printf '%s\n' '# Original instructions' > AGENTS.md
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' '# Newer user instructions' > AGENTS.md
printf '%s\n' '{"status":"auto","merged_content":"# Model merge\n","reason":"Additive rule.","conflicts":[]}'
EOF
  chmod +x "$fake_bin/claude"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider claude --stack node --skill-dir "$skill_dir"

  [ "$status" -ne 0 ]
  [ "$(cat AGENTS.md)" = '# Newer user instructions' ]
  [[ "$output" == *"changed while merge was running"* ]]
}

@test "auto merge works with Codex structured output" {
  printf '%s\n' '# Existing project instructions' > AGENTS.md
  cat > "$fake_bin/codex" <<'EOF'
#!/bin/bash
result_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    result_file="$2"
    shift 2
  else
    shift
  fi
done
printf '%s\n' '{"status":"auto","merged_content":"# Codex merged instructions\n","reason":"No conflicts found.","conflicts":[]}' > "$result_file"
EOF
  chmod +x "$fake_bin/codex"

  PATH="$fake_bin:$PATH" run bash "$skill_dir/scripts/merge-instructions.sh" \
    --provider codex --stack node --skill-dir "$skill_dir"

  [ "$status" -eq 0 ]
  [ "$(cat AGENTS.md)" = '# Codex merged instructions' ]
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

@test "sync-instructions hook runs upgrade, projection, and merge in order" {
  source_dir="$test_root/agent-ready-setup"
  event_log="$test_root/hook-events.log"
  bootstrap_log="$test_root/hook-bootstrap.log"
  merge_log="$test_root/hook-merge.log"
  mkdir -p "$source_dir/assets/stacks" "$source_dir/scripts"
  touch "$source_dir/SKILL.md"
  cat > "$source_dir/scripts/bootstrap.sh" <<'EOF'
#!/bin/bash
printf 'bootstrap\n' >> "$EVENT_LOG"
printf '%s\n' "$*" > "$BOOTSTRAP_LOG"
EOF
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
printf 'merge\n' >> "$EVENT_LOG"
printf '%s\n' "$*" > "$MERGE_LOG"
EOF
  chmod +x "$source_dir/scripts/bootstrap.sh" "$source_dir/scripts/merge-instructions.sh"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
printf 'fury\n' >> "$EVENT_LOG"
EOF
  chmod +x "$fake_bin/fury"
  printf '%s\n' '{"dependencies":{"react":"1.0.0"}}' > package.json

  EVENT_LOG="$event_log" \
    BOOTSTRAP_LOG="$bootstrap_log" \
    MERGE_LOG="$merge_log" \
    AGENT_READY_SETUP_SKILL_DIR="$source_dir" \
    PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/stacks/frontend/hooks/sync-marketplace.sh" \
      --provider claude --merge-instructions

  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$event_log")" = "fury" ]
  [ "$(sed -n '2p' "$event_log")" = "bootstrap" ]
  [ "$(sed -n '3p' "$event_log")" = "merge" ]
  grep -Fq -- "--stack frontend --skill-dir $source_dir --sync" "$bootstrap_log"
  grep -Fq -- "--provider claude --stack frontend --skill-dir $source_dir" "$merge_log"
}

@test "sync-instructions hook preserves session when merge needs human review" {
  source_dir="$test_root/agent-ready-setup"
  mkdir -p "$source_dir/assets/stacks" "$source_dir/scripts"
  touch "$source_dir/SKILL.md"
  printf '%s\n' '#!/bin/bash' 'exit 0' > "$source_dir/scripts/bootstrap.sh"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
[[ "${AGENT_READY_SETUP_NON_INTERACTIVE:-0}" == "1" ]] || exit 99
exit 2
EOF
  chmod +x "$source_dir/scripts/bootstrap.sh" "$source_dir/scripts/merge-instructions.sh"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$fake_bin/fury"
  printf '%s\n' '{}' > package.json

  AGENT_READY_SETUP_SKILL_DIR="$source_dir" PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/stacks/frontend/hooks/sync-marketplace.sh" \
      --provider claude --sync-instructions --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"requires human review"* ]]
}
