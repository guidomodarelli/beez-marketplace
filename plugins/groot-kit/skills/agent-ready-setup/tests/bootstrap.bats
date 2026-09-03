#!/usr/bin/env bats

setup() {
  repository_root="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  skill_dir="$repository_root/plugins/groot-kit/skills/agent-ready-setup"
  test_root="$(mktemp -d)"
  project_dir="$test_root/project"
  mkdir -p "$project_dir"
  git -C "$project_dir" -c init.defaultBranch=main init -q
  cd "$project_dir"
}

teardown() {
  cd "$repository_root"
  rm -rf "$test_root"
}

run_bootstrap() {
  local stack="$1"
  shift

  run bash "$skill_dir/scripts/bootstrap.sh" \
    --stack "$stack" \
    --skill-dir "$skill_dir" \
    "$@"
}

@test "bootstrap projects Claude, shared, and Codex trees" {
  run_bootstrap frontend

  [ "$status" -eq 0 ]
  [ -f AGENTS.md ]
  [ -f CLAUDE.md ]
  cmp -s CLAUDE.md "$skill_dir/assets/root-claude.md"
  [ -f .claude/settings.json ]
  [ -L .claude/rules/security.md ]
  [ "$(readlink .claude/rules/security.md)" = "../../.agents/rules/security.md" ]
  [ -f .agents/rules/security.md ]
  [ -L .claude/skills/component-creation/SKILL.md ]
  [ "$(readlink .claude/skills/component-creation/SKILL.md)" = "../../../.agents/skills/component-creation/SKILL.md" ]
  [ -f .agents/skills/component-creation/SKILL.md ]
  [ -L .claude/agents/security-scanner.md ]
  [ -L .claude/commands/review-pr.md ]
  [ -f .agents/agents/security-scanner.md ]
  [ -f .agents/commands/review-pr.md ]
  [ -f .agents/skills/security-scanner/SKILL.md ]
  [ -f .agents/skills/review-pr/SKILL.md ]
  [ -L .claude/mcp.json ]
  [ -f .codex/.mcp.json ]
  [ -L .claude/hooks/check-harness-consistency.sh ]
  [ -f .codex/hooks/hooks.json ]
  [ ! -f .claude/CLAUDE.md ]
  [ ! -d .codex/agents ]
  grep -Fq '@.agents/rules/security.md' AGENTS.md
  grep -Fxq '## Centralización recursiva de instrucciones' AGENTS.md
  printf '\n# Canonical shared asset\n' >> .agents/rules/security.md
  grep -Fq '# Canonical shared asset' .claude/rules/security.md
  jq -n --slurpfile claude .claude/mcp.json --slurpfile codex .codex/.mcp.json \
    '$claude[0].mcpServers == $codex[0].mcpServers' >/dev/null
  jq -e '.hooks.SessionStart[0].matcher == "startup|clear|resume"' .codex/hooks/hooks.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.claude/hooks/sync-marketplace.sh --provider claude --sync-instructions)")' .claude/settings.json >/dev/null
  jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .claude/hooks/sync-marketplace.sh --provider claude --sync-instructions"' .claude/settings.json >/dev/null
  jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider codex --sync-instructions"' .codex/hooks/hooks.json >/dev/null
  [[ "$output" == *"Providers: Claude Code + Codex-compatible shared tree"* ]]
}

@test "identical legacy Claude copies become canonical symlinks" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  rm .claude/rules/security.md
  cp .agents/rules/security.md .claude/rules/security.md

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  [ -L .claude/rules/security.md ]
  [[ "$output" == *"Normalized instructions:"* ]]
  [[ "$output" == *".claude/rules/security.md -> .agents/rules/security.md"* ]]
}

@test "divergent Claude copies remain untouched and report conflict" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  rm .claude/rules/security.md
  printf '%s\n' '# Claude-only security override' > .claude/rules/security.md

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  [ ! -L .claude/rules/security.md ]
  grep -Fxq '# Claude-only security override' .claude/rules/security.md
  [[ "$output" == *"Instruction conflicts or differences (agent resolution may be required):"* ]]
  [[ "$output" == *".claude/rules/security.md differs from canonical shared asset"* ]]
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
    git -C "$stack_project" -c init.defaultBranch=main init -q
    cd "$stack_project"

    run_bootstrap "$stack"

    [ "$status" -eq 0 ]
    cmp -s CLAUDE.md "$skill_dir/assets/root-claude.md"
    for provider_root in .claude .agents; do
      skill_path="$provider_root/skills/fury-deploy/SKILL.md"
      [ -f "$skill_path" ]
      [ "$(sed -n '1p' "$skill_path")" = '---' ]
      grep -Eq '^description: .+' "$skill_path"
    done
    grep -Fq '@.agents/rules/coding-style.md' AGENTS.md
    grep -Fq '@.agents/rules/security.md' AGENTS.md
    grep -Fq '@.agents/rules/testing.md' AGENTS.md
    jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .claude/hooks/sync-marketplace.sh --provider claude --sync-instructions"' .claude/settings.json >/dev/null
    jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider codex --sync-instructions"' .codex/hooks/hooks.json >/dev/null
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
  cmp -s CLAUDE.md "$skill_dir/assets/root-claude.md"
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

@test "rejects bootstrap outside a Git worktree" {
  non_git_project="$test_root/non-git-project"
  mkdir -p "$non_git_project"
  cd "$non_git_project"

  run bash "$skill_dir/scripts/bootstrap.sh" --stack node --skill-dir "$skill_dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *"bootstrap must run inside a Git worktree"* ]]
}

@test "ignored node_modules instructions remain untouched" {
  printf '%s\n' 'node_modules/' > .gitignore
  mkdir -p node_modules/example-package
  printf '%s\n' '# Dependency instructions' > node_modules/example-package/CLAUDE.md

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ ! -e node_modules/example-package/AGENTS.md ]
  [ "$(cat node_modules/example-package/CLAUDE.md)" = '# Dependency instructions' ]
}

@test "gitignored nested instruction pairs remain untouched" {
  mkdir -p generated/api
  printf '%s\n' 'generated/' > .gitignore
  git -c init.defaultBranch=main init -q .
  printf '%s\n' '# Generated instructions' > generated/api/CLAUDE.md

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ ! -e generated/api/AGENTS.md ]
  [ "$(cat generated/api/CLAUDE.md)" = '# Generated instructions' ]
}

@test "tracked instructions under ignored directories remain normalizable" {
  mkdir -p node_modules/tracked-package
  printf '%s\n' 'node_modules/' > .gitignore
  printf '%s\n' '# Tracked instructions' > node_modules/tracked-package/CLAUDE.md
  git add -f node_modules/tracked-package/CLAUDE.md

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ -f node_modules/tracked-package/AGENTS.md ]
  [ "$(cat node_modules/tracked-package/CLAUDE.md)" = '@AGENTS.md' ]
  [ "$(cat node_modules/tracked-package/AGENTS.md)" = '# Tracked instructions' ]
}

@test "provider destinations are created when ignored by Git" {
  printf '%s\n' '.claude/' '.agents/' '.codex/' > .gitignore
  git -c init.defaultBranch=main init -q .

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ -f .claude/settings.json ]
  [ -f .agents/rules/security.md ]
  [ -f .codex/hooks/hooks.json ]
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
  [[ "$output" == *"Instruction conflicts or differences (agent resolution may be required):"* ]]
  [[ "$output" == *"agent must merge compatible instructions before normalizing"* ]]
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

@test "rejects symlinked provider subdirectories before writing assets" {
  outside_root="$test_root/outside-rules"
  mkdir -p "$outside_root" .claude
  printf '%s\n' 'sentinel' > "$outside_root/sentinel.txt"
  ln -s "$outside_root" .claude/rules

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  [ -L .claude/rules ]
  [ "$(cat "$outside_root/sentinel.txt")" = "sentinel" ]
  [ "$(find "$outside_root" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"parent directory contains symlink"* ]]
  [[ "$output" == *".claude/rules"* ]]
}

@test "harness hooks inspect Claude and shared-agent paths" {
  fake_bin="$test_root/bin"
  invocation_log="$test_root/claude-invocation.log"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf 'PWD=%s\nARGS=%s\n' "$PWD" "$*" > "$CLAUDE_INVOCATION_LOG"
EOF
  chmod +x "$fake_bin/claude"
  mkdir -p .claude .agents

  for stack in frontend node java go; do
    hook="$skill_dir/assets/stacks/$stack/hooks/check-harness-consistency.sh"
    for provider_root in .claude .agents; do
      : > "$invocation_log"
      CLAUDE_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
        bash "$hook" <<< "{\"tool_input\":{\"file_path\":\"$provider_root/rules/security.md\"}}"
      grep -Fq "PWD=$project_dir/$provider_root" "$invocation_log"
      grep -Fq "ARGS=--print Read all .md files in rules/" "$invocation_log"
      grep -Fq "all SKILL.md files in skills/*/" "$invocation_log"
    done
  done
}

@test "harness hooks keep prompt independent from payload paths" {
  fake_bin="$test_root/bin"
  invocation_log="$test_root/claude-invocation.log"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf 'PWD=%s\nARGS=%s\n' "$PWD" "$*" > "$CLAUDE_INVOCATION_LOG"
EOF
  chmod +x "$fake_bin/claude"
  mkdir -p .claude .agents

  for stack in frontend node java go; do
    hook="$skill_dir/assets/stacks/$stack/hooks/check-harness-consistency.sh"
    for provider_root in .claude .agents; do
      : > "$invocation_log"
      malicious_file_path="$provider_root/rules/security.md; echo INJECTED"
      CLAUDE_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
        bash "$hook" <<< "{\"tool_input\":{\"file_path\":\"$malicious_file_path\"}}"
      grep -Fq "PWD=$project_dir/$provider_root" "$invocation_log"
      grep -Fq 'ARGS=--print Read all .md files in rules/ and all SKILL.md files in skills/*/.' "$invocation_log"
      ! grep -Fq 'INJECTED' "$invocation_log"
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

@test "sync hooks pass marketplace provider and support legacy path detection" {
  fake_bin="$test_root/bin"
  invocation_log="$test_root/fury-invocation.log"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$FURY_INVOCATION_LOG"
EOF
  chmod +x "$fake_bin/fury"

  for stack in frontend node java go; do
    hook="$skill_dir/assets/stacks/$stack/hooks/sync-marketplace.sh"

    FURY_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
      run bash "$hook" --provider claude
    [ "$status" -eq 0 ]
    grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider claude' "$invocation_log"

    FURY_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
      run bash "$hook" -p codex
    [ "$status" -eq 0 ]
    grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider codex' "$invocation_log"

    mkdir -p .claude/hooks .agents/hooks
    cp "$hook" .claude/hooks/sync-marketplace.sh
    cp "$hook" .agents/hooks/sync-marketplace.sh

    FURY_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
      run bash .claude/hooks/sync-marketplace.sh
    [ "$status" -eq 0 ]
    grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider claude' "$invocation_log"

    FURY_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
      run bash .agents/hooks/sync-marketplace.sh
    [ "$status" -eq 0 ]
    grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider codex' "$invocation_log"

    run bash "$hook" --provider unsupported
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported marketplace provider"* ]]
  done
}

@test "sync mode shows diffs and preserves existing assets without confirmation" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  printf '%s\n' '# Local change' >> .agents/rules/security.md
  before_hash="$(shasum .agents/rules/security.md | cut -d ' ' -f 1)"

  run_bootstrap frontend --sync

  [ "$status" -eq 0 ]
  [ "$(shasum .agents/rules/security.md | cut -d ' ' -f 1)" = "$before_hash" ]
  [[ "$output" == *"Diff for .agents/rules/security.md"* ]]
  [[ "$output" == *"Pending confirmation (not overwritten):"* ]]
}

@test "sync mode updates managed assets with explicit yes and preserves root instructions" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  printf '%s\n' '# Local change' >> .agents/rules/security.md
  printf '%s\n' '# Project instructions' > AGENTS.md
  cp "$skill_dir/assets/root-claude.md" CLAUDE.md
  root_hash_before="$(shasum AGENTS.md CLAUDE.md | shasum | cut -d ' ' -f 1)"

  run_bootstrap frontend --sync --yes

  [ "$status" -eq 0 ]
  cmp -s .agents/rules/security.md "$skill_dir/assets/stacks/frontend/rules/security.md"
  [ "$(shasum AGENTS.md CLAUDE.md | shasum | cut -d ' ' -f 1)" = "$root_hash_before" ]
  [[ "$output" == *"Updated from templates:"* ]]
}

@test "update is an alias for sync and yes cannot be used without sync" {
  run_bootstrap node
  [ "$status" -eq 0 ]

  printf '%s\n' '# Local change' >> .agents/rules/security.md
  run_bootstrap node --update --yes

  [ "$status" -eq 0 ]
  cmp -s .agents/rules/security.md "$skill_dir/assets/stacks/node/rules/security.md"

  run bash "$skill_dir/scripts/bootstrap.sh" --stack node --skill-dir "$skill_dir" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"--yes requires --sync or --update"* ]]
}

@test "sync mode preserves symlinked managed assets" {
  outside_file="$test_root/outside-security.md"
  printf '%s\n' '# Outside asset' > "$outside_file"
  run_bootstrap node
  [ "$status" -eq 0 ]

  rm .agents/rules/security.md
  ln -s "$outside_file" .agents/rules/security.md

  run_bootstrap node --sync --yes

  [ "$status" -eq 0 ]
  [ -L .agents/rules/security.md ]
  [ "$(cat "$outside_file")" = '# Outside asset' ]
  [[ "$output" == *"is a symlink; neither it nor its target was changed"* ]]
}

@test "sync hooks project updated content after marketplace upgrade" {
  fake_bin="$test_root/bin"
  source_dir="$test_root/agent-ready-setup"
  event_log="$test_root/events.log"
  bootstrap_log="$test_root/bootstrap.log"
  mkdir -p "$fake_bin" "$source_dir/assets/stacks" "$source_dir/scripts"
  touch "$source_dir/SKILL.md"
  cat > "$source_dir/scripts/bootstrap.sh" <<'EOF'
#!/bin/bash
printf 'bootstrap\n' >> "$EVENT_LOG"
printf '%s\n' "$*" > "$BOOTSTRAP_INVOCATION_LOG"
EOF
  chmod +x "$source_dir/scripts/bootstrap.sh"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
printf 'fury\n' >> "$EVENT_LOG"
printf '%s\n' "$*" > "$FURY_INVOCATION_LOG"
EOF
  chmod +x "$fake_bin/fury"
  printf '%s\n' '{"dependencies":{"react":"1.0.0"}}' > package.json

  EVENT_LOG="$event_log" \
    FURY_INVOCATION_LOG="$test_root/fury.log" \
    BOOTSTRAP_INVOCATION_LOG="$bootstrap_log" \
    AGENT_READY_SETUP_SKILL_DIR="$source_dir" \
    PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/stacks/frontend/hooks/sync-marketplace.sh" \
      --provider claude --sync

  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$event_log")" = "fury" ]
  [ "$(sed -n '2p' "$event_log")" = "bootstrap" ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider claude' "$test_root/fury.log"
  grep -Fq -- "--stack frontend --skill-dir $source_dir --sync" "$bootstrap_log"
}

@test "sync hooks do not project content when marketplace upgrade fails" {
  fake_bin="$test_root/bin"
  source_dir="$test_root/agent-ready-setup"
  bootstrap_log="$test_root/bootstrap.log"
  mkdir -p "$fake_bin" "$source_dir/assets/stacks" "$source_dir/scripts"
  touch "$source_dir/SKILL.md"
  cat > "$source_dir/scripts/bootstrap.sh" <<'EOF'
#!/bin/bash
printf '%s\n' called > "$BOOTSTRAP_INVOCATION_LOG"
EOF
  chmod +x "$source_dir/scripts/bootstrap.sh"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
exit 42
EOF
  chmod +x "$fake_bin/fury"

  FURY_INVOCATION_LOG="$test_root/fury.log" \
    BOOTSTRAP_INVOCATION_LOG="$bootstrap_log" \
    AGENT_READY_SETUP_SKILL_DIR="$source_dir" \
    PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/stacks/frontend/hooks/sync-marketplace.sh" \
      --provider claude --sync

  [ "$status" -ne 0 ]
  [ ! -e "$bootstrap_log" ]
}

@test "all stack sync hooks remain byte-identical" {
  for stack in frontend node java go; do
    cmp -s \
      "$skill_dir/assets/stacks/frontend/hooks/sync-marketplace.sh" \
      "$skill_dir/assets/stacks/$stack/hooks/sync-marketplace.sh"
  done
}
