---
description: Guarda la solución aplicada a un ticket SSHP en la knowledge base para mejorar futuros diagnósticos.
argument-hint: SSHP-XXXXXX <descripción>
---

Leé y aplicá `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/knowledge/config/command-entrypoint.md` para el subcomando canónico `save`, los argumentos `$ARGUMENTS` y el provider `claude`.

Solo si el entrypoint habilita la ejecución, leé y seguí literalmente `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/subcommands/save.md`, parseando `$ARGUMENTS` como `<ticket-key> <descripción>` y conservando el estado combinado de readiness validado cuando corresponda.
