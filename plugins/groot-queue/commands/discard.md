---
description: Descarta uno o más tickets SSHP que no corresponden a Groot Soporte: detecta la regla R-DESC que aplica y, si hay MCP Atlassian compatible, postea el comentario sugerido (público) y cierra el ticket. Acepta múltiples keys separadas por espacios o comas.
argument-hint: SSHP-XXXXXX [SSHP-YYYYYY ...]
---

Si `$ARGUMENTS` contiene el token exacto `--help` o `-h`, leé el subcomando y respondé su ayuda sin ejecutar tools.

En otro caso, antes de leer el subcomando, leé y aplicá `~/.claude/skills/groot-queue/knowledge/config/grid-sharing-preflight.md`. Ejecutá el checker con provider `claude`; si existe `GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE`, pasalo mediante `--reuse-result` para que el checker lo valide. Continuá solo con exit code `0` y JSON `ok: true`, y conservá ese resultado validado durante toda la invocación sin repetir el gate.

Luego leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/discard.md`, aplicándolo a `$ARGUMENTS`.
