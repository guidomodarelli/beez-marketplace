# Review PR — Frontend

Run a full review of the current PR by orchestrating all specialized agents in sequence. Each agent focuses on its domain — this command consolidates the results.

## Steps

### 1. Get the diff

```bash
gh pr diff
```

If no PR is open, use `git diff main...HEAD`.

### 2. Run agents in sequence

Execute each agent against the diff. Collect findings before reporting.

| Agent | File | Trigger condition |
|-------|------|-------------------|
| Security scanner | `.claude/agents/security-scanner.md` | Always |
| Accessibility reviewer | `.claude/agents/a11y-reviewer.md` | Always |
| Performance analyzer | `.claude/agents/perf-analyzer.md` | Always |
| Test reviewer | `.claude/agents/test-reviewer.md` | Diff includes `*.spec.*` or `__tests__/` |
| Lint reviewer | `.claude/agents/lint-reviewer.md` | Diff includes `.tsx?` or `.jsx?` |

### 3. Consolidate and report

Present a single unified report using this structure:

```
## PR Review — [branch name]

### 🔴 Blocking
<!-- Critical security vulnerabilities, WCAG AA violations, lint errors -->
- [agent] [file:line] Issue — Fix: ...

### 🟡 Recommended
<!-- Non-blocking improvements from any agent -->
- [agent] [file:line] Suggestion.

### 🟢 Clean
<!-- Domains with no findings -->
- Security: clean
- Accessibility: clean
- ...

### Coverage note
<!-- Only if test-reviewer found missing coverage -->
- Missing tests for: ...
```

## Notes

- Blocking issues must be resolved before merging.
- If `meli_appsec_codeguard` MCP is unavailable, note it in the Security section and continue with the rest of the review.
- If `frontender-web-mcp` MCP is unavailable, note it in the Accessibility section and proceed with the static checklist.
