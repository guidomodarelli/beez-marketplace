#!/usr/bin/env bats

setup() {
  repository_root="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  skill_dir="$repository_root/plugins/groot-kit/skills/agent-ready-setup"
  test_root="$(mktemp -d)"
  project_dir="$test_root/project"
  fake_bin="$test_root/bin"
  mkdir -p "$project_dir" "$fake_bin"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$fake_bin/fury"
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

  run env PATH="$test_root/bin:$PATH" bash "$skill_dir/scripts/bootstrap.sh" \
    --stack "$stack" \
    --skill-dir "$skill_dir" \
    --provider claude \
    "$@"
}

run_marketplace_sync() {
  local hook_path="$1"
  local source_skill_dir="$2"
  shift 2

  run env \
    PATH="$test_root/bin:$PATH" \
    AGENT_READY_SETUP_SKILL_DIR="$source_skill_dir" \
    bash "$hook_path" \
    --provider claude \
    --stack frontend \
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
  [ ! -e .claude/hooks ]
  [ ! -L .claude/hooks ]
  [ -f .agents/hooks/sync-marketplace.sh ]
  [ -f .agents/hooks/check-harness-consistency.sh ]
  [ -f .agents/hooks/pre-tool-use.md ]
  [ -f .codex/hooks/hooks.json ]
  cmp -s .agents/hooks/sync-marketplace.sh "$skill_dir/assets/common/hooks/sync-marketplace.sh"
  cmp -s .codex/hooks/hooks.json "$skill_dir/assets/codex/hooks.json"
  for hook_file in check-harness-consistency.sh pre-tool-use.md; do
    cmp -s ".agents/hooks/$hook_file" "$skill_dir/assets/stacks/frontend/hooks/$hook_file"
  done
  [ ! -f .claude/CLAUDE.md ]
  [ ! -d .codex/agents ]
  for rule_file in frontend-style.md no-unnecessary-mocks.md security.md testing.md; do
    grep -Fq -- "- Read and follow \`.agents/rules/$rule_file\`." AGENTS.md
  done
  grep -Fxq '## Centralización recursiva de instrucciones' AGENTS.md
  printf '\n# Canonical shared asset\n' >> .agents/rules/security.md
  grep -Fq '# Canonical shared asset' .claude/rules/security.md
  jq -n --slurpfile claude .claude/mcp.json --slurpfile codex .codex/.mcp.json \
    '$claude[0].mcpServers == $codex[0].mcpServers' >/dev/null
  jq -e '.hooks.SessionStart[0].matcher == "startup|clear|resume"' .codex/hooks/hooks.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes)")' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/check-harness-consistency.sh)")' .claude/settings.json >/dev/null
  jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes"' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks[0].command == "bash .agents/hooks/check-harness-consistency.sh"' .claude/settings.json >/dev/null
  jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider codex --sync-instructions --yes"' .codex/hooks/hooks.json >/dev/null
  [[ "$output" == *"Providers: Claude Code + Codex-compatible shared tree"* ]]
}

@test "sync removes managed legacy hooks and stale Claude symlink views" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  mkdir -p .claude/hooks .claude/rules
  ln -s ../../.agents/hooks/sync-marketplace.sh .claude/hooks/sync-marketplace.sh
  ln -s ../../.agents/hooks/check-harness-consistency.sh .claude/hooks/check-harness-consistency.sh
  ln -s ../../.agents/hooks/pre-tool-use.md .claude/hooks/pre-tool-use.md
  ln -s ../../.agents/rules/removed-rule.md .claude/rules/removed-rule.md

  run_bootstrap frontend --sync --yes

  [ "$status" -eq 0 ]
  [ ! -e .claude/hooks ]
  [ ! -L .claude/hooks ]
  [ ! -e .claude/rules/removed-rule.md ]
  [[ "$output" == *"Removed stale managed assets:"* ]]
}

@test "sync preserves custom Claude hooks and migrates custom settings" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  outside_file="$test_root/custom-hook.sh"
  printf '%s\n' '#!/bin/bash' > "$outside_file"
  mkdir -p .claude/hooks
  printf '%s\n' '# Custom hook' > .claude/hooks/custom.sh
  printf '%s\n' '# Hidden custom hook' > .claude/hooks/.custom-hook
  ln -s "$outside_file" .claude/hooks/custom-link.sh
  jq '.customSetting = "preserve-me" | .permissions.allow |= map(gsub("\\.agents/hooks/"; ".claude/hooks/")) | .permissions.allow += ["Bash(custom-project-command)"] | .hooks.SessionStart[0].hooks[0].command |= gsub("\\.agents/hooks/"; ".claude/hooks/") | .hooks.PostToolUse[0].hooks[0].command |= gsub("\\.agents/hooks/"; ".claude/hooks/") | .hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"}]' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  run_bootstrap frontend --sync --yes

  [ "$status" -eq 0 ]
  [ -f .claude/hooks/custom.sh ]
  [ -f .claude/hooks/.custom-hook ]
  [ -L .claude/hooks/custom-link.sh ]
  jq -e '.customSetting == "preserve-me"' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(custom-project-command)")' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks | index({"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"})' .claude/settings.json >/dev/null
  ! grep -Fq '.claude/hooks/' .claude/settings.json
  [[ "$output" == *"Managed asset cleanup conflicts (preserved):"* ]]
  [[ "$output" == *".claude/hooks/custom.sh is custom content; preserved"* ]]
  [[ "$output" == *".claude/hooks/.custom-hook is custom content; preserved"* ]]
  [[ "$output" == *".claude/hooks/custom-link.sh is a custom symlink; preserved"* ]]
}

@test "sync preserves custom settings array entries without other custom keys" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  jq '.permissions.allow += ["Bash(custom-project-command)"] | .hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"}]' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  run_bootstrap frontend --sync --yes

  [ "$status" -eq 0 ]
  jq -e '.permissions.allow | index("Bash(custom-project-command)")' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks | index({"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"})' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes)")' .claude/settings.json >/dev/null
}

@test "sync preserves custom settings array entries inserted before managed entries" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  jq '
    .permissions.allow = ["Bash(custom-before-managed)"] + .permissions.allow
    | .hooks.PostToolUse[0].hooks = [{"type":"command","command":"bash .agents/hooks/custom-before-managed.sh"}] + .hooks.PostToolUse[0].hooks
  ' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  run_bootstrap frontend --sync --yes

  [ "$status" -eq 0 ]
  jq -e '.permissions.allow[0] == "Bash(custom-before-managed)"' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes)")' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks[0] == {"type":"command","command":"bash .agents/hooks/custom-before-managed.sh"}' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks | index({"type":"command","command":"bash .agents/hooks/check-harness-consistency.sh"})' .claude/settings.json >/dev/null
}

@test "autonomous sync merges custom Claude settings before instruction merge" {
  dynamic_skill_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$dynamic_skill_dir"

  run_marketplace_sync "$skill_dir/assets/common/hooks/sync-marketplace.sh" "$dynamic_skill_dir" \
    --sync-instructions --yes

  [ "$status" -eq 0 ]
  [ -f .claude/settings.json ]

  jq '
    .customSetting = "preserve-me"
    | .permissions.allow = ["Bash(custom-before-managed)"] + .permissions.allow
    | .hooks.PostToolUse[0].hooks = [{"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"}] + .hooks.PostToolUse[0].hooks
  ' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  jq '.newManagedSetting = "new-value"' \
    "$dynamic_skill_dir/assets/common/settings.json" > "$test_root/template.json"
  mv "$test_root/template.json" "$dynamic_skill_dir/assets/common/settings.json"

  run_marketplace_sync ".agents/hooks/sync-marketplace.sh" "$dynamic_skill_dir" \
    --sync-instructions --yes

  [ "$status" -eq 0 ]
  jq -e '.customSetting == "preserve-me"' .claude/settings.json >/dev/null
  jq -e '.newManagedSetting == "new-value"' .claude/settings.json >/dev/null
  jq -e '.permissions.allow[0] == "Bash(custom-before-managed)"' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes)")' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks[0] == {"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"}' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks | index({"type":"command","command":"bash .agents/hooks/check-harness-consistency.sh"})' .claude/settings.json >/dev/null
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
    grep -Fq -- '- Read and follow `.agents/rules/coding-style.md`.' AGENTS.md
    grep -Fq -- '- Read and follow `.agents/rules/security.md`.' AGENTS.md
    grep -Fq -- '- Read and follow `.agents/rules/testing.md`.' AGENTS.md
    cmp -s .claude/settings.json "$skill_dir/assets/common/settings.json"
    cmp -s .agents/hooks/sync-marketplace.sh "$skill_dir/assets/common/hooks/sync-marketplace.sh"
    cmp -s .codex/hooks/hooks.json "$skill_dir/assets/codex/hooks.json"
    for hook_file in check-harness-consistency.sh pre-tool-use.md; do
      cmp -s ".agents/hooks/$hook_file" "$skill_dir/assets/stacks/$stack/hooks/$hook_file"
    done
    jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes"' .claude/settings.json >/dev/null
    jq -e '.hooks.PostToolUse[0].hooks[0].command == "bash .agents/hooks/check-harness-consistency.sh"' .claude/settings.json >/dev/null
    jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider codex --sync-instructions --yes"' .codex/hooks/hooks.json >/dev/null
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

  run bash "$skill_dir/scripts/bootstrap.sh" --stack node --skill-dir "$skill_dir" --provider claude

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
  run bash "$skill_dir/scripts/bootstrap.sh" --stack rust --skill-dir "$skill_dir" --provider claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported stack"* ]]

  run bash "$skill_dir/scripts/bootstrap.sh" --stack frontend
  [ "$status" -ne 0 ]
  [[ "$output" == *"--stack and --skill-dir are required"* ]]
}

@test "bootstrap infers Codex from installed skill path without provider override" {
  codex_home="$test_root/codex-home"
  codex_skill_dir="$codex_home/.codex/skills/agent-ready-setup"
  invocation_log="$test_root/codex-fury-invocation.log"
  mkdir -p "$codex_skill_dir"
  cp -R "$skill_dir/." "$codex_skill_dir/"
  cat > "$test_root/bin/fury" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$FURY_INVOCATION_LOG"
EOF
  chmod +x "$test_root/bin/fury"

  FURY_INVOCATION_LOG="$invocation_log" \
    run env -u AGENT_READY_SETUP_ACTIVE_PROVIDER \
      HOME="$codex_home" PATH="$test_root/bin:$PATH" \
      bash "$codex_skill_dir/scripts/bootstrap.sh" \
      --stack node --skill-dir "$codex_skill_dir"

  [ "$status" -eq 0 ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider codex' "$invocation_log"
  [ -f .codex/hooks/hooks.json ]
}

@test "bootstrap rejects ambiguous skill path without provider override" {
  run env -u AGENT_READY_SETUP_ACTIVE_PROVIDER PATH="$test_root/bin:$PATH" \
    bash "$skill_dir/scripts/bootstrap.sh" \
    --stack node --skill-dir "$skill_dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *"could not infer provider from skill directory"* ]]
  [ ! -e AGENTS.md ]
}

@test "bootstrap upgrades marketplace before projecting all provider trees" {
  invocation_log="$test_root/fury-invocation.log"
  cat > "$test_root/bin/fury" <<'EOF'
#!/bin/bash
if [[ -e AGENTS.md || -e CLAUDE.md || -e .claude || -e .agents || -e .codex ]]; then
  exit 43
fi
printf '%s\n' "$*" > "$FURY_INVOCATION_LOG"
EOF
  chmod +x "$test_root/bin/fury"

  FURY_INVOCATION_LOG="$invocation_log" run_bootstrap frontend

  [ "$status" -eq 0 ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider claude' "$invocation_log"
  [ -f AGENTS.md ]
  [ -f .agents/hooks/sync-marketplace.sh ]
  [ -f .claude/settings.json ]
  [ -f .codex/hooks/hooks.json ]
  [[ "$output" == *"[marketplace-bootstrap] Marketplace upgrade completed."* ]]
}

@test "bootstrap upgrades marketplace for Codex when provider is explicit" {
  invocation_log="$test_root/fury-invocation.log"
  cat > "$test_root/bin/fury" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$FURY_INVOCATION_LOG"
EOF
  chmod +x "$test_root/bin/fury"

  FURY_INVOCATION_LOG="$invocation_log" \
    run env PATH="$test_root/bin:$PATH" bash "$skill_dir/scripts/bootstrap.sh" \
      --stack node --skill-dir "$skill_dir" --provider codex

  [ "$status" -eq 0 ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider codex' "$invocation_log"
  [ -f .agents/skills/fury-deploy/SKILL.md ]
  [ -f .claude/settings.json ]
  [ -f .codex/hooks/hooks.json ]
}

@test "bootstrap stops before projection when marketplace upgrade fails" {
  cat > "$test_root/bin/fury" <<'EOF'
#!/bin/bash
exit 42
EOF
  chmod +x "$test_root/bin/fury"

  run_bootstrap node

  [ "$status" -ne 0 ]
  [ ! -e AGENTS.md ]
  [ ! -e CLAUDE.md ]
  [ ! -e .claude ]
  [ ! -e .agents ]
  [ ! -e .codex ]
  [[ "$output" == *"marketplace upgrade failed"* ]]
  [ -z "$(find .agents -type f -print -quit 2>/dev/null)" ]
}

@test "common sync hook passes provider and infers Codex from canonical path" {
  fake_bin="$test_root/bin"
  invocation_log="$test_root/fury-invocation.log"
  hook="$skill_dir/assets/common/hooks/sync-marketplace.sh"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$FURY_INVOCATION_LOG"
EOF
  chmod +x "$fake_bin/fury"

  FURY_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
    run bash "$hook" --provider claude
  [ "$status" -eq 0 ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider claude' "$invocation_log"

  FURY_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
    run bash "$hook" -p codex
  [ "$status" -eq 0 ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider codex' "$invocation_log"

  mkdir -p .agents/hooks
  cp "$hook" .agents/hooks/sync-marketplace.sh

  FURY_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
    run bash .agents/hooks/sync-marketplace.sh
  [ "$status" -eq 0 ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider codex' "$invocation_log"

  run bash "$hook" --provider unsupported
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported marketplace provider"* ]]

  run env -u AGENT_READY_SETUP_SKILL_DIR \
    FURY_INVOCATION_LOG="$invocation_log" PATH="$fake_bin:$PATH" \
    bash "$hook" --provider claude --sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not detect project stack"* ]]
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

@test "sync updates managed provider assets without legacy Claude hooks" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]
  [ ! -e .claude/hooks ]

  source_dir="$test_root/updated-agent-ready"
  cp -R "$skill_dir"/. "$source_dir"/
  jq '.hooks.SessionStart[0].matcher = "changed"' \
    "$source_dir/assets/common/settings.json" > "$test_root/settings.json"
  mv "$test_root/settings.json" "$source_dir/assets/common/settings.json"
  printf '%s\n' '# updated common hook' >> "$source_dir/assets/common/hooks/sync-marketplace.sh"
  jq '.hooks.SessionStart[0].hooks[0].command = "bash .agents/hooks/updated-sync.sh"' \
    "$source_dir/assets/codex/hooks.json" > "$test_root/hooks.json"
  mv "$test_root/hooks.json" "$source_dir/assets/codex/hooks.json"

  run env \
    AGENT_READY_SETUP_SKILL_DIR="$source_dir" \
    PATH="$test_root/bin:$PATH" \
    bash "$source_dir/scripts/bootstrap.sh" \
      --stack frontend \
      --skill-dir "$source_dir" \
      --provider claude \
      --sync \
      --yes

  [ "$status" -eq 0 ]
  cmp -s .agents/hooks/sync-marketplace.sh "$source_dir/assets/common/hooks/sync-marketplace.sh"
  cmp -s .claude/settings.json "$source_dir/assets/common/settings.json"
  cmp -s .codex/hooks/hooks.json "$source_dir/assets/codex/hooks.json"
}

@test "sync mode detects managed destination changes before atomic rename" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  printf '%s\n' '# Local change' >> .agents/rules/security.md
  fake_bin="$test_root/bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/cp" <<'EOF'
#!/bin/bash
/bin/cp "$@"
for argument in "$@"; do
  if [[ "$argument" == *agent-ready-sync.* ]]; then
    printf '%s\n' '# Newer destination change' > .agents/rules/security.md
    break
  fi
done
EOF
  chmod +x "$fake_bin/cp"

  run env PATH="$fake_bin:$PATH" bash "$skill_dir/scripts/bootstrap.sh" \
    --stack frontend --skill-dir "$skill_dir" --provider claude --sync --yes

  [ "$status" -eq 0 ]
  [ "$(cat .agents/rules/security.md)" = '# Newer destination change' ]
  [[ "$output" == *".agents/rules/security.md changed after confirmation; neither was changed"* ]]
}

@test "update is an alias for sync and yes cannot be used without sync" {
  run_bootstrap node
  [ "$status" -eq 0 ]

  printf '%s\n' '# Local change' >> .agents/rules/security.md
  run_bootstrap node --update --yes

  [ "$status" -eq 0 ]
  cmp -s .agents/rules/security.md "$skill_dir/assets/stacks/node/rules/security.md"

  run bash "$skill_dir/scripts/bootstrap.sh" --stack node --skill-dir "$skill_dir" --provider claude --yes
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

@test "bootstrap re-resolves replaced versioned marketplace cache after upgrade" {
  fake_bin="$test_root/bin"
  cache_root="$test_root/.claude/plugins/cache/groot-marketplace/groot-kit"
  old_source="$cache_root/1.0.0/skills/agent-ready-setup"
  updated_source="$cache_root/2.0.0/skills/agent-ready-setup"
  mkdir -p "$old_source" "$updated_source"
  cp -R "$skill_dir"/. "$old_source"/
  cp -R "$skill_dir"/. "$updated_source"/
  printf '%s\n' '# Updated marketplace template' >> "$updated_source/assets/stacks/node/rules/security.md"
  cat > "$fake_bin/fury" <<EOF
#!/bin/bash
rm -rf "$old_source"
EOF
  chmod +x "$fake_bin/fury"

  run env HOME="$test_root" PATH="$fake_bin:$PATH" bash "$old_source/scripts/bootstrap.sh" \
    --stack node \
    --skill-dir "$old_source" \
    --provider claude

  [ "$status" -eq 0 ]
  [ ! -e "$old_source" ]
  grep -Fq '# Updated marketplace template' .agents/rules/security.md
}

@test "sync hook preserves custom Claude array entries with equal length" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  jq '.permissions.allow[0] = "Bash(custom-command)"' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  AGENT_READY_SETUP_SKILL_DIR="$skill_dir" PATH="$test_root/bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack frontend --sync-instructions --yes

  [ "$status" -eq 0 ]
  jq -e '.permissions.allow | length == 3' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(custom-command)") != null' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes)") != null' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/check-harness-consistency.sh)") != null' .claude/settings.json >/dev/null
}

@test "sync hook projects managed assets without bootstrap" {
  fake_bin="$test_root/bin"
  source_dir="$test_root/agent-ready-setup"
  event_log="$test_root/events.log"
  bootstrap_log="$test_root/bootstrap.log"
  mkdir -p \
    "$fake_bin" \
    "$source_dir/assets/common/hooks" \
    "$source_dir/assets/codex" \
    "$source_dir/assets/stacks/go/hooks" \
    "$source_dir/assets/stacks/go/rules" \
    "$source_dir/assets/stacks/go/agents" \
    "$source_dir/assets/stacks/go/commands" \
    "$source_dir/assets/stacks/go/skills/fury-deploy" \
    "$source_dir/scripts" \
    .agents/rules
  touch "$source_dir/SKILL.md"
  printf '%s\n' '# updated common sync hook' > "$source_dir/assets/common/hooks/sync-marketplace.sh"
  printf '%s\n' '{"settings":"updated"}' > "$source_dir/assets/common/settings.json"
  printf '%s\n' '{"hooks":"updated"}' > "$source_dir/assets/codex/hooks.json"
  printf '%s\n' '#!/bin/bash' > "$source_dir/assets/stacks/go/hooks/check-harness-consistency.sh"
  printf '%s\n' '# updated pre-tool hook' > "$source_dir/assets/stacks/go/hooks/pre-tool-use.md"
  printf '%s\n' '# updated coding style' > "$source_dir/assets/stacks/go/rules/coding-style.md"
  printf '%s\n' '# security scanner' > "$source_dir/assets/stacks/go/agents/security-scanner.md"
  printf '%s\n' '# review command' > "$source_dir/assets/stacks/go/commands/review-pr.md"
  cat > "$source_dir/assets/stacks/go/skills/fury-deploy/SKILL.md" <<'EOF'
---
name: fury-deploy
description: Deploy Fury applications.
---

# Fury deploy
EOF
  printf '%s\n' '{"mcp":"updated"}' > "$source_dir/assets/stacks/go/mcp.json"
  printf '%s\n' '# previous coding style' > .agents/rules/coding-style.md
  cat > "$source_dir/scripts/bootstrap.sh" <<'EOF'
#!/bin/bash
printf 'bootstrap\n' >> "$EVENT_LOG"
printf '%s\n' "$*" > "$BOOTSTRAP_INVOCATION_LOG"
EOF
  chmod +x "$source_dir/scripts/bootstrap.sh"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
[[ -f .agents/rules/coding-style.md ]] || exit 42
[[ -f .agents/agents/security-scanner.md ]] || exit 42
[[ -f .agents/commands/review-pr.md ]] || exit 42
[[ -f .agents/skills/fury-deploy/SKILL.md ]] || exit 42
[[ -f .codex/.mcp.json ]] || exit 42
printf 'merge\n' >> "$EVENT_LOG"
EOF
  chmod +x "$source_dir/scripts/merge-instructions.sh"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
printf 'fury\n' >> "$EVENT_LOG"
printf '%s\n' "$*" > "$FURY_INVOCATION_LOG"
EOF
  chmod +x "$fake_bin/fury"
  EVENT_LOG="$event_log" \
    FURY_INVOCATION_LOG="$test_root/fury.log" \
    BOOTSTRAP_INVOCATION_LOG="$bootstrap_log" \
    AGENT_READY_SETUP_SKILL_DIR="$source_dir" \
    PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack go --sync-instructions --yes

  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$event_log")" = "fury" ]
  [ "$(sed -n '2p' "$event_log")" = "merge" ]
  [ "$(wc -l < "$event_log")" -eq 2 ]
  [ ! -e "$bootstrap_log" ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider claude' "$test_root/fury.log"
  cmp -s .agents/hooks/sync-marketplace.sh "$source_dir/assets/common/hooks/sync-marketplace.sh"
  cmp -s .agents/hooks/check-harness-consistency.sh "$source_dir/assets/stacks/go/hooks/check-harness-consistency.sh"
  cmp -s .agents/hooks/pre-tool-use.md "$source_dir/assets/stacks/go/hooks/pre-tool-use.md"
  cmp -s .agents/rules/coding-style.md "$source_dir/assets/stacks/go/rules/coding-style.md"
  cmp -s .agents/agents/security-scanner.md "$source_dir/assets/stacks/go/agents/security-scanner.md"
  cmp -s .agents/commands/review-pr.md "$source_dir/assets/stacks/go/commands/review-pr.md"
  grep -Fq '# Fury deploy' .agents/skills/fury-deploy/SKILL.md
  cmp -s .agents/mcp.json "$source_dir/assets/stacks/go/mcp.json"
  cmp -s .claude/settings.json "$source_dir/assets/common/settings.json"
  cmp -s .codex/hooks/hooks.json "$source_dir/assets/codex/hooks.json"
  cmp -s .codex/.mcp.json "$source_dir/assets/stacks/go/mcp.json"
  [ -L .claude/rules/coding-style.md ]
  [ "$(readlink .claude/rules/coding-style.md)" = "../../.agents/rules/coding-style.md" ]
  [ -L .claude/agents/security-scanner.md ]
  [ -L .claude/commands/review-pr.md ]
  [ -L .claude/skills/fury-deploy/SKILL.md ]
}

@test "bootstrap creates new managed assets through atomic rename" {
  mv_log="$test_root/mv.log"
  cat > "$fake_bin/mv" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MV_LOG"
exec /bin/mv "$@"
EOF
  chmod +x "$fake_bin/mv"

  MV_LOG="$mv_log" run env PATH="$fake_bin:$PATH" bash "$skill_dir/scripts/bootstrap.sh" \
    --stack frontend --skill-dir "$skill_dir" --provider claude --sync --yes

  [ "$status" -eq 0 ]
  grep -Eq 'agent-ready-sync\.[^ ]+ \.agents/hooks/sync-marketplace\.sh$' "$mv_log"
}

@test "sync hook creates new managed assets through atomic rename" {
  source_dir="$test_root/agent-ready-setup"
  mv_log="$test_root/mv.log"
  mkdir -p \
    "$source_dir/assets/common/hooks" \
    "$source_dir/assets/codex" \
    "$source_dir/assets/stacks/go/hooks"
  touch "$source_dir/SKILL.md"
  printf '%s\n' '#!/bin/bash' > "$source_dir/assets/common/hooks/sync-marketplace.sh"
  printf '%s\n' '{"settings":"updated"}' > "$source_dir/assets/common/settings.json"
  printf '%s\n' '{"hooks":"updated"}' > "$source_dir/assets/codex/hooks.json"
  cat > "$fake_bin/mv" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MV_LOG"
exec /bin/mv "$@"
EOF
  chmod +x "$fake_bin/mv"

  AGENT_READY_SETUP_SKILL_DIR="$source_dir" MV_LOG="$mv_log" PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack go --sync --yes

  [ "$status" -eq 0 ]
  grep -Eq 'agent-ready-sync\.[^ ]+ \.agents/hooks/sync-marketplace\.sh$' "$mv_log"
}

@test "sync hook replaces its own running file atomically" {
  source_dir="$test_root/agent-ready-setup"
  mkdir -p .agents/hooks
  cp -R "$skill_dir"/. "$source_dir"/
  cp "$skill_dir/assets/common/hooks/sync-marketplace.sh" .agents/hooks/sync-marketplace.sh
  printf '%s\n' '# stale target marker' >> .agents/hooks/sync-marketplace.sh

  AGENT_READY_SETUP_SKILL_DIR="$source_dir" PATH="$test_root/bin:$PATH" \
    run bash .agents/hooks/sync-marketplace.sh \
      --provider claude --stack go --sync --yes

  [ "$status" -eq 0 ]
  cmp -s .agents/hooks/sync-marketplace.sh "$source_dir/assets/common/hooks/sync-marketplace.sh"
}

@test "sync hook reclaims lock left by terminated process" {
  source_dir="$test_root/agent-ready-setup"
  cp -R "$skill_dir"/. "$source_dir"/
  mkdir -p .agents/.agent-ready-assets.lock
  (sleep 30) &
  stale_pid=$!
  kill "$stale_pid"
  wait "$stale_pid" 2>/dev/null || true
  printf '%s\n' "$stale_pid" > .agents/.agent-ready-assets.lock/owner

  AGENT_READY_SETUP_SKILL_DIR="$source_dir" PATH="$test_root/bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack go --sync --yes

  [ "$status" -eq 0 ]
  [ ! -e .agents/.agent-ready-assets.lock ]
  cmp -s .agents/hooks/sync-marketplace.sh "$source_dir/assets/common/hooks/sync-marketplace.sh"
}

@test "sync hook preserves lock held by live process" {
  source_dir="$test_root/agent-ready-setup"
  cp -R "$skill_dir"/. "$source_dir"/
  mkdir -p .agents/.agent-ready-assets.lock
  owner_start_time="$(ps -p "$$" -o lstart= | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  printf '%s\n%s\n' "$$" "$owner_start_time" > .agents/.agent-ready-assets.lock/owner

  AGENT_READY_SETUP_SKILL_DIR="$source_dir" PATH="$test_root/bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack go --sync --yes

  [ "$status" -eq 0 ]
  [ -d .agents/.agent-ready-assets.lock ]
  [[ "$output" == *"active/ambiguous lock"* ]]
}

@test "sync hook reclaims legacy stale lock without owner metadata" {
  source_dir="$test_root/agent-ready-setup"
  cp -R "$skill_dir"/. "$source_dir"/
  mkdir -p .agents/.agent-ready-assets.lock
  touch -t 200001010000 .agents/.agent-ready-assets.lock

  AGENT_READY_SETUP_SKILL_DIR="$source_dir" PATH="$test_root/bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack go --sync --yes

  [ "$status" -eq 0 ]
  [ ! -e .agents/.agent-ready-assets.lock ]
  cmp -s .agents/hooks/sync-marketplace.sh "$source_dir/assets/common/hooks/sync-marketplace.sh"
}

@test "bootstrap reclaims asset lock left by terminated process" {
  mkdir -p .agents/.agent-ready-assets.lock
  (sleep 30) &
  stale_pid=$!
  kill "$stale_pid"
  wait "$stale_pid" 2>/dev/null || true
  printf '%s\n' "$stale_pid" > .agents/.agent-ready-assets.lock/owner

  run_bootstrap frontend --sync --yes

  [ "$status" -eq 0 ]
  [ ! -e .agents/.agent-ready-assets.lock ]
  [ -f .agents/hooks/sync-marketplace.sh ]
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
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --sync

  [ "$status" -ne 0 ]
  [ ! -e "$bootstrap_log" ]
}

@test "common marketplace assets have no stack duplicates" {
  [ -f "$skill_dir/assets/common/settings.json" ]
  [ -f "$skill_dir/assets/common/hooks/sync-marketplace.sh" ]

  for stack in frontend node java go; do
    [ ! -e "$skill_dir/assets/stacks/$stack/settings.json" ]
    [ ! -e "$skill_dir/assets/stacks/$stack/hooks/sync-marketplace.sh" ]
  done
}
