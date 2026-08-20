#!/usr/bin/env bats

setup() {
  repository_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  skill_dir="$repository_root/skills/agent-ready-setup"
  test_root="$(mktemp -d)"
  project_dir="$test_root/project"
  mkdir -p "$project_dir"
  cd "$project_dir"
}

teardown() {
  cd "$repository_root"
  rm -rf "$test_root"
}

run_bootstrap() {
  run bash "$skill_dir/scripts/bootstrap.sh" \
    --stack "$1" \
    --skill-dir "$skill_dir"
}

@test "bootstrap projects Claude, shared, and Codex trees" {
  run_bootstrap frontend

  [ "$status" -eq 0 ]
  [ -f AGENTS.md ]
  [ -f CLAUDE.md ]
  [ "$(cat CLAUDE.md)" = "@AGENTS.md" ]
  [ -f .claude/settings.json ]
  [ -f .claude/rules/security.md ]
  [ -f .agents/rules/security.md ]
  [ -f .agents/skills/component-creation/SKILL.md ]
  [ -f .agents/agents/security-scanner.md ]
  [ -f .agents/commands/review-pr.md ]
  [ -f .agents/skills/security-scanner/SKILL.md ]
  [ -f .agents/skills/review-pr/SKILL.md ]
  [ -f .codex/.mcp.json ]
  [ -f .codex/hooks/hooks.json ]
  [ ! -f .claude/CLAUDE.md ]
  [ ! -d .codex/agents ]
  grep -Fq '@.agents/rules/security.md' AGENTS.md
  jq -n --slurpfile claude .claude/mcp.json --slurpfile codex .codex/.mcp.json \
    '$claude[0].mcpServers == $codex[0].mcpServers' >/dev/null
  jq -e '.hooks.SessionStart[0].matcher == "startup|clear|resume"' .codex/hooks/hooks.json >/dev/null
  [[ "$output" == *"Providers: Claude Code + Codex-compatible shared tree"* ]]
}

@test "second bootstrap is idempotent and preserves generated files" {
  run_bootstrap node
  [ "$status" -eq 0 ]
  [ -f .agents/skills/fury-deploy/SKILL.md ]

  agents_hash_before="$(shasum AGENTS.md | cut -d ' ' -f 1)"
  claude_hash_before="$(shasum CLAUDE.md | cut -d ' ' -f 1)"
  codex_mcp_hash_before="$(shasum .codex/.mcp.json | cut -d ' ' -f 1)"

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ "$(shasum AGENTS.md | cut -d ' ' -f 1)" = "$agents_hash_before" ]
  [ "$(shasum CLAUDE.md | cut -d ' ' -f 1)" = "$claude_hash_before" ]
  [ "$(shasum .codex/.mcp.json | cut -d ' ' -f 1)" = "$codex_mcp_hash_before" ]
  [[ "$output" == *"Already existed (skipped):"* ]]
}

@test "existing CLAUDE instructions migrate to AGENTS and become proxy" {
  cat > CLAUDE.md <<'EOF'
# Existing project instructions

Run the project test command before merging.
EOF

  run_bootstrap go

  [ "$status" -eq 0 ]
  [ "$(cat AGENTS.md)" = $'# Existing project instructions\n\nRun the project test command before merging.' ]
  [ "$(cat CLAUDE.md)" = "@AGENTS.md" ]
  [[ "$output" == *"Normalized instructions:"* ]]
}

@test "proxy CLAUDE leaves existing AGENTS unchanged" {
  cat > AGENTS.md <<'EOF'
# Canonical instructions

Keep changes backwards compatible.
EOF
  printf '%s\n' '@AGENTS.md' > CLAUDE.md

  run_bootstrap java

  [ "$status" -eq 0 ]
  [ "$(cat AGENTS.md)" = $'# Canonical instructions\n\nKeep changes backwards compatible.' ]
  [ "$(cat CLAUDE.md)" = "@AGENTS.md" ]
}

@test "identical instruction files collapse to canonical AGENTS" {
  cat > AGENTS.md <<'EOF'
# Shared instructions

Run checks before merging.
EOF
  cp AGENTS.md CLAUDE.md

  run_bootstrap java

  [ "$status" -eq 0 ]
  [ "$(cat AGENTS.md)" = $'# Shared instructions\n\nRun checks before merging.' ]
  [ "$(cat CLAUDE.md)" = "@AGENTS.md" ]
  [[ "$output" == *"Normalized instructions:"* ]]
}

@test "different instruction files report conflict without overwriting" {
  cat > AGENTS.md <<'EOF'
# Canonical instructions
EOF
  cat > CLAUDE.md <<'EOF'
# Claude-only instructions
EOF

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ "$(cat AGENTS.md)" = "# Canonical instructions" ]
  [ "$(cat CLAUDE.md)" = "# Claude-only instructions" ]
  [[ "$output" == *"Instruction conflicts (manual resolution required):"* ]]
}

@test "rejects unsupported stack and missing arguments" {
  run bash "$skill_dir/scripts/bootstrap.sh" --stack rust --skill-dir "$skill_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported stack"* ]]

  run bash "$skill_dir/scripts/bootstrap.sh" --stack frontend
  [ "$status" -ne 0 ]
  [[ "$output" == *"--stack and --skill-dir are required"* ]]
}
