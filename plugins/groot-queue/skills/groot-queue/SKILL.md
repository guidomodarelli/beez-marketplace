---
name: groot-queue
description: "Monitorea la cola de soporte [Core] - Groot (SSHP). Lista, clasifica, analiza urgencia, sugiere soluciones, alerta por Slack y asigna tickets sin responsable usando round-robin. Usar cuando el usuario invoque /groot-queue o pregunte por tickets de soporte de Groot."
---

# Groot Queue Monitor

**Propósito**: Monitorear y gestionar la cola de soporte "[Core] - Groot" del proyecto Jira SSHP. Read-only salvo el subcomando `assign-unassigned`, que asigna tickets en Jira usando round-robin.

Esta skill funciona como **índice + dispatcher** de subcomandos. La lógica concreta de cada acción vive en `subcommands/<nombre>.md` (single source of truth, compartido entre Claude Code y Codex).

---

## Dispatcher (importante)

Al activarse la skill, parsear el primer token del input del usuario después de `/groot-queue` como subcomando:

- Si el subcomando coincide con uno de la tabla → **leer `subcommands/<subcomando>.md` y seguir literalmente sus instrucciones**, pasando el resto del input como argumentos.
- Si el subcomando no existe o no se provee → mostrar la tabla de subcomandos de abajo y la sección "Inicialización del entorno de desarrollo".

Ejemplos:

| Input del usuario | Archivo a leer | Argumentos |
|-------------------|----------------|------------|
| `/groot-queue setup` | `subcommands/setup.md` | — |
| `/groot-queue detail SSHP-1234567` | `subcommands/detail.md` | `SSHP-1234567` |
| `/groot-queue save SSHP-1234567 cambio de lider corregido` | `subcommands/save.md` | `SSHP-1234567 cambio de lider corregido` |
| `/groot-queue` | (mostrar índice) | — |

Path absoluto (post-install): `~/.claude/skills/groot-queue/subcommands/<nombre>.md`.

**Nota para Claude Code**: si el usuario invoca `/groot-queue:<nombre>` (sintaxis de slash command de plugin), Claude carga directamente `commands/<nombre>.md` del plugin — un wrapper que apunta al mismo `subcommands/<nombre>.md`. La fuente de verdad es la misma; el dispatcher de esta skill solo se ejecuta cuando se entra por la skill (Codex o Claude tipeando `/groot-queue` sin `:`).

---

## Subcomandos disponibles

| Subcomando | Acción |
|------------|--------|
| `setup` | Verificar e instalar dependencias necesarias (ACLI, Slack MCP, permisos, estado round-robin) |
| `list` | Listar todos los incidentes abiertos |
| `classify` | Clasificar y agrupar por tipo de problema + urgencia |
| `detail SSHP-XXXXXX` | Detalle completo de un ticket con clasificación y sugerencia |
| `solve SSHP-XXXXXX` | Sugerir solución basada en runbooks + análisis |
| `alerts` | Detectar tickets en riesgo de SLA y notificar por Slack DM |
| `stats` | Estadísticas agregadas de la cola |
| `assign-unassigned` | Asignar en Jira todos los tickets sin responsable usando round-robin |
| `save SSHP-XXXXXX <desc>` | Guardar la solución aplicada a un ticket en la knowledge base |
| `add-rule` | Agregar una nueva regla de triage a la knowledge base |
| _(sin argumento)_ | Mostrar esta ayuda + inicialización del entorno de desarrollo |

---

## Base de conocimiento

Toda la lógica de negocio (reglas de triage, runbooks procedurales, lógica de clasificación y casos concretos) vive en la **knowledge base** bundleada con la skill:

```
~/.claude/skills/groot-queue/
├── SKILL.md             ← Este archivo (índice + dispatcher)
├── subcommands/         ← Lógica de cada subcomando (single source of truth)
│   ├── setup.md
│   ├── list.md
│   ├── classify.md
│   ├── detail.md
│   ├── solve.md
│   ├── alerts.md
│   ├── stats.md
│   ├── assign-unassigned.md
│   ├── save.md
│   └── add-rule.md
└── knowledge/
    ├── classification.md   ← JQL base + Dimensión 1 + Dimensión 2 + mapeo a solutions/
    ├── triage-rules.md     ← Reglas R-DESC / R-DER / R-FIX + algoritmo de triage
    ├── runbooks.md         ← Runbooks procedurales por categoría
    ├── solutions/          ← Casos concretos resueltos, por categoría
    ├── apis/               ← Docs de endpoints (a futuro)
    └── roundrobin-state.json   ← Estado persistente del round-robin (creado por setup)
```

Los subcomandos **deben leer estos archivos** cada vez que los necesiten (sin cachear). Si cualquiera de estos archivos no existe, avisar al usuario y seguir con los datos mínimos.

---

## Equipo para Round-Robin

Lista de miembros para la rotación. Editá esta lista para cambiar el equipo. El campo `email` se usa directamente en `assign-unassigned` — no se deriva del username:

```
TEAM:
  - username: frgonzalez
    email: francisco.gonzalez@mercadolibre.com
    name: Francisco Gonzalez
  - username: maescobar
    email: matias.escobar@mercadolibre.com
    name: Matias Joel Escobar
  - username: jgibelli
    email: julian.gibelli@mercadolibre.com
    name: Julian Nicolas Gibelli
  - username: nicogutierre
    email: nicolasj.gutierrez@mercadolibre.com
    name: Julio Nicolas Gutierrez
  - username: hfurs
    email: hectoranibal.furs@mercadolibre.com
    name: Hector Furs
  - username: gsosa
    email: gustavo.sosa@mercadolibre.com
    name: Gustavo Gabriel Sosa Sotelo
  - username: levillanueva
    email: leonardo.villanueva@mercadolibre.com
    name: Leonardo Manuel Villanueva
  - username: gmodarelli
    email: guido.modarelli@mercadolibre.com
    name: Guido Modarelli
```

El orden define el turno. El índice actual se persiste en:
`~/.claude/skills/groot-queue/knowledge/roundrobin-state.json`

---

## Cuándo Usar

- Usuario invoca `/groot-queue <subcomando>` (Codex) o `/groot-queue:<subcomando>` (Claude Code).
- Usuario pregunta por tickets de soporte de Groot, la cola de Groot, incidentes pendientes.

---

## Inicialización del entorno de desarrollo

- [ ] **Primer paso**: tener instalado acli:
   ```bash
   brew tap atlassian-labs/acli
   brew install acli
   ```
- [ ] **Segundo paso**: configurar acli con tus credenciales de Atlassian:
   ```bash
   acli jira auth login --web
   ```
   y seleccionar https://mercadolibre.atlassian.net.
- [ ] **Tercer paso**: correr el subcomando `setup` para verificar e instalar el resto del entorno.

---

## Reglas globales

- **WRITE CONTROLADO**: el subcomando `assign-unassigned` escribe en Jira (transición + asignación). `save` y `add-rule` escriben en la knowledge base local. Todos los demás subcomandos son read-only.
- **La base de conocimiento vive fuera de los subcomandos**. No duplicar runbooks ni reglas: siempre referenciar `classification.md` / `triage-rules.md` / `runbooks.md` / `solutions/` por path.
- Siempre mostrar el link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`.
- Las respuestas deben ser en español.
