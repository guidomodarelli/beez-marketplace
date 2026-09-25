# Lint Gate

A task that adds or modifies files is not complete until applicable project lint validation succeeds.

- Run the repository's configured lint command once at the end of the task, after all edits are done. Do not run it after every individual file change.
- The task is complete only when the lint command exits with code 0. Warnings do not block unless repository configuration says otherwise; errors do.
- Fix every lint error within the same task before closing it; do not leave lint errors for a follow-up.
- If the project has no configured linter, report `N/A` and do not add one only to satisfy this rule. If the lint command cannot run (for example, missing dependencies or environment limitations), report the reason and pending validation.
