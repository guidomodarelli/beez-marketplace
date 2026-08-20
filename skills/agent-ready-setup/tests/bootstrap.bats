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
  grep -Fxq '@AGENTS.md' CLAUDE.md
  grep -Fxq '## Regla de centralización de instrucciones' CLAUDE.md
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
  grep -Fxq '## Centralización recursiva de instrucciones' AGENTS.md
  jq -n --slurpfile claude .claude/mcp.json --slurpfile codex .codex/.mcp.json \
    '$claude[0].mcpServers == $codex[0].mcpServers' >/dev/null
  jq -e '.hooks.SessionStart[0].matcher == "startup|clear|resume"' .codex/hooks/hooks.json >/dev/null
  [[ "$output" == *"Providers: Claude Code + Codex-compatible shared tree"* ]]
}

@test "nested skills receive valid Codex adapters with their directory names" {
  run_bootstrap frontend

  [ "$status" -eq 0 ]
  for skill_name in api-endpoint component-creation karpathy-guidelines logger service; do
    skill_path=".agents/skills/$skill_name/SKILL.md"
    [ -f "$skill_path" ]
    [ "$(sed -n '1p' "$skill_path")" = '---' ]
    grep -Fxq "name: $skill_name" <(sed -n '2p' "$skill_path")
    [ "$(sed -n '4p' "$skill_path")" = '---' ]
  done
  [ -f .agents/skills/karpathy-guidelines/EXAMPLES.md ]
  [ ! -e .agents/skills/SKILL/SKILL.md ]
  [ ! -e .agents/skills/EXAMPLES/SKILL.md ]
}

@test "flat deploy templates become discoverable skills for Claude and shared agents" {
  for stack in go java node; do
    stack_project="$test_root/$stack-project"
    mkdir -p "$stack_project"
    cd "$stack_project"

    run_bootstrap "$stack"

    [ "$status" -eq 0 ]
    for provider_root in .claude .agents; do
      skill_path="$provider_root/skills/fury-deploy/SKILL.md"
      [ -f "$skill_path" ]
      [ "$(sed -n '1p' "$skill_path")" = '---' ]
      grep -Eq '^description: .+' "$skill_path"
    done
    grep -Fq '@.agents/rules/coding-style.md' AGENTS.md
    grep -Fq '@.agents/rules/security.md' AGENTS.md
    grep -Fq '@.agents/rules/testing.md' AGENTS.md
  done
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
  grep -Fq '# Existing project instructions' AGENTS.md
  grep -Fq 'Run the project test command before merging.' AGENTS.md
  grep -Fxq '## Centralización recursiva de instrucciones' AGENTS.md
  grep -Fxq '@AGENTS.md' CLAUDE.md
  grep -Fxq '## Regla de centralización de instrucciones' CLAUDE.md
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
  grep -Fq '# Canonical instructions' AGENTS.md
  grep -Fq 'Keep changes backwards compatible.' AGENTS.md
  grep -Fxq '## Centralización recursiva de instrucciones' AGENTS.md
  grep -Fxq '@AGENTS.md' CLAUDE.md
  grep -Fxq '## Regla de centralización de instrucciones' CLAUDE.md
}

@test "normalized root CLAUDE proxy with centralization rule is preserved" {
  cat > AGENTS.md <<'EOF'
# Canonical instructions
EOF
  cp "$skill_dir/assets/root-claude.md" CLAUDE.md
  claude_hash_before="$(shasum CLAUDE.md | cut -d ' ' -f 1)"

  run_bootstrap java

  [ "$status" -eq 0 ]
  [ "$(shasum CLAUDE.md | cut -d ' ' -f 1)" = "$claude_hash_before" ]
  grep -Fq '# Canonical instructions' AGENTS.md
  grep -Fq '## Centralización recursiva de instrucciones' AGENTS.md
}

@test "orphaned normalized root CLAUDE proxy recreates canonical AGENTS" {
  cp "$skill_dir/assets/root-claude.md" CLAUDE.md

  run_bootstrap java

  [ "$status" -eq 0 ]
  [ -f AGENTS.md ]
  grep -Fq '# [Project Name]' AGENTS.md
  grep -Fxq '## Centralización recursiva de instrucciones' AGENTS.md
  grep -Fxq '@AGENTS.md' CLAUDE.md
  grep -Fxq '## Regla de centralización de instrucciones' CLAUDE.md
}

@test "nested instruction pairs normalize recursively" {
  mkdir -p service packages/api
  cat > service/CLAUDE.md <<'EOF'
# Service instructions

Run service checks before merging.
EOF
  cat > packages/api/AGENTS.md <<'EOF'
# API instructions

Keep API changes backwards compatible.
EOF

  run_bootstrap node

  [ "$status" -eq 0 ]
  grep -Fq '# Service instructions' service/AGENTS.md
  grep -Fq 'Run service checks before merging.' service/AGENTS.md
  [ "$(cat service/CLAUDE.md)" = '@AGENTS.md' ]
  [ "$(cat packages/api/CLAUDE.md)" = '@AGENTS.md' ]
  grep -Fq '# API instructions' packages/api/AGENTS.md
  grep -Fq 'Keep API changes backwards compatible.' packages/api/AGENTS.md
}

@test "identical instruction files collapse to canonical AGENTS" {
  cat > AGENTS.md <<'EOF'
# Shared instructions

Run checks before merging.
EOF
  cp AGENTS.md CLAUDE.md

  run_bootstrap java

  [ "$status" -eq 0 ]
  grep -Fq '# Shared instructions' AGENTS.md
  grep -Fq 'Run checks before merging.' AGENTS.md
  grep -Fxq '@AGENTS.md' CLAUDE.md
  grep -Fxq '## Regla de centralización de instrucciones' CLAUDE.md
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

@test "rejects symlinked provider roots before writing assets" {
  for provider_root in .claude .agents .codex; do
    outside_root="$test_root/$provider_root"
    mkdir -p "$outside_root"
    ln -s "$outside_root" "$provider_root"

    run_bootstrap frontend

    [ "$status" -ne 0 ]
    [[ "$output" == *"Provider root conflicts (manual resolution required):"* ]]
    [ -z "$(find "$outside_root" -mindepth 1 -print -quit)" ]
    [ -L "$provider_root" ]

    rm "$provider_root"
  done
}

@test "harness hooks inspect Claude and shared-agent paths" {
  fake_bin="$test_root/bin"
  invocation_log="$test_root/claude-invocation.log"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$CLAUDE_INVOCATION_LOG"
EOF
  chmod +x "$fake_bin/claude"

  for stack in frontend node java go; do
    hook="$skill_dir/assets/stacks/$stack/hooks/check-harness-consistency.sh"
    for provider_root in .claude .agents; do
      : > "$invocation_log"
      CLAUDE_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
        bash "$hook" <<< "{\"tool_input\":{\"file_path\":\"$provider_root/rules/security.md\"}}"
      grep -Fq "Read all .md files in $provider_root/rules/" "$invocation_log"
      grep -Fq "all SKILL.md files in $provider_root/skills/*/" "$invocation_log"
    done
  done
}

@test "harness hooks ignore unrelated paths" {
  fake_bin="$test_root/bin"
  invocation_log="$test_root/claude-invocation.log"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$CLAUDE_INVOCATION_LOG"
EOF
  chmod +x "$fake_bin/claude"

  CLAUDE_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
    bash "$skill_dir/assets/stacks/frontend/hooks/check-harness-consistency.sh" \
    <<< '{"tool_input":{"file_path":"README.md"}}'
  [ ! -e "$invocation_log" ]
}

@test "rejects unsupported stack and missing arguments" {
  run bash "$skill_dir/scripts/bootstrap.sh" --stack rust --skill-dir "$skill_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported stack"* ]]

  run bash "$skill_dir/scripts/bootstrap.sh" --stack frontend
  [ "$status" -ne 0 ]
  [[ "$output" == *"--stack and --skill-dir are required"* ]]
}
