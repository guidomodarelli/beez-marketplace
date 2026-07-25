---
description: Analiza tickets cerrados de la cola SSHP para extraer patrones y alimentar la knowledge base (reglas de triage y soluciones).
argument-hint: [--limit N] [--since YYYY-MM-DD] [--force]
---

Si `$ARGUMENTS` contiene el token exacto `--help` o `-h`, leé el subcomando y respondé su ayuda sin ejecutar tools.

En otro caso, antes de leer el subcomando, leé y aplicá `~/.claude/skills/groot-queue/knowledge/config/grid-sharing-preflight.md`. Ejecutá el checker con provider `claude`; si existe `GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE`, pasalo mediante `--reuse-result` para que el checker lo valide. Continuá solo con exit code `0` y JSON `ok: true`, y conservá ese resultado validado durante toda la invocación sin repetir el gate.

Luego leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/analyze-history.md`, aplicándolo a `$ARGUMENTS`.
