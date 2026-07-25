---
description: Detecta tickets vencidos y por vencer, agrupa por responsable y envía resumen por Slack DM. Soporta --dry-run.
argument-hint: [--dry-run]
---

Leé y aplicá `~/.claude/skills/groot-queue/knowledge/config/command-entrypoint.md` para el subcomando canónico `alerts`, los argumentos `$ARGUMENTS` y el provider `claude`.

Solo si el entrypoint habilita la ejecución, leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/alerts.md`, aplicándolo a `$ARGUMENTS` y conservando el resultado validado de Grid cuando corresponda.
