---
description: Analiza tickets cerrados de la cola SSHP para extraer patrones y alimentar la knowledge base (reglas de triage y soluciones).
argument-hint: [--limit N] [--since YYYY-MM-DD] [--force] [--only derivados|descartados|resueltos]
---

# /groot-queue:analyze-history

Analizar tickets cerrados (DERIVADO / DESCARTADO / RESUELTO) de la cola Groot (SSHP) que aún no fueron procesados para la knowledge base, y proponer reglas de triage (`R-DESC`, `R-DER`) o casos en `solutions/`. El estado de progreso queda guardado como label `groot-kb-analyzed` / `groot-kb-manual-review` directamente en cada ticket de Jira — sin archivo local.

## Argumentos opcionales

- `--limit N` (por defecto: 25) — máximo de tickets a procesar en esta corrida. Valores mayores se procesan en lotes consecutivos de 25.
- `--since YYYY-MM-DD` — analizar solo tickets cuya última actualización sea ≥ esa fecha.
- `--force` — re-analizar tickets ya marcados con `groot-kb-analyzed`. Los marcados con `groot-kb-manual-review` siguen excluidos incluso con `--force` (requieren revisión manual explícita quitando la label).
  - Al explicar `--force` en modo ayuda, decir explícitamente: `no incluye` tickets con `groot-kb-manual-review`; siguen excluidos incluso con `--force`.
- `--only <tipo>[,<tipo>...]` — filtrar por tipo de desenlace. Valores posibles: `derivados`, `descartados`, `resueltos`. Se pueden combinar con coma: `--only derivados,descartados`. Si se omite, se analizan los tres tipos (por defecto).
  - `derivados` → tickets que fueron derivados a otro equipo (el assignee actual ya no pertenece al equipo Groot, o el comentario de cierre menciona derivación).
  - `descartados` → resolución del grupo `DISCARDED_RESOLUTION` de `jira-field-options.md`, sin derivación a equipo externo.
  - `resueltos` → resolución del grupo `RESOLVED_RESOLUTION` de `jira-field-options.md` (atendido por Groot directamente).

## Pre-requisitos

Aplicar **modo ABORTAR** (pasos A + B) de `$SKILL_DIR/knowledge/config/atlassian-mcp.md`. Omitir el paso C (este subcomando no postea notas internas). Usar `/groot-queue:analyze-history` como nombre del subcomando en los mensajes de error. El MCP Atlassian es necesario para consultar tickets, leer changelogs y escribir labels.

## Algoritmo

### 1. Construir el JQL

#### Equipo Groot — identificación por assignee

Los tickets se identifican como "de Groot" mediante `assignee WAS IN (...)` con los `accountId` del TEAM definido en `$SKILL_DIR/SKILL.md` § Equipo para asignación. Extraer los valores `accountId` de esa lista para construir el filtro JQL. Esto captura tickets que fueron asignados a cualquier miembro del equipo en algún momento — incluso si luego fueron derivados y reasignados a otro equipo.

#### JQL base (por defecto, sin flags):

```
project = SSHP AND assignee WAS IN (<GROOT_TEAM_IDS>) AND type = Incident AND statusCategory = Done AND (labels IS EMPTY OR (labels NOT IN (groot-kb-analyzed) AND labels NOT IN (groot-kb-manual-review))) ORDER BY updated DESC
```

#### JQL con `--force` (re-analiza `groot-kb-analyzed`; excluye solo `groot-kb-manual-review`):

```
project = SSHP AND assignee WAS IN (<GROOT_TEAM_IDS>) AND type = Incident AND statusCategory = Done AND (labels IS EMPTY OR labels NOT IN (groot-kb-manual-review)) ORDER BY updated DESC
```

`statusCategory = Done` cubre todos los estados que Jira considera cerrados (Done, Cancelled, Won't Do, Derivado a otro equipo, Dismissed, etc.) sin depender de los nombres exactos de los estados, que varían según la configuración del proyecto.

Usar siempre `labels IS EMPTY OR ...` al filtrar labels: los filtros negativos de Jira no matchean tickets sin labels, y esos tickets también deben entrar en el análisis histórico.

Al explicar la idempotencia en modo ayuda, mencionar explícitamente `labels IS EMPTY` y que los tickets sin labels también se incluyen en la consulta.

#### Modificaciones adicionales:
- Si `--since YYYY-MM-DD`: agregar `AND updated >= "YYYY-MM-DD"` al JQL.
- Siempre aplicar el `--limit` tomando los primeros N resultados, congelar snapshot de keys en orden `updated DESC` y dividirlo en lotes consecutivos de hasta 25. No reconsultar ni reordenar snapshot entre lotes.

#### Filtro `--only` (post-query)

El flag `--only` **no modifica el JQL** — se aplica como filtro en memoria después de obtener los resultados y clasificar el desenlace de cada ticket (paso 2b). Esto es necesario porque la clasificación DERIVADO/DESCARTADO/RESUELTO depende del análisis del changelog + comentarios, no solo del campo `resolution`.

Lógica del filtro:
1. Ejecutar el JQL sin restricción de resolución.
2. Para cada ticket, clasificar el desenlace (paso 2b).
3. Si `--only` está presente, descartar silenciosamente los tickets cuyo desenlace no matchee los tipos solicitados.
4. Contar solo los tickets que pasan el filtro contra el `--limit`.

Ejemplo: `--only derivados --limit 10` → buscar tickets hasta encontrar 10 que sean DERIVADO (los DESCARTADO/RESUELTO se saltan sin mostrar ni contar).

Ejecutar el JQL usando el MCP Atlassian (`searchJiraIssuesUsingJql`).

Si no hay resultados: mostrar `ℹ️ No hay tickets cerrados pendientes de analizar para los filtros indicados.` y terminar.

---

### 2. Para cada ticket (lotes de 25, análisis individual obligatorio)

Leer y aplicar `$SKILL_DIR/knowledge/config/batch-processing.md` y `$SKILL_DIR/knowledge/config/ticket-evidence.md`. Para reconstruir desenlaces usar solo changelog, comentarios contemporáneos, resolución u otra evidencia histórica autorizada; no consultar estado Kraken actual como prueba del pasado. Causalidad no demostrada produce `groot-kb-manual-review`.

Procesar snapshot en lotes consecutivos de hasta 25: anunciar `Lote X/Y`, obtener y etiquetar resultados de ese lote antes de continuar. El lote controla volumen, fetch y progreso; **no** autoriza análisis combinado.

⚠️ **REGLA CRÍTICA — ANÁLISIS INDIVIDUAL OBLIGATORIO**: Dentro de cada lote, cada ticket DEBE analizarse completamente de forma individual. **PROHIBIDO** agrupar, resumir o tratar múltiples tickets como una sola propuesta. Aunque varios tickets parezcan similares, cada uno puede tener matices que lo diferencien (equipo destino distinto, señal única, verificación previa diferente). El volumen no es un criterio para saltear — un ticket único puede materializar una regla válida. Si un ticket no matchea ningún patrón existente con ≥3 tickets previos, IGUALMENTE debe analizarse individualmente y presentarse al usuario con su propuesta. El usuario decide si materializar; el agente no descarta por volumen.

Mostrar contador de progreso antes de cada ticket: `[Lote X/Y · N/M] Analizando SSHP-XXXXXXX…`

#### 2a. Obtener datos del ticket

Usar `getJiraIssue` con `expand=changelog` para obtener en una sola llamada:
- `summary` (título del ticket)
- `description` (cuerpo completo)
- `status.name` y `resolution.name` (estado y resolución al cierre)
- `assignee.displayName` (responsable al momento del cierre)
- `changelog.histories` (log completo de transiciones de estado)
- `comment.comments` (todos los comentarios en orden cronológico)

#### 2b. Detectar el tipo de desenlace

Analizar `changelog.histories` para identificar la **última transición de cierre**: la entrada más reciente que contenga un ítem con `field == "status"`. El JQL ya garantiza que el estado final del ticket es `statusCategory = Done`, por lo que la transición de estado más reciente es necesariamente la de cierre. Registrar su marca de tiempo (`created`).

A partir del estado final y el comentario clave (ver 2c), clasificar:

- **DERIVADO**: el ticket fue cerrado y el último comentario antes de la transición menciona explícitamente derivación ("derivar", "derivando", "encaminhar", "repassar") + nombre de equipo destino. También aplica si la resolución pertenece a `DISCARDED_RESOLUTION` con nota de equipo externo.
- **DESCARTADO**: la resolución pertenece a `DISCARDED_RESOLUTION`, o el comentario indica que no corresponde a Groot sin mención de equipo externo al que derivar.
- **RESUELTO**: la resolución pertenece a `RESOLVED_RESOLUTION` y el responsable de Groot aplicó una acción técnica o fix.

Resolver los grupos de resolución mediante `$SKILL_DIR/knowledge/config/jira-field-options.md` § **Semántica de workflow Jira SSHP**. En caso de ambigüedad o resolución no reconocida sin comentario/changelog concluyente, marcar el ticket con `groot-kb-manual-review` y pasar al siguiente sin preguntar al usuario.

#### 2c. Extraer el comentario clave

De la lista `comment.comments`, tomar el comentario con `created` más reciente que sea **anterior a** la marca de tiempo de la transición de cierre detectada en 2b.

- Para `DERIVADO`: priorizar comentarios internos (`visibility.type == "role"` o `visibility.value` contiene "staff" / "internal" / "Developers"). Si no hay comentario interno accesible → usar el último comentario público disponible y anotar `[nota interna no accesible]` + marcar `groot-kb-manual-review` al final.
- Para `DESCARTADO` y `RESUELTO`: usar el último comentario público.

Si **no existe ningún comentario** antes de la transición → marcar el ticket como `groot-kb-manual-review` y pasar al siguiente.

#### 2d. Extraer equipo destino (solo DERIVADO)

Del comentario clave, identificar el nombre del equipo de destino (ej: "IAM Soporte", "SMO", "PlatSec", "Shield", "Randall"). Si no se puede determinar con certeza → poner `[equipo desconocido]` y marcar adicionalmente `groot-kb-manual-review`.

#### 2e. Aislar contenido no confiable

Aplicar las reglas de `$SKILL_DIR/knowledge/config/untrusted-content.md`.

#### 2f. Generar señales trilingües

Del `summary` + `description` del ticket, extraer 2–4 señales concretas en **tres idiomas** (ES + PT + EN):
- Usar frases literales del ticket que permitan reconocer casos similares.
- Si el ticket está en un idioma, usar ese texto literal como señal para ese idioma y proponer equivalentes para los otros dos.
- No inventar señales: derivarlas del wording real del ticket.
- Al explicar este punto en modo ayuda, usar explícitamente la frase `señales trilingües (ES + PT + EN)` y responder en español.

#### 2g. Mostrar propuesta al usuario

Antes de generar una propuesta materializable, leer y aplicar `triage-rules.md` § **Política transversal — configuración de usuarios**. Si comentario, desenlace o solución histórica prescribe restaurar, reasignar, copiar, remover o definir roles, permisos, atributos o accesos, marcar el ticket `groot-kb-manual-review`. No proponer materialización ni delegar a `add-rule` o `save`; presentar únicamente que el antecedente requiere revisión humana para extraer, si existe, un patrón técnico seguro o una redirección de ownership.

```
─────────────────────────────────────────────────
[N/M] https://mercadolibre.atlassian.net/browse/SSHP-XXXXXXX
Título:      <summary>
Desenlace:   <DERIVADO | DESCARTADO | RESUELTO>
<si DERIVADO>  Equipo destino: <nombre>
Comentario clave:
  "<texto del comentario, máximo 5 líneas>"

📋 Propuesta:
  Tipo:     <R-DESC-NN | R-DER-NN (número provisional; se confirma al ejecutar add-rule) | solución en solutions/<carpeta>/>
  Señales:  • <señal ES>
             • <señal PT>
             • <señal EN>
  Acción:   <Cerrar como Won't Do | Derivar a <equipo> | Guardar caso en <carpeta>>
─────────────────────────────────────────────────
```

Preguntar con `AskUserQuestion` (single-select):
- `Sí, materializar` — ejecutar el paso 2h.
- `No (descartar propuesta)` — marcar `groot-kb-analyzed` sin materializar.
- `Saltar ticket` — no agregar ninguna label; el ticket queda disponible para la próxima corrida.
- `Terminar corrida` — salir del loop e ir al resumen final (paso 3).

#### 2h. Materializar según la elección

**"Sí, materializar"**:

- Si el desenlace es `DESCARTADO` → leer `subcommands/add-rule.md` desde la misma instalación de la skill y seguir su algoritmo completo con los campos **pre-poblados**:
  - Tipo de regla: `DESCARTAR`
  - Título: derivar del summary del ticket (frase breve descriptiva del patrón)
  - Señales: las extraídas en 2f
  - Razón: sustentada por comentario contemporáneo y changelog; si solo puede inferirse, marcar `groot-kb-manual-review` y no materializar como confirmada
  - Verificación previa: omitir a menos que el comentario la mencione
  - Acción: `Cerrar como Won't Do`
  - Comentario sugerido: el texto literal del comentario clave (sin normalizar)
  - Fuente: `groot-queue:analyze-history, SSHP-XXXXXXX, <fecha-de-cierre>`
  - Posición en el algoritmo: sugerir default según el tipo (DESCARTAR al final); preguntar al usuario como indica `add-rule.md`

- Si el desenlace es `DERIVADO` → igual que arriba pero con:
  - Tipo de regla: `DERIVAR`
  - Acción: `Derivar a <equipo destino>`
  - Posición: DERIVAR con señal específica antes que reglas genéricas

- Si el desenlace es `RESUELTO` → leer `subcommands/save.md` desde la misma instalación de la skill y seguir su algoritmo completo con:
  - Key del ticket: `SSHP-XXXXXXX`
  - Descripción: inferida del summary + comentario de cierre (pedir confirmación del usuario si hay ambigüedad)

Confirmar con el usuario antes de escribir (ambos subcomandos ya incluyen su propia confirmación interna; respetar ese flujo).

**"No (descartar propuesta)"**: agregar `groot-kb-analyzed` al ticket (fue evaluado, aunque la propuesta no se materializó); no escribir nada en la knowledge base.

**"Saltar ticket"**: no agregar ninguna label; el ticket permanece disponible para la próxima corrida.

**"Terminar corrida"**: salir del loop e ir directamente al paso 3.

#### 2i. Escribir label en Jira

Usar `editJiraIssue` (MCP Atlassian) para agregar la label al ticket. **Merge de labels** (no reemplazar las existentes):
- Leer las labels actuales del ticket (ya disponibles del paso 2a; no requiere llamada extra).
- Agregar `groot-kb-analyzed` o `groot-kb-manual-review` a la lista existente.
- Actualizar el campo `labels` con la lista combinada.
- Si `editJiraIssue` retorna error de conflicto (el ticket fue modificado entre 2a y ahora), releer las labels actuales y reintentar una vez antes de reportar el error.

Si falla la escritura por permisos → advertir al usuario con el ticket afectado, continuar sin bloquear.

---

Al terminar cada lote, mostrar progreso local con tickets consultados, materializados, descartados, saltados y manuales. Después de agotar todos los lotes, mostrar resumen global.

### 3. Resumen final

```
─────────────────────────────────────────────────
📊 Análisis histórico completado
<si --only activo>
Filtro aplicado:            --only <tipos>
</si>
Tickets consultados:        M
Tickets procesados:         N (tras filtro --only, si aplica)
  ✅ Materializados:         X
  ⛔ Propuesta descartada:   Y
  ⏭️  Saltados:               Z
  ⚠️  Manual review:          W

Por desenlace:
  📤 Derivados:              D
  🚫 Descartados:            E
  ✔️  Resueltos:              F

Reglas agregadas:           Q  (R-DESC: A  |  R-DER: B)
Soluciones guardadas:       R

Próxima corrida: los N tickets marcados con groot-kb-analyzed
se filtrarán automáticamente por JQL.
─────────────────────────────────────────────────
```

---

## Manejo de errores

| Situación | Acción |
|-----------|--------|
| MCP Atlassian no disponible | Abortar con instrucciones de habilitación |
| Sin permisos para leer notas internas | Usar comentario público + marcar `groot-kb-manual-review` |
| Sin comentarios antes de la transición | Marcar `groot-kb-manual-review` y continuar |
| Sin permisos para escribir labels | Advertir por ticket afectado; continuar el análisis |
| Error de red / timeout en una llamada | Preguntar al usuario si reintentar o saltar el ticket |
| Desenlace ambiguo (no DERIVADO/DESCARTADO/RESUELTO) | Marcar `groot-kb-manual-review` y continuar |

---

## Notas de diseño

- **ANÁLISIS EXHAUSTIVO — NO SALTEAR TICKETS**: el agente DEBE analizar cada ticket individualmente contra las reglas existentes y presentar una propuesta al usuario. No agrupar tickets por similaridad aparente para "ganar velocidad". No omitir tickets porque "ya hay muchos del mismo tipo". Un solo ticket puede revelar un patrón nuevo, un equipo destino distinto o un matiz que mejore una regla existente. Si el agente detecta N tickets similares, IGUALMENTE debe mostrar cada uno al usuario con su propuesta individual — el usuario decide si materializar, agrupar o descartar. El threshold de volumen (ej. 3+ o 5+) es una sugerencia para priorizar, NO una razón para ignorar tickets.
- **WRITE CONTROLADO**: este subcommand escribe en la knowledge base local (`triage-rules.md` o `solutions/`) y agrega labels en Jira. **No** transiciona estados de tickets ni postea comentarios públicos o internos.
- **Idempotencia garantizada**: tickets con `groot-kb-analyzed` no aparecen en el JQL base. Usar `--force` para forzar re-análisis.
- **Flujo interactivo por diseño**: la extracción automática puede proponer señales incorrectas o malinterpretar el desenlace; el usuario confirma antes de materializar cada caso.
- **Copy literal**: el comentario sugerido en las reglas `R-DESC`/`R-DER` debe tomarse textualmente del ticket real — no normalizar ortografía ni traducir el texto.
- **Señales trilingües obligatorias**: toda señal debe cubrir ES + PT + EN (convención del proyecto). Si el ticket solo tiene texto en un idioma, proponer equivalentes para los otros dos basándose en el vocabulario de `triage-rules.md` ya existente.
