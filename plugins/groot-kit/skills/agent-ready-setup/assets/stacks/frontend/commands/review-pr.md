---
name: review-pr
description: Run a full review of the current PR by orchestrating the specialized review agents and consolidating their results. Use when asked to review a pull request.
---

# Review PR — Frontend

Run a full review of the current PR by orchestrating all specialized agents in sequence. Each agent focuses on its domain — this command consolidates the results.

## Steps

### 1. Get the diff

```bash
gh pr diff
```

If no PR is open, resolve remote default branch and compare against it:

```bash
BASE_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD)"
git diff "$BASE_BRANCH"...HEAD
```

If `origin/HEAD` is not configured locally, set it with `git remote set-head origin --auto` and rerun the fallback.

### 2. Run agents in sequence

Execute each agent against the diff. Collect findings before reporting.

| Agent | File | Trigger condition |
|-------|------|-------------------|
| Security scanner | `.agents/agents/security-scanner.md` | Always |
| Accessibility reviewer | `.agents/agents/a11y-reviewer.md` | Always |
| Performance analyzer | `.agents/agents/perf-analyzer.md` | Always |
| Test reviewer | `.agents/agents/test-reviewer.md` | Use the activation rules in `test-reviewer.md` |
| Lint reviewer | `.agents/agents/lint-reviewer.md` | Use the activation rules in `lint-reviewer.md` |

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
