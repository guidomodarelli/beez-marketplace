---
description: Verifica dependencias, integraciones, permisos y Grid Sharing para usar la skill groot-queue.
---

Si `$ARGUMENTS` contiene el token exacto `--help` o `-h`, respondé sin ejecutar tools ni leer archivos adicionales: `setup` verifica ACLI, MCPs, permisos, TEAM y el preflight completo de Grid Sharing; no instala ni modifica nada sin autorización explícita.

`setup` está exento del gate global. Sin ejecutar el checker desde este wrapper, leé y seguí literalmente `~/.claude/skills/groot-queue/subcommands/setup.md`, que realiza su propio diagnóstico completo, aplicándolo a `$ARGUMENTS`.
