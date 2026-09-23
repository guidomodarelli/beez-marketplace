#!/usr/bin/env bats

setup() {
  repository_root="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  skill_dir="$repository_root/plugins/groot-kit/skills/agent-ready-setup"
  test_root="$(mktemp -d)"
  project_dir="$test_root/project"
  fake_bin="$test_root/bin"
  mkdir -p "$project_dir" "$fake_bin" "$test_root/tmp"
  export TMPDIR="$test_root/tmp"
  # Keeps the SessionStart upgrade window stamp out of the user's real cache.
  export XDG_CACHE_HOME="$test_root/cache"
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$fake_bin/fury"
  cat > "$fake_bin/npm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${NPM_INVOCATION_LOG:-/dev/null}"
if [[ "$1" == "view" ]]; then
  printf '%s\n' "${GROOT_UI_LATEST_VERSION:-9.9.9}"
fi
exit 0
EOF
  chmod +x "$fake_bin/npm"
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
  cmp -s CLAUDE.md "$skill_dir/assets/claude-proxy.md"
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
  for rule_file in api-configuration.md frontend-style.md lodash.md no-unnecessary-mocks.md security.md testing.md; do
    grep -Fq -- "- Read and follow \`.agents/rules/$rule_file\`." AGENTS.md
  done
  grep -Fxq '## Centralización recursiva de instrucciones' AGENTS.md
  printf '\n# Canonical shared asset\n' >> .agents/rules/security.md
  grep -Fq '# Canonical shared asset' .claude/rules/security.md
  jq -n --slurpfile claude .claude/mcp.json --slurpfile codex .codex/.mcp.json \
    '$claude[0].mcpServers == $codex[0].mcpServers' >/dev/null
  jq -e '.hooks.SessionStart[0].matcher == "startup|clear|resume"' .codex/hooks/hooks.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude)")' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/check-harness-consistency.sh)")' .claude/settings.json >/dev/null
  jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider claude"' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks[0].command == "bash .agents/hooks/check-harness-consistency.sh"' .claude/settings.json >/dev/null
  jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider codex"' .codex/hooks/hooks.json >/dev/null
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

  run_bootstrap frontend

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
  jq '.customSetting = "preserve-me" | .permissions.allow |= map(gsub("\\.agents/hooks/"; ".claude/hooks/") | gsub(" --provider claude\\)$"; " --provider claude --sync-instructions --yes)")) | .permissions.allow += ["Bash(custom-project-command)"] | .hooks.SessionStart[0].hooks[0].command |= (gsub("\\.agents/hooks/"; ".claude/hooks/") | gsub(" --provider claude$"; " --provider claude --sync-instructions --yes")) | .hooks.PostToolUse[0].hooks[0].command |= gsub("\\.agents/hooks/"; ".claude/hooks/") | .hooks.PostToolUse[0].hooks += [{"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"}]' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  [ -f .claude/hooks/custom.sh ]
  [ -f .claude/hooks/.custom-hook ]
  [ -L .claude/hooks/custom-link.sh ]
  jq -e '.customSetting == "preserve-me"' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(custom-project-command)")' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude)")' .claude/settings.json >/dev/null
  jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider claude"' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks | index({"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"})' .claude/settings.json >/dev/null
  ! grep -Fq '.claude/hooks/' .claude/settings.json
  ! grep -Fq -- '--sync' .claude/settings.json
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

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  jq -e '.permissions.allow | index("Bash(custom-project-command)")' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks | index({"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"})' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude)")' .claude/settings.json >/dev/null
}

@test "sync preserves custom settings array entries inserted before managed entries" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  jq '
    .permissions.allow = ["Bash(custom-before-managed)"] + .permissions.allow
    | .hooks.PostToolUse[0].hooks = [{"type":"command","command":"bash .agents/hooks/custom-before-managed.sh"}] + .hooks.PostToolUse[0].hooks
  ' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  jq -e '.permissions.allow[0] == "Bash(custom-before-managed)"' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude)")' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks[0] == {"type":"command","command":"bash .agents/hooks/custom-before-managed.sh"}' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks | index({"type":"command","command":"bash .agents/hooks/check-harness-consistency.sh"})' .claude/settings.json >/dev/null
}

@test "sync preserves replaced custom settings entries with equal length" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  jq '
    .permissions.allow[0] = "Bash(custom-replaced-permission)"
    | .hooks.PostToolUse[0].hooks[0] = {"type":"command","command":"bash .agents/hooks/custom-replaced-hook.sh"}
  ' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  jq -e '.permissions.allow | length == 3' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(custom-replaced-permission)") != null' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude)") != null' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/check-harness-consistency.sh)") != null' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse | length == 2' .claude/settings.json >/dev/null
  jq -e '[.hooks.PostToolUse[].hooks[]] | index({"type":"command","command":"bash .agents/hooks/custom-replaced-hook.sh"}) != null' .claude/settings.json >/dev/null
  jq -e '[.hooks.PostToolUse[].hooks[]] | index({"type":"command","command":"bash .agents/hooks/check-harness-consistency.sh"}) != null' .claude/settings.json >/dev/null
}

@test "autonomous sync merges custom Claude settings before instruction merge" {
  dynamic_skill_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$dynamic_skill_dir"

  run_marketplace_sync "$skill_dir/assets/common/hooks/sync-marketplace.sh" "$dynamic_skill_dir" \

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

  [ "$status" -eq 0 ]
  jq -e '.customSetting == "preserve-me"' .claude/settings.json >/dev/null
  jq -e '.newManagedSetting == "new-value"' .claude/settings.json >/dev/null
  jq -e '.permissions.allow[0] == "Bash(custom-before-managed)"' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude)")' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks[0] == {"type":"command","command":"bash .agents/hooks/custom-project-hook.sh"}' .claude/settings.json >/dev/null
  jq -e '.hooks.PostToolUse[0].hooks | index({"type":"command","command":"bash .agents/hooks/check-harness-consistency.sh"})' .claude/settings.json >/dev/null
}

@test "autonomous sync replaces identical and edited Claude copies with managed views" {
  dynamic_skill_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$dynamic_skill_dir"

  run_marketplace_sync "$skill_dir/assets/common/hooks/sync-marketplace.sh" "$dynamic_skill_dir" \

  [ "$status" -eq 0 ]
  rm .claude/rules/security.md
  cp .agents/rules/security.md .claude/rules/security.md

  run_marketplace_sync ".agents/hooks/sync-marketplace.sh" "$dynamic_skill_dir" \

  [ "$status" -eq 0 ]
  [ -L .claude/rules/security.md ]
  [ "$(readlink .claude/rules/security.md)" = "../../.agents/rules/security.md" ]
  [[ "$output" != *".claude/rules/security.md differs from canonical shared asset"* ]]

  rm .claude/rules/security.md
  printf '%s\n' '# Claude-only security override' > .claude/rules/security.md

  run_marketplace_sync ".agents/hooks/sync-marketplace.sh" "$dynamic_skill_dir" \

  [ "$status" -eq 0 ]
  [ "$(readlink .claude/rules/security.md)" = "../../.agents/rules/security.md" ]
  ! grep -Fq '# Claude-only security override' .agents/rules/security.md
  [[ "$output" == *".claude/rules/security.md -> managed view"* ]]
}

@test "autonomous sync normalizes CLAUDE.md under .claude and is idempotent" {
  dynamic_skill_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$dynamic_skill_dir"

  run_marketplace_sync "$skill_dir/assets/common/hooks/sync-marketplace.sh" "$dynamic_skill_dir"
  [ "$status" -eq 0 ]

  cat > .claude/CLAUDE.md <<'EOF'
## Meli SDD Kit

This project uses Meli SDD Kit.
EOF
  rm -f .claude/AGENTS.md

  run_marketplace_sync ".agents/hooks/sync-marketplace.sh" "$dynamic_skill_dir"

  [ "$status" -eq 0 ]
  [ -f .claude/AGENTS.md ]
  grep -Fxq '## Meli SDD Kit' .claude/AGENTS.md
  cmp -s .claude/CLAUDE.md "$dynamic_skill_dir/assets/claude-proxy.md"

  claude_hash_before="$(shasum .claude/CLAUDE.md | cut -d ' ' -f 1)"
  agents_hash_before="$(shasum .claude/AGENTS.md | cut -d ' ' -f 1)"

  run_marketplace_sync ".agents/hooks/sync-marketplace.sh" "$dynamic_skill_dir"

  [ "$status" -eq 0 ]
  [ "$(shasum .claude/CLAUDE.md | cut -d ' ' -f 1)" = "$claude_hash_before" ]
  [ "$(shasum .claude/AGENTS.md | cut -d ' ' -f 1)" = "$agents_hash_before" ]
}

@test "sync hook discovers provider CLAUDE.md from nested cwd" {
  dynamic_skill_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$dynamic_skill_dir"

  run_marketplace_sync "$skill_dir/assets/common/hooks/sync-marketplace.sh" "$dynamic_skill_dir"
  [ "$status" -eq 0 ]

  cat > .claude/CLAUDE.md <<'EOF'
# Nested hook instructions
EOF
  rm -f .claude/AGENTS.md

  run env \
    PATH="$test_root/bin:$PATH" \
    AGENT_READY_SETUP_SKILL_DIR="$dynamic_skill_dir" \
    bash -c 'cd .claude && bash ../.agents/hooks/sync-marketplace.sh --provider claude --stack frontend'

  [ "$status" -eq 0 ]
  [ -f .claude/AGENTS.md ]
  grep -Fxq '# Nested hook instructions' .claude/AGENTS.md
  cmp -s .claude/CLAUDE.md "$dynamic_skill_dir/assets/claude-proxy.md"
}

@test "identical legacy Claude copies become canonical symlinks" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  rm .claude/rules/security.md
  cp .agents/rules/security.md .claude/rules/security.md

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  [ -L .claude/rules/security.md ]
  [[ "$output" == *"Updated from templates:"* ]]
  [[ "$output" == *".claude/rules/security.md -> managed view"* ]]
}

@test "edited Claude copies of managed rules are replaced with managed views" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  rm .claude/rules/security.md
  printf '%s\n' '# Claude-only security override' > .claude/rules/security.md

  run_bootstrap frontend

  [ "$status" -eq 0 ]
  [ "$(readlink .claude/rules/security.md)" = "../../.agents/rules/security.md" ]
  cmp -s .agents/rules/security.md "$skill_dir/assets/stacks/frontend/rules/security.md"
  [[ "$output" == *".claude/rules/security.md -> managed view"* ]]
}

@test "nested skills receive valid Codex adapters with their directory names" {
  run_bootstrap frontend

  [ "$status" -eq 0 ]
  for skill_name in api-endpoint component-creation constants-refactor karpathy-guidelines logger service; do
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

@test "skill adapters are verbatim copies of their templates for every stack" {
  for stack in frontend go java node; do
    stack_project="$test_root/$stack-adapters"
    mkdir -p "$stack_project"
    git -C "$stack_project" -c init.defaultBranch=main init -q
    cd "$stack_project"

    run_bootstrap "$stack"

    [ "$status" -eq 0 ]
    while IFS= read -r template; do
      relative="${template#"$skill_dir/assets/stacks/$stack/"}"
      case "$relative" in
        skills/*/SKILL.md)
          skill_name="${relative#skills/}"
          skill_name="${skill_name%/SKILL.md}"
          cmp -s ".claude/skills/$skill_name/SKILL.md" "$template"
          ;;
        *)
          skill_name="${relative##*/}"
          skill_name="${skill_name%.md}"
          cmp -s ".agents/$relative" "$template"
          cmp -s ".claude/$relative" "$template"
          ;;
      esac
      cmp -s ".agents/skills/$skill_name/SKILL.md" "$template"
    done < <(find "$skill_dir/assets/stacks/$stack" -type f \( -path '*/skills/*/SKILL.md' -o -path '*/agents/*.md' -o -path '*/commands/*.md' \))
    cd "$project_dir"
  done
}

@test "skill, agent, and command templates declare provider frontmatter" {
  while IFS= read -r template; do
    case "$template" in
      */skills/*/SKILL.md) expected_name="$(basename "$(dirname "$template")")" ;;
      *) expected_name="$(basename "$template" .md)" ;;
    esac
    [ "$(sed -n '1p' "$template")" = '---' ] || { echo "missing frontmatter: $template"; false; }
    frontmatter="$(sed -n '2,/^---$/p' "$template")"
    grep -Fxq "name: $expected_name" <<< "$frontmatter" || { echo "missing name: $template"; false; }
    grep -Eq '^description: .+' <<< "$frontmatter" || { echo "missing description: $template"; false; }
  done < <(find "$skill_dir/assets/stacks" -type f \( -path '*/skills/*/SKILL.md' -o -path '*/agents/*.md' -o -path '*/commands/*.md' \))
}

@test "Claude registers each agent and command once while Codex keeps its adapter" {
  source_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$source_dir"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF

  run_bootstrap frontend
  [ "$status" -eq 0 ]
  run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"
  [ "$status" -eq 0 ]

  for workflow in agents/a11y-reviewer agents/lint-reviewer agents/perf-analyzer agents/security-scanner agents/test-reviewer commands/review-pr; do
    workflow_name="${workflow#*/}"
    [ -L ".claude/$workflow.md" ]
    [ -f ".agents/skills/$workflow_name/SKILL.md" ]
    [ ! -e ".claude/skills/$workflow_name" ]
  done
  [ -L .claude/skills/component-creation/SKILL.md ]
}

@test "sync removes duplicate Claude skill views of agents and commands, even when edited" {
  source_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$source_dir"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  run_bootstrap frontend
  [ "$status" -eq 0 ]
  mkdir -p .claude/skills/a11y-reviewer .claude/skills/lint-reviewer
  ln -s ../../../.agents/skills/a11y-reviewer/SKILL.md .claude/skills/a11y-reviewer/SKILL.md
  printf '%s\n' '# Custom lint skill' > .claude/skills/lint-reviewer/SKILL.md

  run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"

  [ "$status" -eq 0 ]
  [ ! -e .claude/skills/a11y-reviewer ]
  [[ "$output" == *"Removed duplicate Claude views:"* ]]
  [ ! -e .claude/skills/lint-reviewer ]
  [[ "$output" == *"  - .claude/skills/lint-reviewer/SKILL.md"* ]]
}

@test "sync links project rules for Claude and prunes views of deleted ones" {
  source_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$source_dir"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  run_bootstrap frontend
  [ "$status" -eq 0 ]
  mkdir -p .agents/rules/area
  printf '%s\n' '# Team conventions' > .agents/rules/team-conventions.md
  printf '%s\n' '# Area rule' > .agents/rules/area/payments.md

  run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"

  [ "$status" -eq 0 ]
  [ "$(readlink .claude/rules/team-conventions.md)" = "../../.agents/rules/team-conventions.md" ]
  [ "$(readlink .claude/rules/area/payments.md)" = "../../../.agents/rules/area/payments.md" ]
  [ -f .agents/rules/team-conventions.md ]

  rm .agents/rules/team-conventions.md
  run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"

  [ "$status" -eq 0 ]
  [ ! -L .claude/rules/team-conventions.md ]
  [ -L .claude/rules/area/payments.md ]
  [ -L .claude/rules/security.md ]
}

@test "sync hook replaces placeholder adapter descriptions from older projections" {
  source_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$source_dir"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  run_bootstrap frontend
  [ "$status" -eq 0 ]
  template="$skill_dir/assets/stacks/frontend/skills/constants-refactor/SKILL.md"
  {
    printf '%s\n' '---' 'name: constants-refactor' \
      'description: Provider-neutral reusable workflow for constants-refactor.' '---' ''
    sed '1,/^---$/d' "$template"
  } > .agents/skills/constants-refactor/SKILL.md

  run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"

  [ "$status" -eq 0 ]
  cmp -s .agents/skills/constants-refactor/SKILL.md "$template"
  [[ "$output" == *"↻ .agents/skills/constants-refactor/SKILL.md"* ]]
}

@test "flat deploy templates become discoverable skills for Claude and shared agents" {
  for stack in go java node; do
    stack_project="$test_root/$stack-project"
    mkdir -p "$stack_project"
    git -C "$stack_project" -c init.defaultBranch=main init -q
    cd "$stack_project"

    run_bootstrap "$stack"

    [ "$status" -eq 0 ]
    cmp -s CLAUDE.md "$skill_dir/assets/claude-proxy.md"
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
    jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider claude"' .claude/settings.json >/dev/null
    jq -e '.hooks.PostToolUse[0].hooks[0].command == "bash .agents/hooks/check-harness-consistency.sh"' .claude/settings.json >/dev/null
    jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider codex"' .codex/hooks/hooks.json >/dev/null
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
  [ "$(cat AGENTS.md)" = $'# Existing project instructions\n\nRun the project test command before merging.' ]
  cmp -s CLAUDE.md "$skill_dir/assets/claude-proxy.md"
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
  cmp -s CLAUDE.md "$skill_dir/assets/claude-proxy.md"
}

@test "normalized root CLAUDE proxy and existing AGENTS are preserved" {
  cat > AGENTS.md <<'EOF'
# Canonical instructions
EOF
  cp "$skill_dir/assets/claude-proxy.md" CLAUDE.md
  claude_hash_before="$(shasum CLAUDE.md | cut -d ' ' -f 1)"

  run_bootstrap java

  [ "$status" -eq 0 ]
  [ "$(shasum CLAUDE.md | cut -d ' ' -f 1)" = "$claude_hash_before" ]
  [ "$(cat AGENTS.md)" = '# Canonical instructions' ]
}

@test "orphaned normalized root CLAUDE proxy recreates canonical AGENTS" {
  cp "$skill_dir/assets/claude-proxy.md" CLAUDE.md

  run_bootstrap java

  [ "$status" -eq 0 ]
  [ -f AGENTS.md ]
  grep -Fq '# [Project Name]' AGENTS.md
  grep -Fxq '## Centralización recursiva de instrucciones' AGENTS.md
  cmp -s CLAUDE.md "$skill_dir/assets/claude-proxy.md"
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
  cmp -s service/CLAUDE.md "$skill_dir/assets/claude-proxy.md"
  cmp -s packages/api/CLAUDE.md "$skill_dir/assets/claude-proxy.md"
  grep -Fq '# API instructions' packages/api/AGENTS.md
  grep -Fq 'Keep API changes backwards compatible.' packages/api/AGENTS.md
}

@test "nested legacy CLAUDE proxy upgrades to root template" {
  mkdir -p service
  printf '%s\n' '@AGENTS.md' > service/CLAUDE.md
  printf '%s\n' '# Canonical service instructions' > service/AGENTS.md

  run_bootstrap node

  [ "$status" -eq 0 ]
  cmp -s service/CLAUDE.md "$skill_dir/assets/claude-proxy.md"
  grep -Fq '# Canonical service instructions' service/AGENTS.md
}

@test "nested exact CLAUDE proxy creates an empty canonical sibling" {
  mkdir -p service
  cp "$skill_dir/assets/claude-proxy.md" service/CLAUDE.md

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ -f service/AGENTS.md ]
  [ ! -s service/AGENTS.md ]
  cmp -s service/CLAUDE.md "$skill_dir/assets/claude-proxy.md"
}

@test "provider configuration CLAUDE.md gets a sibling AGENTS.md and exact proxy" {
  mkdir -p .claude
  cat > .claude/CLAUDE.md <<'EOF'
## Meli SDD Kit

This project uses Meli SDD Kit.
EOF

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ -f .claude/AGENTS.md ]
  grep -Fxq '## Meli SDD Kit' .claude/AGENTS.md
  grep -Fxq 'This project uses Meli SDD Kit.' .claude/AGENTS.md
  cmp -s .claude/CLAUDE.md "$skill_dir/assets/claude-proxy.md"
  [[ "$output" == *".claude/CLAUDE.md -> .claude/AGENTS.md"* ]]
}

@test "instruction normalization uses Git root when invoked from nested directory" {
  mkdir -p .claude
  cat > .claude/CLAUDE.md <<'EOF'
# Claude instructions

Run checks from project root.
EOF

  run bash -c "cd .claude && env PATH=\"$test_root/bin:\$PATH\" bash \"$skill_dir/scripts/bootstrap.sh\" --stack node --skill-dir \"$skill_dir\" --provider claude"

  [ "$status" -eq 0 ]
  [ -f .claude/AGENTS.md ]
  grep -Fxq '# Claude instructions' .claude/AGENTS.md
  cmp -s .claude/CLAUDE.md "$skill_dir/assets/claude-proxy.md"
}

@test "case-variant instruction filenames normalize recursively" {
  cat > Claude.md <<'EOF'
# Root instructions

Run root checks before merging.
EOF
  mkdir -p services/api/v1
  cat > services/api/v1/claude.MD <<'EOF'
# API instructions

Run API checks before merging.
EOF

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ "$(find . -maxdepth 1 -type f -name 'Claude.md' -print)" = "" ]
  [ "$(find services/api/v1 -maxdepth 1 -type f -name 'claude.MD' -print)" = "" ]
  [ -f CLAUDE.md ]
  [ -f services/api/v1/CLAUDE.md ]
  grep -Fq '# Root instructions' AGENTS.md
  grep -Fq 'Run root checks before merging.' AGENTS.md
  grep -Fq '# API instructions' services/api/v1/AGENTS.md
  grep -Fq 'Run API checks before merging.' services/api/v1/AGENTS.md
  cmp -s CLAUDE.md "$skill_dir/assets/claude-proxy.md"
  cmp -s services/api/v1/CLAUDE.md "$skill_dir/assets/claude-proxy.md"
  [[ "$output" == *"Renamed instruction files:"* ]]
  [[ "$output" == *"Claude.md -> ./CLAUDE.md"* ]]
  [[ "$output" == *"services/api/v1/claude.MD -> services/api/v1/CLAUDE.md"* ]]
}

@test "case-variant rename preserves a concurrent canonical destination" {
  mkdir -p service
  printf '%s\n' '# Original instructions' > service/Claude.md
  printf '%s\n' '# Existing canonical instructions' > service/AGENTS.md
  cat > "$fake_bin/mv" <<'EOF'
#!/bin/bash
/bin/mv "$@"
for argument in "$@"; do
  if [[ "$argument" == *agent-ready-name.* ]]; then
    printf '%s\n' '# Concurrent instructions' > service/CLAUDE.md
    break
  fi
done
EOF
  chmod +x "$fake_bin/mv"

  run env PATH="$test_root/bin:$PATH" bash "$skill_dir/scripts/bootstrap.sh" \
    --stack node \
    --skill-dir "$skill_dir" \
    --provider claude

  [ "$status" -eq 0 ]
  [ "$(cat service/CLAUDE.md)" = '# Concurrent instructions' ]
  [[ "$output" == *"destination changed concurrently and was preserved"* ]]
  if [ -n "$(find service -maxdepth 1 -type f -name 'Claude.md' -print)" ]; then
    [ "$(cat service/Claude.md)" = '# Original instructions' ]
  else
    staged_files=(service/.CLAUDE.md.agent-ready-name.*)
    [ -f "${staged_files[0]}" ]
    [ "$(cat "${staged_files[0]}")" = '# Original instructions' ]
  fi
}

@test "ignored case-variant instruction filenames remain untouched" {
  printf '%s\n' 'node_modules/' > .gitignore
  mkdir -p node_modules/example-package
  cat > node_modules/example-package/Claude.md <<'EOF'
# Dependency instructions
EOF

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ -f node_modules/example-package/Claude.md ]
  [ "$(find node_modules/example-package -maxdepth 1 -type f -name 'CLAUDE.md' -print)" = "" ]
  [ ! -e node_modules/example-package/AGENTS.md ]
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
  cmp -s node_modules/tracked-package/CLAUDE.md "$skill_dir/assets/claude-proxy.md"
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
  cmp -s CLAUDE.md "$skill_dir/assets/claude-proxy.md"
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

@test "frontend bootstrap reports latest groot-ui without installing and configures package scripts" {
  npm_log="$test_root/npm-invocation.log"
  cat > package.json <<'EOF'
{
  "name": "frontend-project",
  "scripts": {
    "i18n:gettext": "i18n gettext",
    "i18n:upload": "i18n upload",
    "generate-po.zip": "node ./translations/po-generate-zip.js",
    "upload-translations": "upload-translations --appName=test",
    "clean-locales": "clean-po-locales && clean-json-locales",
    "install-selenium": "selenium-standalone install"
  },
  "dependencies": {
    "react": "1.0.0",
    "kraken-translations": "^0.1.4"
  }
}
EOF
  printf '%s\n' '{"lockfileVersion":3,"marker":"preserve"}' > package-lock.json

  GROOT_UI_LATEST_VERSION="2.3.4" NPM_INVOCATION_LOG="$npm_log" run_bootstrap frontend

  [ "$status" -eq 0 ]
  grep -Fxq 'view groot-ui version' "$npm_log"
  ! grep -Fq 'install' "$npm_log"
  jq -e '.scripts.i18n == "groot-i18n"' package.json >/dev/null
  jq -e '.scripts.local2prod == "groot-config-sync"' package.json >/dev/null
  jq -e '(.scripts | has("i18n:gettext")) | not' package.json >/dev/null
  jq -e '(.scripts | has("i18n:upload")) | not' package.json >/dev/null
  jq -e '(.scripts | has("generate-po.zip")) | not' package.json >/dev/null
  jq -e '(.scripts | has("upload-translations")) | not' package.json >/dev/null
  jq -e '(.scripts | has("clean-locales")) | not' package.json >/dev/null
  jq -e '(.scripts["install-selenium"] == "selenium-standalone install")' package.json >/dev/null
  jq -e '(.dependencies | has("kraken-translations")) | not' package.json >/dev/null
  [[ "$output" == *"[groot-ui] Latest available version: groot-ui@2.3.4"* ]]
  [[ "$output" == *"No package installation was performed"* ]]
  [[ "$output" == *"kraken-translations was removed from package.json; run npm install to update package-lock.json"* ]]
  [[ "$output" == *"npm install --save groot-ui@2.3.4"* ]]
  ! grep -Fq 'Installing' <<< "$output"
  [ "$(cat package-lock.json)" = '{"lockfileVersion":3,"marker":"preserve"}' ]
  [[ "$output" == *"[groot-ui] Configured"* ]]
}

@test "sync hook reuses a marketplace upgrade from the last hour unless forced" {
  source_dir="$test_root/dynamic-skill"
  cp -R "$skill_dir" "$source_dir"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  fury_log="$test_root/fury.log"
  cat > "$fake_bin/fury" <<EOF
#!/bin/bash
printf '%s\\n' upgrade >> "$fury_log"
EOF
  chmod +x "$fake_bin/fury"
  stamp="$XDG_CACHE_HOME/agent-ready-setup/marketplace-upgrade-claude.stamp"

  run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"
  [ "$status" -eq 0 ]
  [ -f "$stamp" ]
  [ "$(wc -l < "$fury_log" | tr -d ' ')" -eq 1 ]

  run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$fury_log" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"Marketplace upgraded less than 60 minutes ago; upgrade skipped."* ]]

  AGENT_READY_SETUP_FORCE_UPGRADE=1 run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$fury_log" | tr -d ' ')" -eq 2 ]

  touch -t 202001010000 "$stamp"
  run_marketplace_sync "$source_dir/assets/common/hooks/sync-marketplace.sh" "$source_dir"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$fury_log" | tr -d ' ')" -eq 3 ]
}

@test "failed marketplace upgrade does not open the upgrade window" {
  cat > "$fake_bin/fury" <<'EOF'
#!/bin/bash
exit 7
EOF
  chmod +x "$fake_bin/fury"

  run_marketplace_sync "$skill_dir/assets/common/hooks/sync-marketplace.sh" "$skill_dir"

  [ "$status" -ne 0 ]
  [ ! -e "$XDG_CACHE_HOME/agent-ready-setup/marketplace-upgrade-claude.stamp" ]
}

@test "frontend sync looks up groot-ui concurrently with the marketplace upgrade" {
  event_log="$test_root/network-events.log"
  printf '%s\n' '{"name":"frontend-project","dependencies":{"react":"1.0.0"}}' > package.json
  cat > "$fake_bin/fury" <<EOF
#!/bin/bash
printf '%s\\n' fury-start >> "$event_log"
sleep 1
printf '%s\\n' fury-end >> "$event_log"
EOF
  cat > "$fake_bin/npm" <<EOF
#!/bin/bash
[[ "\$1" == "view" ]] && printf '%s\\n' npm-view >> "$event_log"
printf '%s\\n' 2.3.4
EOF
  chmod +x "$fake_bin/fury" "$fake_bin/npm"

  AGENT_READY_SETUP_SKILL_DIR="$skill_dir" PATH="$fake_bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" --provider claude

  [ "$status" -eq 0 ]
  [ "$(grep -c '^npm-view$' "$event_log")" -eq 1 ]
  npm_line="$(grep -n '^npm-view$' "$event_log" | cut -d: -f1)"
  fury_end_line="$(grep -n '^fury-end$' "$event_log" | cut -d: -f1)"
  [ "$npm_line" -lt "$fury_end_line" ]
  [[ "$output" == *"[groot-ui] Latest available version: groot-ui@2.3.4"* ]]
}

@test "frontend sync reports latest groot-ui without installing and enforces frontend scripts" {
  npm_log="$test_root/npm-invocation.log"
  cat > package.json <<'EOF'
{
  "name": "frontend-project",
  "scripts": {
    "i18n": "custom-i18n",
    "local2prod": "old-config-command",
    "i18n:gettext": "i18n gettext",
    "i18n:upload": "i18n upload",
    "generate-po.zip": "node ./translations/po-generate-zip.js",
    "upload-translations": "upload-translations --appName=test",
    "clean-locales": "clean-po-locales && clean-json-locales",
    "install-selenium": "selenium-standalone install"
  },
  "dependencies": {
    "react": "1.0.0",
    "groot-ui": "^1.0.0",
    "kraken-translations": "^0.1.4"
  }
}
EOF
  printf '%s\n' '{"lockfileVersion":3,"marker":"preserve"}' > package-lock.json

  GROOT_UI_LATEST_VERSION="2.3.4" NPM_INVOCATION_LOG="$npm_log" AGENT_READY_SETUP_SKILL_DIR="$skill_dir" \
    PATH="$test_root/bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" --provider claude

  [ "$status" -eq 0 ]
  [ "$(grep -c '^view groot-ui version$' "$npm_log")" -eq 1 ]
  [[ "$output" == *"[groot-ui] Latest available version: groot-ui@2.3.4"* ]]
  ! grep -Fq 'install' "$npm_log"
  jq -e '.scripts.i18n == "groot-i18n"' package.json >/dev/null
  jq -e '.scripts.local2prod == "groot-config-sync"' package.json >/dev/null
  jq -e '(.scripts | has("i18n:gettext")) | not' package.json >/dev/null
  jq -e '(.scripts | has("i18n:upload")) | not' package.json >/dev/null
  jq -e '(.scripts | has("generate-po.zip")) | not' package.json >/dev/null
  jq -e '(.scripts | has("upload-translations")) | not' package.json >/dev/null
  jq -e '(.scripts | has("clean-locales")) | not' package.json >/dev/null
  jq -e '(.scripts["install-selenium"] == "selenium-standalone install")' package.json >/dev/null
  jq -e '(.dependencies | has("kraken-translations")) | not' package.json >/dev/null
  jq -e '.dependencies["groot-ui"] == "^1.0.0"' package.json >/dev/null
  [[ "$output" == *"Latest available version: groot-ui@2.3.4"* ]]
  [[ "$output" == *"npm install --save groot-ui@2.3.4"* ]]
  [ "$(cat package-lock.json)" = '{"lockfileVersion":3,"marker":"preserve"}' ]
  [[ "$output" == *"Local managed asset projection completed for frontend."* ]]
}

@test "frontend groot-ui warning is omitted when lockfile has latest version" {
  cat > package.json <<'EOF'
{
  "name": "frontend-project",
  "dependencies": {
    "react": "1.0.0",
    "groot-ui": "^2.3.4"
  }
}
EOF
  cat > package-lock.json <<'EOF'
{
  "name": "frontend-project",
  "lockfileVersion": 3,
  "packages": {
    "": {
      "dependencies": {
        "groot-ui": "^2.3.4"
      }
    },
    "node_modules/groot-ui": {
      "version": "2.3.4"
    }
  }
}
EOF

  GROOT_UI_LATEST_VERSION="2.3.4" run_bootstrap frontend

  [ "$status" -eq 0 ]
  [[ "$output" == *"Current effective version is 2.3.4 (lockfile); no update is required."* ]]
  ! grep -Fq 'WARNING: [groot-ui]' <<< "$output"
  ! grep -Fq 'npm install --save groot-ui@' <<< "$output"
  [[ "$output" == *"kraken-translations was not declared in package.json; no npm install is required for its removal."* ]]
}

@test "frontend groot-ui lookup failure leaves package files unchanged" {
  cat > package.json <<'EOF'
{
  "name": "frontend-project",
  "scripts": {
    "i18n:gettext": "i18n gettext"
  },
  "dependencies": {
    "react": "1.0.0",
    "groot-ui": "^1.0.0"
  }
}
EOF
  printf '%s\n' '{"lockfileVersion":3,"marker":"preserve"}' > package-lock.json
  cp package.json "$test_root/package.json.before"
  cp package-lock.json "$test_root/package-lock.json.before"
  cat > "$fake_bin/npm" <<'EOF'
#!/bin/bash
if [[ "$1" == "view" ]]; then
  printf '%s\n' 'registry unavailable' >&2
  exit 42
fi
exit 0
EOF
  chmod +x "$fake_bin/npm"

  run_bootstrap frontend

  [ "$status" -ne 0 ]
  cmp -s package.json "$test_root/package.json.before"
  cmp -s package-lock.json "$test_root/package-lock.json.before"
  [[ "$output" == *"could not look up the latest groot-ui version"* ]]
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
    bash "$hook" --provider claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not detect project stack"* ]]
}

@test "sync hook rejects removed phase flags" {
  for removed_flag in --sync --update --sync-instructions --merge-instructions --yes; do
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude "$removed_flag"

    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported marketplace sync argument: $removed_flag"* ]]
  done
}

@test "sync hook rejects invalid reexecution guards" {
  for guard in AGENT_READY_SETUP_MARKETPLACE_UPGRADED AGENT_READY_SETUP_SYNC_LOCK_HELD; do
    run env "$guard=invalid" PATH="$test_root/bin:$PATH" \
      bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" --provider claude

    [ "$status" -ne 0 ]
    [[ "$output" == *"$guard must be 0 or 1"* ]]
  done
}

@test "bootstrap shows diffs and updates changed managed assets without prompting" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  printf '%s\n' '# Local change' >> .agents/rules/security.md

  run_bootstrap frontend < /dev/null

  [ "$status" -eq 0 ]
  cmp -s .agents/rules/security.md "$skill_dir/assets/stacks/frontend/rules/security.md"
  [[ "$output" == *"Diff for .agents/rules/security.md"* ]]
  [[ "$output" != *"Pending confirmation"* ]]
  [[ "$output" != *"Replace .agents/rules/security.md with the template?"* ]]
}

@test "bootstrap updates managed assets and preserves root instructions" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  printf '%s\n' '# Local change' >> .agents/rules/security.md
  printf '%s\n' '# Project instructions' > AGENTS.md
  cp "$skill_dir/assets/claude-proxy.md" CLAUDE.md
  root_hash_before="$(shasum AGENTS.md CLAUDE.md | shasum | cut -d ' ' -f 1)"

  run_bootstrap frontend

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
      --provider claude
  [ "$status" -eq 0 ]
  cmp -s .agents/hooks/sync-marketplace.sh "$source_dir/assets/common/hooks/sync-marketplace.sh"
  cmp -s .claude/settings.json "$source_dir/assets/common/settings.json"
  cmp -s .codex/hooks/hooks.json "$source_dir/assets/codex/hooks.json"
}

@test "bootstrap detects managed destination changes before atomic rename" {
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
    --stack frontend --skill-dir "$skill_dir" --provider claude

  [ "$status" -eq 0 ]
  [ "$(cat .agents/rules/security.md)" = '# Newer destination change' ]
  [[ "$output" == *".agents/rules/security.md changed during synchronization; neither was changed"* ]]
}

@test "bootstrap rejects removed sync and confirmation flags" {
  for removed_flag in --sync --update --yes; do
    run bash "$skill_dir/scripts/bootstrap.sh" --stack node --skill-dir "$skill_dir" --provider claude "$removed_flag"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown argument: $removed_flag"* ]]
  done
}

@test "symlinked managed assets are replaced without touching their target" {
  outside_file="$test_root/outside-security.md"
  printf '%s\n' '# Outside asset' > "$outside_file"
  run_bootstrap node
  [ "$status" -eq 0 ]

  rm .agents/rules/security.md
  ln -s "$outside_file" .agents/rules/security.md

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ ! -L .agents/rules/security.md ]
  cmp -s .agents/rules/security.md "$skill_dir/assets/stacks/node/rules/security.md"
  [ "$(cat "$outside_file")" = '# Outside asset' ]
  [[ "$output" == *".agents/rules/security.md (symlink replaced with template)"* ]]
}

@test "a symlink to a directory at a managed path cannot redirect the write" {
  outside_directory="$test_root/outside-directory"
  mkdir -p "$outside_directory"
  run_bootstrap node
  [ "$status" -eq 0 ]

  rm .agents/rules/security.md
  ln -s "$outside_directory" .agents/rules/security.md

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ -f .agents/rules/security.md ]
  [ ! -L .agents/rules/security.md ]
  [ -z "$(ls -A "$outside_directory")" ]
}

@test "a directory at a managed path is preserved and reported" {
  run_bootstrap node
  [ "$status" -eq 0 ]

  rm .agents/rules/security.md
  mkdir .agents/rules/security.md

  run_bootstrap node

  [ "$status" -eq 0 ]
  [ -d .agents/rules/security.md ]
  [[ "$output" == *".agents/rules/security.md is not a regular file"* ]]
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

@test "bootstrap ignores higher versions from another plugin cache" {
  cache_root="$test_root/.claude/plugins/cache/groot-marketplace"
  target_source="$cache_root/groot-kit/1.9.0/skills/agent-ready-setup"
  unrelated_source="$cache_root/other-plugin/99.0.0/skills/agent-ready-setup"
  mkdir -p "$target_source" "$unrelated_source"
  cp -R "$skill_dir"/. "$target_source"/
  cp -R "$skill_dir"/. "$unrelated_source"/
  printf '%s\n' '# groot-kit template' > "$target_source/assets/stacks/node/rules/security.md"
  printf '%s\n' '# unrelated template' > "$unrelated_source/assets/stacks/node/rules/security.md"
  cat > "$target_source/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$target_source/scripts/merge-instructions.sh"

  run env HOME="$test_root" PATH="$test_root/bin:$PATH" \
    bash "$target_source/scripts/bootstrap.sh" \
      --stack node \
      --skill-dir "$target_source" \
      --provider claude

  [ "$status" -eq 0 ]
  grep -Fxq '# groot-kit template' .agents/rules/security.md
  ! grep -Fxq '# unrelated template' .agents/rules/security.md
}

@test "resolvers select highest semantic cache version for Claude and Codex" {
  for provider in claude codex; do
    cache_root="$test_root/.$provider/plugins/cache/groot-marketplace/groot-kit"
    old_source="$cache_root/1.9.0/skills/agent-ready-setup"
    new_source="$cache_root/1.10.2/skills/agent-ready-setup"
    mkdir -p "$old_source" "$new_source"
    cp -R "$skill_dir"/. "$old_source"/
    cp -R "$skill_dir"/. "$new_source"/
    printf '%s\n' "# old $provider template" > "$old_source/assets/stacks/node/rules/security.md"
    printf '%s\n' "# newest $provider template" > "$new_source/assets/stacks/node/rules/security.md"
    cat > "$new_source/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$new_source/scripts/merge-instructions.sh"

    rm -rf .agents .claude .codex AGENTS.md CLAUDE.md
    mkdir -p .agents/rules
    printf '%s\n' "# existing $provider rule" > .agents/rules/security.md

    run env HOME="$test_root" PATH="$test_root/bin:$PATH" \
      bash "$old_source/scripts/bootstrap.sh" \
        --stack node \
        --skill-dir "$old_source" \
        --provider "$provider"

    [ "$status" -eq 0 ]
    grep -Fxq "# newest $provider template" .agents/rules/security.md

    rm -rf .agents .claude .codex AGENTS.md CLAUDE.md
    mkdir -p .agents/rules
    printf '%s\n' "# existing hook $provider rule" > .agents/rules/security.md

    run env HOME="$test_root" PATH="$test_root/bin:$PATH" \
      bash "$old_source/assets/common/hooks/sync-marketplace.sh" \
        --provider "$provider" \
        --stack node

    [ "$status" -eq 0 ]
    grep -Fxq "# newest $provider template" .agents/rules/security.md
  done
}

@test "sync hook prefers newest semantic cache over active old source" {
  for provider in claude codex; do
    provider_root="$test_root/.$provider"
    cache_root="$provider_root/plugins/cache/groot-marketplace/groot-kit"
    old_source="$cache_root/1.9.0/skills/agent-ready-setup"
    new_source="$cache_root/1.10.2/skills/agent-ready-setup"
    mkdir -p "$old_source" "$new_source"
    cp -R "$skill_dir"/. "$old_source"/
    cp -R "$skill_dir"/. "$new_source"/
    printf '%s\n' "# old $provider template" > "$old_source/assets/stacks/node/rules/security.md"
    printf '%s\n' "# newest $provider template" > "$new_source/assets/stacks/node/rules/security.md"
    cat > "$new_source/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$new_source/scripts/merge-instructions.sh"

    rm -rf .agents .claude .codex AGENTS.md CLAUDE.md
    mkdir -p .agents/rules
    printf '%s\n' "# existing $provider rule" > .agents/rules/security.md

    run env \
      HOME="$test_root" \
      PATH="$test_root/bin:$PATH" \
      CLAUDE_PLUGIN_ROOT="$old_source" \
      bash "$old_source/assets/common/hooks/sync-marketplace.sh" \
        --provider "$provider" \
        --stack node

    [ "$status" -eq 0 ]
    grep -Fxq "# newest $provider template" .agents/rules/security.md
    [[ "$output" == *"[marketplace-sync] Using agent-ready-setup cache version 1.10.2."* ]]
  done
}

@test "bootstrap keeps requested newest cache version instead of downgrading" {
  cache_root="$test_root/.claude/plugins/cache/groot-marketplace/groot-kit"
  old_source="$cache_root/1.9.0/skills/agent-ready-setup"
  new_source="$cache_root/1.10.2/skills/agent-ready-setup"
  mkdir -p "$old_source" "$new_source"
  cp -R "$skill_dir"/. "$old_source"/
  cp -R "$skill_dir"/. "$new_source"/
  printf '%s\n' '# old template' > "$old_source/assets/stacks/node/rules/security.md"
  printf '%s\n' '# newest template' > "$new_source/assets/stacks/node/rules/security.md"

  run env HOME="$test_root" PATH="$test_root/bin:$PATH" \
    bash "$new_source/scripts/bootstrap.sh" \
      --stack node \
      --skill-dir "$new_source" \
      --provider claude

  [ "$status" -eq 0 ]
  grep -Fxq '# newest template' .agents/rules/security.md
  [[ "$output" == *"Using agent-ready-setup cache version 1.10.2."* ]]
  [[ "$output" != *"cache version 1.9.0"* ]]
}

@test "sync hook refreshes missing shared helper before projecting assets" {
  cache_root="$test_root/.claude/plugins/cache/groot-marketplace/groot-kit"
  source_dir="$cache_root/1.0.0/skills/agent-ready-setup"
  fury_log="$test_root/fury.log"
  mkdir -p "$(dirname "$source_dir")"
  cp -R "$skill_dir" "$source_dir"
  rm "$source_dir/scripts/asset-sync-common.sh"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$source_dir/scripts/merge-instructions.sh"
  cat > "$fake_bin/fury" <<EOF
#!/bin/bash
printf '%s\\n' "\$*" >> "$fury_log"
if [[ "\$(wc -l < "$fury_log")" -eq 2 ]]; then
  cp "$skill_dir/scripts/asset-sync-common.sh" "$source_dir/scripts/asset-sync-common.sh"
fi
EOF
  chmod +x "$fake_bin/fury"

  run env HOME="$test_root" PATH="$fake_bin:$PATH" \
    bash "$source_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack node

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$fury_log")" -eq 2 ]
  [ -f "$source_dir/scripts/asset-sync-common.sh" ]
  cmp -s .agents/hooks/sync-marketplace.sh \
    "$source_dir/assets/common/hooks/sync-marketplace.sh"
  [[ "$output" == *"Shared synchronization helper is missing; refreshing"* ]]
}

@test "sync hook preserves local hook when helper remains unavailable after refresh" {
  cache_root="$test_root/.claude/plugins/cache/groot-marketplace/groot-kit"
  source_dir="$cache_root/1.0.0/skills/agent-ready-setup"
  fury_log="$test_root/fury.log"
  mkdir -p "$(dirname "$source_dir")" .agents/hooks
  cp -R "$skill_dir" "$source_dir"
  rm "$source_dir/scripts/asset-sync-common.sh"
  printf '%s\n' '# local hook' > .agents/hooks/sync-marketplace.sh
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$source_dir/scripts/merge-instructions.sh"
  cat > "$fake_bin/fury" <<EOF
#!/bin/bash
printf '%s\\n' "\$*" >> "$fury_log"
exit 0
EOF
  chmod +x "$fake_bin/fury"

  run env HOME="$test_root" PATH="$fake_bin:$PATH" \
    bash "$source_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack node

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$fury_log")" -eq 2 ]
  grep -Fxq '# local hook' .agents/hooks/sync-marketplace.sh
  [[ "$output" == *"is unavailable after marketplace refresh; local projection skipped."* ]]
}

@test "sync hook preserves custom Claude array entries with equal length" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  jq '.permissions.allow[0] = "Bash(custom-command)"' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  cat > "$test_root/bin/claude" <<'EOF'
#!/bin/bash
awk '/^<!-- BEGIN AGENT-READY MANAGED -->$/ { print "<!-- AGENT-READY MANAGED BLOCK -->"; skip = 1; next }
  /^<!-- END AGENT-READY MANAGED -->$/ { skip = 0; next }
  !skip' AGENTS.md |
  jq -Rs '{project_content:., removed:[], inconsistencies:[], reason:"No changes"}'
EOF
  chmod +x "$test_root/bin/claude"

  AGENT_READY_SETUP_SKILL_DIR="$skill_dir" PATH="$test_root/bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack frontend

  [ "$status" -eq 0 ]
  jq -e '.permissions.allow | length == 3' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(custom-command)") != null' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude)") != null' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("Bash(.agents/hooks/check-harness-consistency.sh)") != null' .claude/settings.json >/dev/null
  [[ "$output" == *"Local backups directory:"* ]]
  backup_files=("$test_root"/tmp/agent-ready-backups.*/.claude/settings.json.agent-ready-backup.*)
  [ -f "${backup_files[0]}" ]
  grep -Fq 'Bash(custom-command)' "${backup_files[0]}"
}

@test "sync hook migrates legacy Claude settings path and flags" {
  run_bootstrap frontend
  [ "$status" -eq 0 ]

  jq '
    .permissions.allow[0] = "Bash(.claude/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes)"
    | .permissions.allow += [
        "bash .agents/hooks/sync-marketplace.sh-wrapper --provider claude --custom",
        "bash .agents/hooks/sync-marketplace.sh --provider claude --stack node"
      ]
    | .hooks.SessionStart[0].hooks[0].command = "bash .claude/hooks/sync-marketplace.sh --provider claude --sync-instructions --yes"
  ' .claude/settings.json > "$test_root/settings.json"
  mv "$test_root/settings.json" .claude/settings.json

  cat > "$test_root/bin/claude" <<'EOF'
#!/bin/bash
awk '/^<!-- BEGIN AGENT-READY MANAGED -->$/ { print "<!-- AGENT-READY MANAGED BLOCK -->"; skip = 1; next }
  /^<!-- END AGENT-READY MANAGED -->$/ { skip = 0; next }
  !skip' AGENTS.md |
  jq -Rs '{project_content:., removed:[], inconsistencies:[], reason:"No changes"}'
EOF
  chmod +x "$test_root/bin/claude"

  AGENT_READY_SETUP_SKILL_DIR="$skill_dir" PATH="$test_root/bin:$PATH" \
    run bash "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
      --provider claude --stack frontend

  [ "$status" -eq 0 ]
  jq -e '.permissions.allow | index("Bash(.agents/hooks/sync-marketplace.sh --provider claude)")' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("bash .agents/hooks/sync-marketplace.sh-wrapper --provider claude --custom")' .claude/settings.json >/dev/null
  jq -e '.permissions.allow | index("bash .agents/hooks/sync-marketplace.sh --provider claude --stack node")' .claude/settings.json >/dev/null
  jq -e '.hooks.SessionStart[0].hooks[0].command == "bash .agents/hooks/sync-marketplace.sh --provider claude"' .claude/settings.json >/dev/null
  ! grep -Fq '.claude/hooks/' .claude/settings.json
  ! grep -Fq -- '--sync' .claude/settings.json
}

@test "sync hook projects managed assets without bootstrap" {
  fake_bin="$test_root/bin"
  source_dir="$test_root/agent-ready-setup"
  event_log="$test_root/events.log"
  bootstrap_log="$test_root/bootstrap.log"
  mkdir -p \
    "$fake_bin" \
    "$source_dir/assets/common/hooks" \
    "$source_dir/assets/common/shared" \
    "$source_dir/assets/codex" \
    "$source_dir/assets/stacks/go/hooks" \
    "$source_dir/assets/stacks/go/rules" \
    "$source_dir/assets/stacks/go/agents" \
    "$source_dir/assets/stacks/go/commands" \
    "$source_dir/assets/stacks/go/skills/fury-deploy" \
    "$source_dir/scripts" \
    .agents/rules
  touch "$source_dir/SKILL.md"
  cp "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
    "$source_dir/assets/common/hooks/sync-marketplace.sh"
  cp "$skill_dir/scripts/asset-sync-common.sh" "$source_dir/scripts/asset-sync-common.sh"
  cp "$skill_dir/scripts/merge-managed-settings.py" "$source_dir/scripts/merge-managed-settings.py"
  printf '%s\n' '{"settings":"updated"}' > "$source_dir/assets/common/settings.json"
  printf '%s\n' '# updated common asset' > "$source_dir/assets/common/shared/asset.md"
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
  mkdir -p .agents/shared
  printf '%s\n' '# previous common asset' > .agents/shared/asset.md
  printf '%s\n' '# previous coding style' > .agents/rules/coding-style.md
  cat > "$source_dir/scripts/bootstrap.sh" <<'EOF'
#!/bin/bash
printf 'bootstrap\n' >> "$EVENT_LOG"
printf '%s\n' "$*" > "$BOOTSTRAP_INVOCATION_LOG"
EOF
  chmod +x "$source_dir/scripts/bootstrap.sh"
  cat > "$source_dir/scripts/merge-instructions.sh" <<'EOF'
#!/bin/bash
[[ "$(cat .agents/shared/asset.md)" = '# updated common asset' ]] || exit 42
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
      --provider claude --stack go

  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$event_log")" = "fury" ]
  [ "$(sed -n '2p' "$event_log")" = "merge" ]
  [ "$(wc -l < "$event_log")" -eq 2 ]
  [ ! -e "$bootstrap_log" ]
  grep -Fxq 'ai assets marketplace upgrade --name groot-marketplace --provider claude' "$test_root/fury.log"
  cmp -s .agents/hooks/sync-marketplace.sh "$source_dir/assets/common/hooks/sync-marketplace.sh"
  cmp -s .agents/hooks/check-harness-consistency.sh "$source_dir/assets/stacks/go/hooks/check-harness-consistency.sh"
  cmp -s .agents/hooks/pre-tool-use.md "$source_dir/assets/stacks/go/hooks/pre-tool-use.md"
  cmp -s .agents/shared/asset.md "$source_dir/assets/common/shared/asset.md"
  [ -L .claude/shared/asset.md ]
  [ "$(readlink .claude/shared/asset.md)" = "../../.agents/shared/asset.md" ]
  cmp -s .agents/rules/coding-style.md "$source_dir/assets/stacks/go/rules/coding-style.md"
  cmp -s .agents/agents/security-scanner.md "$source_dir/assets/stacks/go/agents/security-scanner.md"
  cmp -s .agents/commands/review-pr.md "$source_dir/assets/stacks/go/commands/review-pr.md"
  grep -Fq '# Fury deploy' .agents/skills/fury-deploy/SKILL.md
  adapter_mode="$(python3 -c 'import os, stat, sys; print(format(stat.S_IMODE(os.stat(sys.argv[1]).st_mode), "o"))' .agents/skills/fury-deploy/SKILL.md)"
  [ "$adapter_mode" = "644" ]
  claude_adapter_mode="$(python3 -c 'import os, stat, sys; print(format(stat.S_IMODE(os.stat(sys.argv[1]).st_mode), "o"))' .claude/skills/fury-deploy/SKILL.md)"
  [ "$claude_adapter_mode" = "644" ]
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
    --stack frontend --skill-dir "$skill_dir" --provider claude

  [ "$status" -eq 0 ]
  grep -Eq 'agent-ready-sync\.[^ ]+ \.agents/hooks/sync-marketplace\.sh$' "$mv_log"
}

@test "sync hook creates new managed assets through atomic rename" {
  source_dir="$test_root/agent-ready-setup"
  mv_log="$test_root/mv.log"
  mkdir -p \
    "$source_dir/assets/common/hooks" \
    "$source_dir/assets/codex" \
    "$source_dir/assets/stacks/go/hooks" \
    "$source_dir/scripts"
  touch "$source_dir/SKILL.md"
  cp "$skill_dir/assets/common/hooks/sync-marketplace.sh" \
    "$source_dir/assets/common/hooks/sync-marketplace.sh"
  cp "$skill_dir/scripts/asset-sync-common.sh" "$source_dir/scripts/asset-sync-common.sh"
  cp "$skill_dir/scripts/merge-managed-settings.py" "$source_dir/scripts/merge-managed-settings.py"
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
      --provider claude --stack go

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
      --provider claude --stack go

  [ "$status" -eq 0 ]
  grep -Fq -- "Sync hook updated; restarting with latest version." <<< "$output"
  grep -Fq -- "Local managed asset projection completed for go." <<< "$output"
  [ ! -e .agents/.agent-ready-assets.lock ]
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
      --provider claude --stack go

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
      --provider claude --stack go

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
      --provider claude --stack go

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

  run_bootstrap frontend

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
      --provider claude

  [ "$status" -ne 0 ]
  [ ! -e "$bootstrap_log" ]
}

@test "common marketplace assets have no stack duplicates" {
  [ -f "$skill_dir/assets/common/settings.json" ]
  [ -f "$skill_dir/assets/common/hooks/sync-marketplace.sh" ]
  [ -f "$skill_dir/scripts/asset-sync-common.sh" ]
  [ -f "$skill_dir/scripts/merge-managed-settings.py" ]

  for stack in frontend node java go; do
    [ ! -e "$skill_dir/assets/stacks/$stack/settings.json" ]
    [ ! -e "$skill_dir/assets/stacks/$stack/hooks/sync-marketplace.sh" ]
  done
}
