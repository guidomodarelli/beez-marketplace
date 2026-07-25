---
description: Deriva uno o más tickets SSHP al equipo correspondiente: detecta la regla R-DER que aplica y, si hay MCP Atlassian compatible, postea nota interna y transiciona el estado en Jira. Acepta múltiples keys separadas por espacios o comas.
argument-hint: SSHP-XXXXXX [SSHP-YYYYYY ...]
---

Leé y aplicá `~/.claude/skills/groot-queue/knowledge/config/command-entrypoint.md` para el subcomando canónico `derive`, los argumentos `$ARGUMENTS` y el provider `claude`.

Solo si el entrypoint habilita la ejecución, leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/derive.md`, aplicándolo a `$ARGUMENTS` y conservando el estado combinado de readiness validado cuando corresponda.
