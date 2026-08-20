---
description: "Descarta uno o más tickets SSHP que no corresponden a Groot Soporte: detecta la regla R-DESC que aplica y, si hay MCP Atlassian compatible, postea el comentario sugerido (público) y cierra el ticket. Acepta múltiples keys separadas por espacios o comas."
argument-hint: "SSHP-XXXXXX [SSHP-YYYYYY ...]"
---

Leé y aplicá `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/knowledge/config/command-entrypoint.md` para el subcomando canónico `discard`, los argumentos `$ARGUMENTS` y el provider `claude`.

Solo si el entrypoint habilita la ejecución, leé y seguí literalmente `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/subcommands/discard.md`, aplicándolo a `$ARGUMENTS` y conservando el estado combinado de readiness validado cuando corresponda.
