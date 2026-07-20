---
name: groot-queue
description: "Monitorea la cola de soporte [Core] - Groot (SSHP). Lista, clasifica, analiza urgencia, sugiere soluciones, alerta por Slack, asigna tickets sin responsable y analiza históricos con analyze-history. Usar cuando el usuario invoque /groot-queue o pregunte por tickets de soporte de Groot."
---

# Groot Queue Monitor

**Propósito**: Monitorear y gestionar la cola de soporte "[Core] - Groot" del proyecto Jira SSHP. Read-only salvo los subcomandos `assign-unassigned`, que reparte tickets sin responsable de forma equitativa entre el TEAM (stateless); `derive`, que postea nota interna y transiciona estado con MCP Atlassian; `discard`, que postea comentario público y cierra tickets que no corresponden a Groot Soporte; `save` y `add-rule`, que escriben en la knowledge base local; `backfill-guides`, que postea guías de resolución en tickets abiertos ya asignados sin guía; y `analyze-history`, que analiza tickets cerrados históricos, escribe en la knowledge base y agrega labels de estado en Jira.

Esta skill funciona como **índice + dispatcher** de subcomandos. La lógica concreta de cada acción vive en `subcommands/<nombre>.md` (single source of truth, compartido entre Claude Code y Codex).

---

## Resolución De Paths

Antes de leer o escribir archivos del skill, resolver una variable conceptual `SKILL_DIR`:

1. Si existe la variable de entorno `GROOT_QUEUE_SKILL_DIR`, usar ese valor.
2. Si no existe y está disponible `~/.codex/skills/groot-queue/SKILL.md`, usar `~/.codex/skills/groot-queue`.
3. Si no existe y está disponible `~/.claude/skills/groot-queue/SKILL.md`, usar `~/.claude/skills/groot-queue`.
4. Si se está trabajando dentro del repositorio marketplace, usar `plugins/groot-queue/skills/groot-queue`.

En los subcomandos, `$SKILL_DIR` refiere a ese directorio resuelto. No asumir un path exclusivo de Claude o Codex. Si se usa `GROOT_QUEUE_SKILL_DIR` desde `.zshrc`, debe estar exportada en el entorno que inicia el agente; los shells `bash` invocados después solo heredan variables ya exportadas. Cuando un snippet Bash use `$SKILL_DIR` y la variable no esté en el entorno, definirla en la misma llamada Bash con el path resuelto.

---

## Dispatcher (importante)

Al activarse la skill, **primero** chequear el modo de ejecución con Bash:

```bash
echo "${GROOT_QUEUE_DIRECT:-}"
```

### Modo script (output vacío — invocación directa del usuario)

Parsear el subcomando y argumentos del input, luego ejecutar vía Bash:

```bash
run-groot-queue <subcomando> [args...]
```

Mostrar el output al usuario. El script gestiona provider, modelo y effort automáticamente con los defaults correctos (claude-sonnet-4.6 + high para copilot/claude, gpt-5.4-mini + high para codex).

Si `run-groot-queue` no está en PATH, buscar el script relativo al skill:

```bash
# Resolver path real del skill (sigue symlinks)
SKILL_REAL="$(python3 -c "import os; p='$SKILL_DIR'; print(os.path.realpath(p))" 2>/dev/null || realpath "$SKILL_DIR" 2>/dev/null || echo "$SKILL_DIR")"
bash "$SKILL_REAL/../../scripts/run-groot-queue.sh" <subcomando> [args...]
```

Si el input contiene `--help` o no hay subcomando → ejecutar `run-groot-queue start` (o `start --help`).

### Modo directo (output = `1` — spawneado por el script, evita recursión)

Leer `$SKILL_DIR/subcommands/<subcomando>.md` y seguir literalmente sus instrucciones, pasando el resto como argumentos. Si no hay subcomando → `subcommands/start.md`.

| Input del usuario | Subcomando | Argumentos |
|-------------------|-----------|------------|
| `/groot-queue start` | `start` | — |
| `/groot-queue detail SSHP-1234567` | `detail` | `SSHP-1234567` |
| `/groot-queue analyze-history --help` | `analyze-history` | `--help` |
| `/groot-queue` | `start` | — |

**Nota para Claude Code**: si el usuario invoca `/groot-queue:<nombre>` (sintaxis de slash command de plugin), Claude carga directamente `commands/<nombre>.md` — un wrapper que apunta al mismo `subcommands/<nombre>.md`. El dispatcher de esta skill solo se ejecuta cuando se entra por la skill (Codex o Claude tipeando `/groot-queue` sin `:`).

---

## Subcomandos disponibles

| Subcomando | Acción |
|------------|--------|
| `start` | Mostrar banner de bienvenida, versión y catálogo de comandos con hints de uso |
| `setup` | Verificar e instalar dependencias necesarias (ACLI, Atlassian MCP, Slack MCP, permisos) |
| `list` | Listar todos los incidentes abiertos |
| `classify` | Clasificar y agrupar por tipo de problema + urgencia |
| `detail SSHP-XXXXXX` | Detalle completo de un ticket con clasificación y sugerencia |
| `solve SSHP-XXXXXX` | Sugerir solución basada en runbooks + análisis |
| `alerts [--dry-run]` | Detectar tickets vencidos y por vencer, agrupar por responsable del TEAM y enviar un resumen por Slack DM a cada uno |
| `stats` | Estadísticas agregadas de la cola |
| `assign-unassigned` | Asignar en Jira todos los tickets sin responsable repartiéndolos de forma equitativa entre el TEAM (stateless) |
| `derive SSHP-XXXXXX` | Derivar un ticket al equipo correcto: detecta regla R-DER y, si hay MCP Atlassian compatible, postea nota interna y transiciona estado |
| `discard SSHP-XXXXXX` | Descartar un ticket que no corresponde a Groot Soporte: detecta regla R-DESC y, si hay MCP Atlassian compatible, postea comentario público y cierra el ticket |
| `save SSHP-XXXXXX <desc>` | Guardar la solución aplicada a un ticket en la knowledge base |
| `add-rule` | Agregar una nueva regla de triage a la knowledge base |
| `backfill-guides` | Postear guías de resolución (nota interna) en tickets abiertos y asignados que aún no tienen guía — backfill retroactivo idempotente |
| `analyze-history [--limit N] [--since YYYY-MM-DD] [--force]` | Analizar tickets cerrados históricos y extraer patrones para la knowledge base |
| _(sin argumento)_ | Ejecutar `start` (banner + catálogo de comandos) |

---

## Resumen Operativo De `analyze-history`

Este resumen existe para consultas rápidas de ayuda. Para ejecutar o explicar detalles no cubiertos acá, leer `subcommands/analyze-history.md`.

- Requiere MCP Atlassian para consultar tickets cerrados, leer changelog/comentarios y escribir labels. Si no está disponible, abortar con instrucciones para habilitar `https://mcp.atlassian.com/v1/mcp` y completar OAuth.
- Por defecto procesa como máximo `20` tickets. `--limit N` cambia ese máximo.
- Consulta tickets cerrados con JQL sobre `project = SSHP`, `Squad = Groot`, `type = Incident`, `statusCategory = Done`.
- La idempotencia vive en Jira: el JQL base incluye tickets sin labels con `labels IS EMPTY` y excluye tickets con `groot-kb-analyzed` o `groot-kb-manual-review`.
- `--force` permite re-analizar tickets con `groot-kb-analyzed`, pero los tickets con `groot-kb-manual-review` siguen excluidos.
- `--since YYYY-MM-DD` agrega un filtro de fecha al JQL: `updated >= "YYYY-MM-DD"`.
- Clasifica cada ticket cerrado como `DERIVADO`, `DESCARTADO` o `RESUELTO` usando la última transición de cierre del `changelog`, la resolución y el comentario clave previo a esa transición.
- Si no puede extraer el comentario clave, no hay visibilidad suficiente de notas internas o el desenlace es ambiguo, marca el ticket con `groot-kb-manual-review` y continúa.
- Las señales para reglas se derivan de `summary` y `description`; deben cubrir ES + PT + EN y partir del wording real del ticket.
- Si el usuario confirma materialización: `DESCARTADO` y `DERIVADO` delegan en `add-rule` para escribir `triage-rules.md` (`R-DESC` / `R-DER`) con campos pre-poblados; `RESUELTO` delega en `save` para crear una solución.
- El resumen final muestra conteos de procesados, materializados, descartados, saltados, manual review, reglas agregadas (`R-DESC` / `R-DER`) y soluciones guardadas.

---

## Base de conocimiento

Toda la lógica de negocio (reglas de triage, runbooks procedurales, lógica de clasificación y casos concretos) vive en la **knowledge base** bundleada con la skill:

```
$SKILL_DIR/
├── SKILL.md             ← Este archivo (índice + dispatcher)
├── subcommands/         ← Lógica de cada subcomando (single source of truth)
│   ├── start.md
│   ├── setup.md
│   ├── list.md
│   ├── classify.md
│   ├── detail.md
│   ├── solve.md
│   ├── alerts.md
│   ├── stats.md
│   ├── assign-unassigned.md
│   ├── derive.md
│   ├── discard.md
│   ├── save.md
│   ├── add-rule.md
│   └── analyze-history.md
└── knowledge/
    ├── classification.md   ← JQL base + Dimensión 1 + Dimensión 2 + mapeo a solutions/
    ├── triage-rules.md     ← Reglas R-DESC / R-DER / R-FIX + algoritmo de triage
    ├── runbooks.md         ← Runbooks procedurales por categoría
    ├── solutions/          ← Casos concretos resueltos, por categoría
    └── apis/               ← Docs de endpoints (a futuro)
```

Los subcomandos **deben leer estos archivos** cada vez que los necesiten (sin cachear). Si cualquiera de estos archivos no existe, avisar al usuario y seguir con los datos mínimos.

---

## Equipo para asignación

Lista de miembros entre los que se reparten los tickets. Editá esta lista para cambiar el equipo. El campo `email` se usa directamente en `assign-unassigned` — no se deriva del username:

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

El orden de la lista **no** define el turno: en cada corrida, `assign-unassigned` baraja el TEAM una sola vez (un shuffle aleatorio) y reparte los tickets siguiendo ese orden, sin repetir (si hay más tickets que miembros, repite el mismo orden barajado). La asignación **no persiste estado entre corridas** — usa un archivo scratch efímero (creado con `mktemp` y borrado al terminar) solo durante la ejecución, así la equidad no depende del orden en que cada miembro ejecute el comando ni de ninguna cache compartida.

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
- [ ] **Tercer paso**: habilitar el MCP de Atlassian en Claude Code:
   ```bash
   claude mcp add --transport http "Atlassian" https://mcp.atlassian.com/v1/mcp
   ```
   Luego ejecutar `/mcp` dentro de Claude Code y completar el flujo OAuth para `mercadolibre.atlassian.net`.
   Requerido para que `/groot-queue:derive` pueda ejecutar la transición "Derivar a otro equipo".
- [ ] **Cuarto paso**: correr el subcomando `setup` para verificar e instalar el resto del entorno.

---

## Reglas globales

- **WRITE CONTROLADO**: los subcomandos `assign-unassigned`, `derive` y `discard` pueden escribir en Jira (`assign-unassigned`: transición + asignación; `derive`: nota interna + transición de estado + labels de trazabilidad; `discard`: comentario público + transición de cierre + labels de trazabilidad — los tres requieren MCP Atlassian compatible). `save` y `add-rule` escriben en la knowledge base local. `analyze-history` escribe en la knowledge base local **y** agrega labels de estado (`groot-kb-analyzed` / `groot-kb-manual-review`) en los tickets de Jira (requiere MCP Atlassian). Todos los demás subcomandos son read-only.
- **La base de conocimiento vive fuera de los subcomandos**. No duplicar runbooks ni reglas: siempre referenciar `classification.md` / `triage-rules.md` / `runbooks.md` / `solutions/` por path.
- Siempre mostrar el link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`.
- Las respuestas deben ser en español.
