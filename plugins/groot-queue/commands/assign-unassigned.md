---
description: Asigna en Jira todos los tickets sin responsable repartiéndolos de forma equitativa sobre el TEAM configurado.
---

Si `$ARGUMENTS` contiene el token exacto `--help` o `-h`, leé el subcomando y respondé su ayuda sin ejecutar tools.

En otro caso, antes de leer el subcomando, leé y aplicá `~/.claude/skills/groot-queue/knowledge/config/grid-sharing-preflight.md`. Ejecutá el checker con provider `claude`; si existe `GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE`, pasalo mediante `--reuse-result` para que el checker lo valide. Continuá solo con exit code `0` y JSON `ok: true`, y conservá ese resultado validado durante toda la invocación sin repetir el gate.

Luego leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/assign-unassigned.md`, aplicándolo a `$ARGUMENTS`.
