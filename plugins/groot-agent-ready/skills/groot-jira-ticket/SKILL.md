---
name: groot-jira-ticket
type: skill
description: Crea o actualiza un ticket Jira (parent + subtasks) para trabajo en un repo de Kraken. Sin valores hardcodeados — lee la config del proyecto desde memoria, archivo o usuario.
tags: [jira, groot, ticket, subtask]
saved-by: gmodarelli
saved-at: 2026-06-23
---

# Kraken JIRA Ticket

Create or update a ticket in a Jira project for work done in a Kraken repository.

> **Prerequisite:** This skill requires the [Atlassian MCP server](https://github.com/sooperset/mcp-atlassian) installed and authenticated with your Atlassian account. It uses `createJiraIssue`, `editJiraIssue`, `getJiraIssue`, `getTransitionsForJiraIssue`, and `transitionJiraIssue` tools from that server.

> **NEVER run `git push` or any git upload command during this skill.**
> Ticket management is independent of repository state.

---

## Step 1 — Load project config

Variables y custom fields definidos en `references/constants.md` — leer ese archivo antes de continuar.

**Auto-detect `{{BASE_BRANCH}}`:**

```bash
for b in develop master main; do git show-ref --verify --quiet "refs/heads/$b" && { BASE_BRANCH=$b; break; }; done
```

**Load project config variables.** Try each source in order; stop at the first that yields all required values:

1. **`.env.local`** in the project root:
   ```bash
   cat .env.local 2>/dev/null
   ```
   Parse `KEY=value` lines — see `references/constants.md` for the expected variable names.

2. **Memory**: `search_episodic_memories(query="jira config <repo-name>")`

3. **Ask the user** for each missing field (ver tabla en `references/constants.md`).

After resolving all values, persist any new or updated values to `.env.local`. Repeat for each `JIRA_*` key:

```bash
# Example for JIRA_CLOUD_ID — repeat for every key:
grep -q "^JIRA_CLOUD_ID=" .env.local 2>/dev/null \
  && sed -i.bak "s|^JIRA_CLOUD_ID=.*|JIRA_CLOUD_ID=<value>|" .env.local && rm -f .env.local.bak \
  || echo "JIRA_CLOUD_ID=<value>" >> .env.local
```

Keys to persist: `JIRA_CLOUD_ID`, `JIRA_PROJECT_KEY`, `JIRA_LABEL`, `JIRA_ASSIGNEE_ID`, `JIRA_SUMMARY_PREFIX`, `JIRA_FIELD_QUARTERS`, `JIRA_FIELD_START_DATE`.

Ensure `.env.local` is gitignored:

```bash
grep -qxF ".env.local" .gitignore 2>/dev/null || echo ".env.local" >> .gitignore
```

**Derive the quarter from the system date:**

```bash
date +"%m %Y"
```

| Month | Quarter |
|---|---|
| 01 – 03 | Q1 |
| 04 – 06 | Q2 |
| 07 – 09 | Q3 |
| 10 – 12 | Q4 |

Example: month `06`, year `2026` → `Q2/26`. Use the last two digits of the year.

Before creating or updating issues, resolve the JIRA option id for that quarter:

1. Fetch issue metadata / edit metadata for the project issue type being created or updated.
2. Read `{{FIELD_QUARTERS}}` (`Quarters`) allowed values.
3. Select the option whose `value` equals the derived quarter.
4. Set `{{FIELD_QUARTERS}}` with the option object:

```json
[{ "id": "<allowed-value-id>", "value": "<Q derived from system date>" }]
```

Do not use `[{ "name": "<quarter>" }]`; JIRA ignores that shape for this field.

---

## Step 2 — Check for an existing ticket

Search memory for a recent ticket on the same branch or feature:

```
search_episodic_memories(query="jira ticket <branch-or-feature-name> <PROJECT_KEY> kraken")
```

- If a ticket already exists and its description is **incomplete or outdated**, update it with
  `editJiraIssue` — do not create a duplicate.
- If no ticket exists, proceed to create one.

---

## Step 3 — Gather the git diff

Run in parallel:

```bash
git log {{BASE_BRANCH}}..HEAD --oneline   # to understand scope — do NOT copy into the ticket
git diff {{BASE_BRANCH}}..HEAD --stat
grep -E '"[a-z-]+":\s*"[0-9]' package.json | head -20  # read real dependency versions
```

Always read version numbers from `package.json` directly — never copy them from commit messages.

Then read the key changed files to understand what was built. Focus on:
- `view.js` / `controller.js` — new UI surfaces, permission flags, conditional renders
- `styles.scss` — new CSS classes and layout changes
- `i18n/*/messages.po` — new user-facing labels
- `*.spec.js` — test coverage added

---

## Step 4 — Build the ticket

### Summary format

```
{{SUMMARY_PREFIX}} <concise imperative description of the main change>
```

Example: `[auth-admin-fe] Add corporate information accordion to userSharedDetail sidebar`

### Description structure (markdown)

```markdown
## Overview
<1–2 sentence summary of what changed and why>

---

## Changes

### <Area 1> (e.g. Desktop sidebar, Mobile panel, Corporate accordion…)
- <bullet per meaningful change>

### <Area 2>
- …

### Tests
- <what test coverage was added or updated>
```

Keep bullets precise and technical. No filler. Do **not** include a list of commits — the description must describe *what* was built, not the git history.

---

## Step 5 — Create or update the ticket

### Create

```
createJiraIssue(
  cloudId:             "{{CLOUD_ID}}",
  projectKey:          "{{PROJECT_KEY}}",
  issueTypeName:       "Task",
  summary:             "{{SUMMARY_PREFIX}} …",
  description:         "…",
  contentFormat:       "markdown",
  assignee_account_id: "{{ASSIGNEE_ID}}",
  additional_fields: {
    "labels":              ["{{LABEL}}"],
    "{{FIELD_QUARTERS}}":  [{"id": "<quarter option id>", "value": "<Q derived from system date>"}],
    "{{FIELD_START_DATE}}": "YYYY-MM-DD"   ← start date, usually today's system date for new tickets
  }
)
```

### Update (if ticket already exists)

Go directly to **Step 7** — do not edit the ticket here.

---

## Step 6 — Create subtasks (new tickets only)

After creating the parent ticket, identify the natural work units from the diff and create
one subtask per area. Typical split for Kraken repos:

- One subtask per major UI surface or feature area.
- One subtask for dependency bumps if any.
- One subtask for tests covering all the above.

Each subtask must inherit **the same labels, quarter, and start date** as the parent:

```
createJiraIssue(
  cloudId:             "{{CLOUD_ID}}",
  projectKey:          "{{PROJECT_KEY}}",
  issueTypeName:       "Sub-task",
  parent:              "{{PROJECT_KEY}}-XXXX",
  summary:             "<concise imperative title>",
  description:         "…",
  contentFormat:       "markdown",
  assignee_account_id: "{{ASSIGNEE_ID}}",
  additional_fields: {
    "labels":              ["{{LABEL}}"],
    "{{FIELD_QUARTERS}}":  [{"id": "<quarter option id>", "value": "<Q derived from system date>"}],
    "{{FIELD_START_DATE}}": "YYYY-MM-DD"
  }
)
```

Create all subtasks in parallel.

---

## Step 7 — Update existing ticket (update path only)

### 7a — Fetch current state in parallel

```
getJiraIssue({{CLOUD_ID}}, parentKey)
getJiraIssue({{CLOUD_ID}}, subtask1Key)
getJiraIssue({{CLOUD_ID}}, subtask2Key)
…
```

### 7b — Re-read the diff

Re-run Step 3. The code is the source of truth — not what was previously in JIRA.

### 7c — Compare and identify drift

| Element | What to check |
|---|---|
| Parent title | Still accurate? Reflects the full scope of the branch? |
| Parent description | All change areas covered? No outdated bullets? No commit list? |
| Subtask titles | Each title still maps to a real, self-contained work unit? |
| Subtask descriptions | Bullets match actual implementation? No stale details? |
| Coverage | Are there work areas in the diff NOT covered by any existing subtask? |

### 7d — Apply updates in parallel

```
editJiraIssue({{CLOUD_ID}}, parentKey,   fields: { summary: "…", description: "…" })
editJiraIssue({{CLOUD_ID}}, subtask1Key, fields: { summary: "…", description: "…" })
editJiraIssue({{CLOUD_ID}}, subtask2Key, fields: { summary: "…", description: "…" })
…
```

### 7e — Create missing subtasks

If the diff contains work areas not covered by any existing subtask, create the missing ones
using the same fields as Step 6.

---

## Step 8 — Validate parent and subtasks

After creating or updating, fetch every issue and verify:

- `labels` contains `{{LABEL}}`
- `{{FIELD_QUARTERS}}` contains the derived quarter value
- `{{FIELD_START_DATE}}` contains the expected start date

If any field is missing, patch the affected issue before closing the task.

---

## Step 9 — Transition to In Progress (new tickets only)

```
getTransitionsForJiraIssue({{CLOUD_ID}}, issueIdOrKey)  →  find "In Progress" transition id
transitionJiraIssue({{CLOUD_ID}}, issueIdOrKey, transitionId)
```

Skip when updating an existing ticket already in progress.

---

## Step 10 — Save to memory

After a successful create or update:

- **If no entry exists** — call `store_note` with:
  - `title`: `"Ticket JIRA <KEY> para <feature>"`
  - `result`: `"Ticket <KEY> created|updated. Summary: … Subtasks: {{PROJECT_KEY}}-XXXX, … Status: In Progress."`
  - `project`: `"<repo-name>"`
  - `tags`: `["feature", "change"]`

- **If an entry already exists** — update it with the new summary, subtask keys, and status.

---

## Rules

- **NEVER** run `git push`, `git push --force`, or any git upload command.
- Do not create a duplicate if a ticket already exists — update it instead.
- `{{LABEL}}` is mandatory for every ticket.
- `{{FIELD_QUARTERS}}` must always be set; derive it from `date +"%m %Y"` — never from memory.
- Description must be in **English** (ticket body).
- On update: fetch parent + all subtasks before editing — never update from memory alone.
- On update: run all `editJiraIssue` calls in parallel.
- On update: only patch fields that actually changed.
