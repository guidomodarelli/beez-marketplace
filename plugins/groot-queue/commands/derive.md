---
description: Deriva uno o más tickets SSHP al equipo correspondiente: detecta la regla R-DER que aplica y, si hay MCP Atlassian compatible, postea nota interna y transiciona el estado en Jira. Acepta múltiples keys separadas por espacios o comas.
argument-hint: SSHP-XXXXXX [SSHP-YYYYYY ...]
---

Si `$ARGUMENTS` contiene el token exacto `--help` o `-h`, leé el subcomando y respondé su ayuda sin ejecutar tools.

En otro caso, antes de leer el subcomando, leé y aplicá `~/.claude/skills/groot-queue/knowledge/config/grid-sharing-preflight.md`. Ejecutá el checker con provider `claude`; si existe `GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE`, pasalo mediante `--reuse-result` para que el checker lo valide. Continuá solo con exit code `0` y JSON `ok: true`, y conservá ese resultado validado durante toda la invocación sin repetir el gate.

Luego leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/derive.md`, aplicándolo a `$ARGUMENTS`.
