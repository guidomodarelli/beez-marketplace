# Session checkpoint

- Objetivo: ajustar catálogo visual de `groot-queue`, renombrar renderer y corregir evals fallidos.
- Decisiones: mantener marcador verde, eliminar violeta; usar `render-catalog.sh`; separar clasificación activa de automatización pendiente para `R-DER-12`; alinear assertions con contratos documentados.
- Archivos modificados: `evals/eval-config.json`, `knowledge/triage-rules.md`, `subcommands/classify.md`, `subcommands/start.md`, `scripts/render-catalog.sh`.
- Estado: skill válida; suite completa llegó a 38/39 antes de corregir assertion de fallback de versión; `start-command` pasó luego en corrida aislada. Casos PT, LMS e idempotencia pasan.
- Pendiente: commit/push solo si usuario lo solicita.
