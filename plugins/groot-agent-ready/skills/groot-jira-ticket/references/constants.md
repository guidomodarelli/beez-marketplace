# Constants — groot-jira-ticket

Variables requeridas por la skill. Se leen desde `.env.local` en la raíz del proyecto (fuente primaria), memoria o preguntando al usuario.

## `.env.local` format

```dotenv
JIRA_CLOUD_ID=<atlassian-cloud-uuid>
JIRA_PROJECT_KEY=<project-key>
JIRA_LABEL=<label>
JIRA_ASSIGNEE_ID=<atlassian-account-id>
JIRA_SUMMARY_PREFIX=[<repo-suffix>]
JIRA_FIELD_QUARTERS=customfield_18353
JIRA_FIELD_START_DATE=customfield_12410
```

## Project config

| `.env.local` key | Skill variable | Description | How to find it |
|---|---|---|---|
| `JIRA_CLOUD_ID` | `{{CLOUD_ID}}` | Atlassian cloud UUID | `getAccessibleAtlassianResources` → campo `id` |
| `JIRA_PROJECT_KEY` | `{{PROJECT_KEY}}` | Jira project key | Prefijo de los tickets, e.g. `SGP1` |
| `JIRA_LABEL` | `{{LABEL}}` | Label aplicado a todos los tickets | Default: `kraken-user-role`. Sobreescribir en `.env.local` si el proyecto usa otro. |
| `JIRA_ASSIGNEE_ID` | `{{ASSIGNEE_ID}}` | Atlassian account ID del assignee por defecto | Auto-detectable — ver sección abajo |
| `JIRA_SUMMARY_PREFIX` | `{{SUMMARY_PREFIX}}` | Prefijo de los títulos de tickets | Auto-detectable — ver sección abajo |

## Custom fields

| `.env.local` key | Skill variable | Field ID | Description |
|---|---|---|---|
| `JIRA_FIELD_QUARTERS` | `{{FIELD_QUARTERS}}` | `customfield_18353` | Quarter al que pertenece el ticket |
| `JIRA_FIELD_START_DATE` | `{{FIELD_START_DATE}}` | `customfield_12410` | Fecha de inicio del ticket |

## Auto-detected (no config needed)

| Variable | How |
|---|---|
| `{{BASE_BRANCH}}` | `for b in develop master main; do git show-ref --verify --quiet "refs/heads/$b" && { BASE_BRANCH=$b; break; }; done` |
| `{{CLOUD_ID}}` | `getAccessibleAtlassianResources` → campo `id` |
| `{{ASSIGNEE_ID}}` | `atlassianUserInfo` → campo `account_id` |
| `{{SUMMARY_PREFIX}}` | `repo=$(basename $(git rev-parse --show-toplevel)); echo "[${repo#*-}]"` |
