---
description: "Analiza tickets cerrados de la cola SSHP para extraer patrones y alimentar la knowledge base (reglas de triage y soluciones)."
argument-hint: "[--limit N] [--since YYYY-MM-DD] [--force]"
---

Leé y aplicá `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/knowledge/config/command-entrypoint.md` para el subcomando canónico `analyze-history`, los argumentos `$ARGUMENTS` y el provider `claude`.

Solo si el entrypoint habilita la ejecución, leé y seguí literalmente `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/subcommands/analyze-history.md`, aplicándolo a `$ARGUMENTS` y conservando el estado combinado de readiness validado cuando corresponda.
