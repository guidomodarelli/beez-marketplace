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

1. Si existe `GROOT_QUEUE_SKILL_DIR` y contiene `SKILL.md`, usar ese valor.
2. Si Claude Code cargó el plugin y `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue/SKILL.md` existe, usar `${CLAUDE_PLUGIN_ROOT}/skills/groot-queue`.
3. Si `GROOT_QUEUE_ACTIVE_PROVIDER=codex` y `~/.codex/skills/groot-queue/SKILL.md` existe, usar `~/.codex/skills/groot-queue`.
4. Si `GROOT_QUEUE_ACTIVE_PROVIDER=claude` y `~/.claude/skills/groot-queue/SKILL.md` existe, usar `~/.claude/skills/groot-queue`.
5. Fuera del launcher, usar el directorio desde el cual el provider cargó esta skill; no seleccionar el árbol de otro provider por mera existencia.
6. Si se está trabajando dentro del repositorio marketplace, usar `plugins/groot-queue/skills/groot-queue`.

En los subcomandos, `$SKILL_DIR` refiere a ese directorio resuelto. No asumir un path exclusivo de Claude o Codex. Si se usa `GROOT_QUEUE_SKILL_DIR` desde `.zshrc`, debe estar exportada en el entorno que inicia el agente; los shells `bash` invocados después solo heredan variables ya exportadas. Cuando un snippet Bash use `$SKILL_DIR` y la variable no esté en el entorno, definirla en la misma llamada Bash con el path resuelto.

---

## Dispatcher (importante)

Al activarse la skill, aplicar este orden sin adelantar lecturas, tools ni acciones del subcomando.

### Paso 1 — Resolver comando y alias

Parsear el primer token después de `/groot-queue`. Si coincide con un alias, reemplazarlo por el subcomando canónico:

| Alias | Subcomando canónico |
|-------|---------------------|
| `cl` | `classify` |
| `ls` | `list` |
| `d` | `detail` |
| `s` | `solve` |
| `der` | `derive` |
| `dis` | `discard` |
| `aa` | `assign-unassigned` |
| `assign` | `assign-unassigned` |
| `ah` | `analyze-history` |
| `history` | `analyze-history` |
| `bf` | `backfill-guides` |
| `backfill` | `backfill-guides` |
| `ar` | `add-rule` |

Si el token resuelto no corresponde a un subcomando disponible, o si no hay token, resolver la invocación a `start`. La entrada vacía y la desconocida no son ayuda ni están exentas del gate.

### Paso 2 — Resolver provider y aplicar el entrypoint

Identificar el provider activo como `claude`, `codex` o `copilot`. Usar `GROOT_QUEUE_ACTIVE_PROVIDER` cuando el launcher lo haya definido con uno de esos valores; en otro caso usar el provider que ejecuta esta skill. Usar `auto` solamente cuando el contexto no permita distinguirlo.

Antes de leer el archivo del subcomando, leer y aplicar `$SKILL_DIR/knowledge/config/command-entrypoint.md` con el subcomando canónico resuelto, los tokens completos de la invocación y el provider. Si el entrypoint deshabilita la ejecución, detenerse.

### Paso 3 — Despachar

Solo si el entrypoint habilita la ejecución, leer `$SKILL_DIR/subcommands/<subcomando-resuelto>.md`, seguir literalmente sus instrucciones y pasarle los argumentos restantes junto con el estado combinado de readiness ya validado cuando corresponda.

Ejemplos:

| Input del usuario | Archivo a leer | Argumentos |
|-------------------|----------------|------------|
| `/groot-queue start` | `subcommands/start.md` | — |
| `/groot-queue setup` | `subcommands/setup.md` | — |
| `/groot-queue detail SSHP-1234567` | `subcommands/detail.md` | `SSHP-1234567` |
| `/groot-queue save SSHP-1234567 cambio de lider corregido` | `subcommands/save.md` | `SSHP-1234567 cambio de lider corregido` |
| `/groot-queue analyze-history --help` | `subcommands/analyze-history.md` | `--help` |
| `/groot-queue` | `subcommands/start.md` | — |

**Nota para Claude Code**: si el usuario invoca `/groot-queue:<nombre>`, Claude carga directamente `commands/<nombre>.md`. Esos wrappers aplican el mismo contrato central con provider `claude` y luego apuntan al mismo archivo de subcomando.

---

## Subcomandos disponibles

| Subcomando | Alias | Acción |
|------------|-------|--------|
| `start` | — | Mostrar banner de bienvenida, versión y catálogo de comandos con hints de uso |
| `setup` | — | Diagnosticar dependencias, integraciones, permisos y readiness de Grid Sharing + Fury Services/FuryDocs; no instala ni modifica componentes sin aprobación explícita |
| `list` | `ls` | Listar todos los incidentes abiertos |
| `classify` | `cl` | Clasificar y agrupar por tipo de problema + urgencia |
| `detail SSHP-XXXXXX` | `d` | Detalle completo de un ticket con clasificación y sugerencia |
| `solve SSHP-XXXXXX` | `s` | Sugerir solución basada en runbooks + análisis |
| `alerts [--dry-run]` | — | Detectar tickets vencidos y por vencer, agrupar por responsable del TEAM y enviar un resumen por Slack DM a cada uno |
| `stats` | — | Estadísticas agregadas de la cola |
| `assign-unassigned` | `aa`, `assign` | Asignar en Jira todos los tickets sin responsable repartiéndolos de forma equitativa entre el TEAM (stateless) |
| `derive SSHP-XXXXXX` | `der` | Derivar un ticket al equipo correcto: detecta regla R-DER y, si hay MCP Atlassian compatible, postea nota interna y transiciona estado |
| `discard SSHP-XXXXXX` | `dis` | Descartar un ticket que no corresponde a Groot Soporte: detecta regla R-DESC y, si hay MCP Atlassian compatible, postea comentario público y cierra el ticket |
| `save SSHP-XXXXXX <desc>` | — | Guardar la solución aplicada a un ticket en la knowledge base |
| `add-rule` | `ar` | Agregar una nueva regla de triage a la knowledge base |
| `backfill-guides` | `bf`, `backfill` | Postear guías de resolución (nota interna) en tickets abiertos y asignados que aún no tienen guía — backfill retroactivo idempotente |
| `analyze-history [--limit N] [--since YYYY-MM-DD] [--force]` | `ah`, `history` | Analizar tickets cerrados históricos y extraer patrones para la knowledge base |
| _(sin argumento)_ | — | Ejecutar `start` (banner + catálogo de comandos) |

---

## Resumen Operativo De `analyze-history`

Para detalles completos, leer `subcommands/analyze-history.md`.

- Requiere MCP Atlassian para consultar tickets cerrados, leer changelog/comentarios y escribir labels.
- Por defecto procesa máximo `20` tickets (`--limit N` cambia ese máximo).
- Idempotencia vía labels en Jira: `groot-kb-analyzed` / `groot-kb-manual-review`.
- `--force` re-analiza tickets con `groot-kb-analyzed` (no `groot-kb-manual-review`).
- `--since YYYY-MM-DD` filtra por fecha de actualización.
- `--only derivados|descartados|resueltos` filtra por tipo de desenlace.

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
    accountId: 5cd4929cc9167e0d6ea2312d
    name: Francisco Gonzalez
  - username: maescobar
    email: matias.escobar@mercadolibre.com
    accountId: 600061b51051d10075eac0b8
    name: Matias Joel Escobar
  - username: jgibelli
    email: julian.gibelli@mercadolibre.com
    accountId: "712020:43d9d55a-f958-4256-b2b7-9a0485c717ff"
    name: Julian Nicolas Gibelli
  - username: nicogutierre
    email: nicolasj.gutierrez@mercadolibre.com
    accountId: "712020:13bb4a44-bc51-4ee3-b443-8d8cc17acc7b"
    name: Julio Nicolas Gutierrez
  - username: hfurs
    email: hectoranibal.furs@mercadolibre.com
    accountId: 5ea6e12306a3eb0b7ec96e32
    name: Hector Furs
  - username: gsosa
    email: gustavo.sosa@mercadolibre.com
    accountId: 609eebec2614ec006877ad99
    name: Gustavo Gabriel Sosa Sotelo
  - username: levillanueva
    email: leonardo.villanueva@mercadolibre.com
    accountId: 62cf1c0f10fcc6f7ae3ea200
    name: Leonardo Manuel Villanueva
  - username: gmodarelli
    email: guido.modarelli@mercadolibre.com
    accountId: "712020:8300527c-0cb7-4412-8303-0306dac20649"
    name: Guido Modarelli
```

El orden de la lista **no** define el turno: en cada corrida, `assign-unassigned` baraja el TEAM una sola vez (un shuffle aleatorio) y reparte los tickets siguiendo ese orden, sin repetir (si hay más tickets que miembros, repite el mismo orden barajado). La asignación **no persiste estado entre corridas** — usa un archivo scratch efímero (creado con `mktemp` y borrado al terminar) solo durante la ejecución, así la equidad no depende del orden en que cada miembro ejecute el comando ni de ninguna cache compartida.

---

## Cuándo Usar

- Usuario invoca `/groot-queue <subcomando>` (Codex) o `/groot-queue:<subcomando>` (Claude Code).
- Usuario pregunta por tickets de soporte de Groot, la cola de Groot, incidentes pendientes.

---

## Onboarding y diagnóstico

La [guía completa de Groot Queue](knowledge/config/installation.md) es la fuente canónica para instalar, configurar, diagnosticar, actualizar y desinstalar el entorno. El subcomando `setup` solo diagnostica y propone remediaciones; no instala, autentica, habilita, configura ni actualiza componentes sin aprobación explícita.

---

## Reglas globales

- **WRITE CONTROLADO**: los subcomandos `assign-unassigned`, `derive` y `discard` pueden escribir en Jira (`assign-unassigned`: transición + asignación; `derive`: nota interna + transición de estado + labels de trazabilidad; `discard`: comentario público + transición de cierre + labels de trazabilidad — los tres requieren MCP Atlassian compatible). `save` y `add-rule` escriben en la knowledge base local. `analyze-history` escribe en la knowledge base local **y** agrega labels de estado (`groot-kb-analyzed` / `groot-kb-manual-review`) en los tickets de Jira (requiere MCP Atlassian). Todos los demás subcomandos son read-only.
- **La base de conocimiento vive fuera de los subcomandos**. No duplicar runbooks ni reglas: siempre referenciar `classification.md` / `triage-rules.md` / `runbooks.md` / `solutions/` por path.
- Siempre mostrar el link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`.
- Las respuestas deben ser en español.
