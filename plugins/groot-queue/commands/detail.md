---
description: Muestra detalle completo de un ticket SSHP con clasificación, urgencia y sugerencia de solución.
argument-hint: SSHP-XXXXXX
---

Leé y aplicá `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/knowledge/config/command-entrypoint.md` para el subcomando canónico `detail`, los argumentos `$ARGUMENTS` y el provider `claude`.

Solo si el entrypoint habilita la ejecución, leé y seguí literalmente `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/subcommands/detail.md`, aplicándolo a `$ARGUMENTS` y conservando el estado combinado de readiness validado cuando corresponda.
