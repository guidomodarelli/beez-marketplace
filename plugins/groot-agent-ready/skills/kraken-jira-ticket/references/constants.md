# Constants — kraken-jira-ticket

Variables requeridas por la skill. Cargar en Step 1 desde memoria, `.jira-config.json` o preguntando al usuario.

## Project config

| Variable | Description | How to find it |
|---|---|---|
| `{{CLOUD_ID}}` | Atlassian cloud UUID | URL de Jira: `https://<org>.atlassian.net` → panel de administración |
| `{{PROJECT_KEY}}` | Jira project key | Prefijo de los tickets, e.g. `SGP1` |
| `{{LABEL}}` | Label aplicado a todos los tickets | Acordado por el equipo, e.g. `kraken-user-role` |
| `{{ASSIGNEE_ID}}` | Atlassian account ID del assignee por defecto | Perfil de Jira del usuario |
| `{{SUMMARY_PREFIX}}` | Prefijo de los títulos de tickets | Derivado del nombre del repo: `fury_kraken-auth-admin-fe` → `[auth-admin-fe]` |

## Custom fields

| Variable | Field ID | Description |
|---|---|---|
| `{{FIELD_QUARTERS}}` | `customfield_18353` | Quarter al que pertenece el ticket |
| `{{FIELD_START_DATE}}` | `customfield_12410` | Fecha de inicio del ticket |

## Auto-detected (no config needed)

| Variable | How |
|---|---|
| `{{BASE_BRANCH}}` | `for b in develop master main; do git show-ref --verify --quiet "refs/heads/$b" && { BASE_BRANCH=$b; break; }; done` |
