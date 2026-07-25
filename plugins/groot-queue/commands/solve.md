---
description: Sugiere solución para un ticket SSHP basada en runbooks, casos previos y análisis del contexto.
argument-hint: SSHP-XXXXXX
---

Leé y aplicá `~/.claude/skills/groot-queue/knowledge/config/command-entrypoint.md` para el subcomando canónico `solve`, los argumentos `$ARGUMENTS` y el provider `claude`.

Solo si el entrypoint habilita la ejecución, leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/solve.md`, aplicándolo a `$ARGUMENTS` y conservando el estado combinado de readiness validado cuando corresponda.
