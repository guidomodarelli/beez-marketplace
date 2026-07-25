---
description: Muestra el banner de bienvenida con la versión y el catálogo de comandos disponibles con hints de uso.
---

Si `$ARGUMENTS` contiene el token exacto `--help` o `-h`, leé `start.md` y respondé su ayuda sin ejecutar tools.

En otro caso, tratá este wrapper bare como `start`: antes de leer el subcomando, leé y aplicá `~/.claude/skills/groot-queue/knowledge/config/grid-sharing-preflight.md`. Ejecutá el checker con provider `claude`; si existe `GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE`, pasalo mediante `--reuse-result` para que el checker lo valide. Continuá solo con exit code `0` y JSON `ok: true`, y conservá ese resultado validado durante toda la invocación sin repetir el gate.

Luego leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/start.md`, aplicándolo a `$ARGUMENTS`.
