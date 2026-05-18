---
name: groot-queue
description: "Monitorea la cola de soporte [Core] - Groot (SSHP). Lista, clasifica, analiza urgencia, sugiere soluciones, alerta por Slack y asigna tickets sin responsable usando round-robin. Usar cuando el usuario invoque /groot-queue o pregunte por tickets de soporte de Groot."
---

# Groot Queue Monitor

**Propósito**: Monitorear y gestionar la cola de soporte "[Core] - Groot" del proyecto Jira SSHP. Read-only salvo el subcomando `assign-unassigned`, que asigna tickets en Jira usando round-robin.

---

## Base de conocimiento

Toda la lógica de negocio (reglas de triage, runbooks procedurales y casos concretos) vive en la **knowledge base** bundleada con la skill:

```
~/.claude/skills/groot-queue/knowledge/
├── triage-rules.md   ← Reglas R-DESC / R-DER / R-FIX + algoritmo de triage
├── runbooks.md       ← Runbooks procedurales por categoría (Jerarquía, CAD, etc.)
├── solutions/        ← Casos concretos resueltos, por categoría
└── apis/             ← Docs de endpoints (a futuro)
```

La skill **debe leer estos archivos** cada vez que los necesite (sin cachear):

- **`triage-rules.md`** → al ejecutar `list`, `classify`, `detail` y `solve` para asignar veredicto.
- **`runbooks.md`** → al ejecutar `detail` y `solve` para buscar el procedimiento de la categoría.
- **`solutions/<categoria>/*.md`** → al ejecutar `solve` para enriquecer con casos previos.

Si cualquiera de estos archivos no existe, avisar al usuario y seguir con los datos mínimos (sin runbook → solo clasificación; sin reglas → solo `REVISAR_MANUAL`).

---

## Equipo para Round-Robin

Lista de usernames de Jira para la rotación. Editá esta lista para cambiar el equipo:

```
TEAM:
  - frgonzalez       # Francisco Gonzalez
  - lpadularrosa     # Lucas Nahuel Padularrosa
  - maescobar        # Matias Joel Escobar
  - jgibelli         # Julian Nicolas Gibelli
  - nicogutierre     # Julio Nicolas Gutierrez
  - hfurs            # Hector Furs
  - gsosa            # Gustavo Gabriel Sosa Sotelo
  - levillanueva     # Leonardo Manuel Villanueva
  - gmodarelli       # Guido Modarelli
```

El orden define el turno. El índice actual se persiste en:
`~/.claude/skills/groot-queue/knowledge/roundrobin-state.json`

---

## Cuándo Usar

- Usuario invoca `/groot-queue` con un subcomando
- Usuario pregunta por tickets de soporte de Groot, la cola de Groot, incidentes pendientes

---

## Subcomandos

Parsear el argumento del usuario para determinar el subcomando:

| Argumento | Acción |
|-----------|--------|
| `list` | Listar todos los incidentes abiertos |
| `classify` | Clasificar y agrupar por tipo de problema + urgencia |
| `detail SSHP-XXXXXX` | Detalle completo de un ticket con clasificación y sugerencia |
| `solve SSHP-XXXXXX` | Sugerir solución basada en runbooks + análisis |
| `alerts` | Detectar tickets en riesgo de SLA y notificar por Slack DM |
| `stats` | Estadísticas agregadas de la cola |
| `setup` | Verificar e instalar dependencias necesarias (ACLI, Slack MCP, permisos, estado round-robin) |
| `assign-unassigned` | Asignar en Jira todos los tickets sin responsable usando round-robin |
| `save SSHP-XXXXXX <desc>` | Guardar la solución aplicada a un ticket en la knowledge base |
| `add-rule` | Agregar una nueva regla de triage (DESCARTAR / DERIVAR / FIX_APLICADO) a la knowledge base mediante flujo interactivo |
| _(sin argumento)_ | Mostrar ayuda con los subcomandos disponibles |

---

## Paso 1: Consultar Jira

Para TODOS los subcomandos (excepto `detail` y `solve` que usan una key específica), ejecutar:

```bash
acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type = Incident AND resolution = Unresolved ORDER BY created DESC"
```

Para `detail` y `solve` con una key específica:

```bash
acli jira workitem view SSHP-XXXXXX
```

---

## Paso 2: Clasificación

Antes de clasificar por categoría/urgencia, aplicar el **triage de veredicto** definido en `triage-rules.md` (ver path arriba). Ese archivo contiene las reglas extraídas del seguimiento histórico de la ticketera para identificar tickets que deben **descartarse**, **derivarse a otro equipo** o que ya tienen un **fix aplicado**. Leerlo al inicio de cualquier `list` o `classify` y aplicar su algoritmo a cada ticket para asignar un veredicto: `DESCARTAR`, `DERIVAR`, `FIX_APLICADO`, `VALIDO_GROOT` o `REVISAR_MANUAL`.

Luego clasificar CADA ticket en DOS dimensiones:

### Dimensión 1 — Tipo de Problema

Analizar el summary y description del ticket y asignar UNA de estas categorías:

| Categoría | Descripción | Señales típicas (ES/PT/EN) |
|-----------|-------------|---------------------------|
| **Jerarquía/Líder** | Cambios de líder, gestión, jerarquía | cambio de lider, trocar lider, trocar gestao, hierarquia, jerarquia, lider directo, manager primario, alterar lider, lider incorreto |
| **Warehouse/Site** | Asignación de warehouse, facility, sitio | warehouse, ajustar warehouse, mover reps, mover colaborador, facility, cambiar SVC, trocar site |
| **Roles/Permisos** | Problemas con roles, permisos, autorización | rol, role, permiso, not authorized, no autorizado, boton deshabilitado, asignar rol, nao ve rol |
| **Visibilidad Usuario** | Usuario no aparece en sistemas | no aparece, nao aparece, sem bolhas, no visualizam, nao visualizam, sin visibilidad, tela branca |
| **Atributos** | Modificación de atributos falla | atributo, remover atributo, crossdocking, alteracao nao salva, no guarda el cambio |
| **Labour Share** | Problemas con labour share | labour share, labor share, no impacta |
| **CAD/Perfil** | Problemas de perfil, CAD, autogestión | CAD, autogestao, perfil incorrecto, xtools, cad errado |
| **Error UI Groot** | Errores de interfaz en Groot | erro ao editar, error en groot, se queda cargando, botao sumiu, nao foi possivel realizar, erro no groot |
| **Vincular/Desvincular** | Vincular/desvincular cuenta | vincular, desvincular, conta meli, cuenta meli, trocar senha |
| **Otro** | No encaja en ninguna categoría | — |

Las categorías se mapean 1:1 con los runbooks de `runbooks.md` y con las subcarpetas de `solutions/`.

### Dimensión 2 — Urgencia (1-5)

Calcular un score de urgencia basado en:

| Factor | Peso | Scoring |
|--------|------|---------|
| **Prioridad Jira** | 30% | Highest=5, High=4, Medium=3, Low=2, Lowest=1 |
| **Edad del ticket** | 25% | >72h=5, >48h=4, >24h=3, <24h=2 |
| **Status sin respuesta** | 25% | "Esperando por Soporte" >24h sin asignar=5, <24h=3, otros=1 |
| **Sin asignar** | 20% | Sin assignee=+1 al score |

Score final: promedio ponderado, redondeado a 1-5.
- Score >= 4 → **Riesgo SLA** (marcar con indicador rojo)

---

## Paso 3: Presentación según subcomando

### `list`

Mostrar tabla markdown:

```
| # | Key | Summary | Status | Priority | Assignee | Edad | Triage |
```

La columna `Triage` usa los indicadores de `triage-rules.md`: `⛔ DESCARTAR`, `➡️ DERIVAR→<Equipo>`, `✅ FIX_APLICADO`, `🟢 VALIDO_GROOT`, `❓ REVISAR_MANUAL`.

### `classify`

Mostrar primero la sección **"🚨 Acciones de triage recomendadas"** con los matches de `triage-rules.md` (ver formato en ese archivo).

Luego mostrar tickets agrupados por categoría, ordenados por urgencia dentro de cada grupo:

```
### Jerarquía/Líder (5 tickets)
| Key | Summary | Urgencia | Edad | Assignee |

### Warehouse/Site (3 tickets)
| Key | Summary | Urgencia | Edad | Assignee |
...
```

Indicadores de urgencia:
- 1-2: `🟢`
- 3: `🟡`  
- 4-5: `🔴`

### `detail SSHP-XXXXXX`

Mostrar:
1. **Info del ticket**: key, summary, status, priority, assignee, URL
2. **Veredicto de triage**: leer `triage-rules.md` y aplicar el algoritmo; citar la regla matcheada si corresponde
3. **Clasificación**: categoría asignada con justificación
4. **Urgencia**: score con desglose de factores
5. **Descripción**: texto completo
6. **Sugerencia de solución**: aplicar la lógica de `solve`

### `solve SSHP-XXXXXX`

Analizar el ticket y sugerir una solución siguiendo este orden:
1. Identificar la categoría del problema
2. Leer `runbooks.md` y buscar el runbook de esa categoría
3. Leer `solutions/<categoria>/*.md` en busca de casos previos con señales similares
4. Complementar con análisis propio basado en el contexto del ticket
5. Presentar:
   - **Diagnóstico probable**: qué está pasando
   - **Pasos de resolución**: ordenados, concretos, con URLs si aplica
   - **Casos similares**: links a archivos de `solutions/` si se encontraron
   - **Escalación**: a quién escalar si no se resuelve
   - **Confianza**: baja/media/alta

### `alerts`

1. Obtener todos los tickets abiertos
2. Clasificar cada uno (incluye triage)
3. Filtrar los que tienen urgencia >= 4 O están en "Esperando por Soporte" sin asignar hace >24h
4. Para cada ticket en riesgo, enviar Slack DM a **lucas.padularrosa@mercadolibre.com** usando las tools de Slack MCP. Primero autenticarse con `mcp__plugin_slack_slack__authenticate` si es necesario, luego enviar mensaje con formato:
   - 🔴 **SLA Risk** — SSHP-XXXXXX
   - Summary del ticket
   - Categoría | Urgencia X/5 | Edad Xh
   - Link a Jira: https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX
5. Mostrar resumen en consola de cuántos alerts se enviaron

### `stats`

Mostrar:
- Total de tickets abiertos
- Cantidad sin asignar
- Cantidad con riesgo SLA (urgencia >= 4)
- Edad promedio
- Tabla: tickets por categoría (con barra visual)
- Tabla: tickets por score de urgencia
- Tabla: tickets por veredicto de triage (DESCARTAR / DERIVAR / FIX_APLICADO / VALIDO_GROOT / REVISAR_MANUAL)

---

### `setup`

Verificar e instalar todo lo necesario para usar el skill. Ejecutar en orden:

**1. ACLI (Atlassian CLI)**
- Verificar: `acli --version`
- Si no está instalado: mostrar instrucciones → `brew install acli` o https://acli.atlassian.com
- Si está instalado, verificar autenticación: `acli jira serverinfo`
  - Si falla: mostrar `acli jira login --server https://mercadolibre.atlassian.net`

**2. Slack MCP**
- Verificar si el tool `mcp__plugin_slack_slack__authenticate` está disponible en el contexto
- Si no está disponible: indicar al usuario que instale el plugin de Slack:
  ```
  claude mcp add slack
  ```
- Si está disponible pero no autenticado: ejecutar `mcp__plugin_slack_slack__authenticate`

**3. Permisos ACLI en settings**
- Verificar que el directorio `.claude/` existe en el directorio actual
- Verificar que `.claude/settings.local.json` contiene `"Bash(acli jira *)"` en `permissions.allow`
- Si no: crear o actualizar el archivo con el permiso mínimo necesario:
  ```json
  { "permissions": { "allow": ["Bash(acli jira *)"] } }
  ```

**4. Estado round-robin**
- Verificar si existe el archivo `roundrobin-state.json` en la knowledge base
- Si no existe: crearlo con `{ "last_updated": "", "next_assignee_index": 0, "history": [] }`
- Path esperado: `~/.claude/skills/groot-queue/knowledge/roundrobin-state.json`

**5. Verificación del TEAM**
- Leer la sección TEAM del SKILL.md
- Si está vacía: advertir que `assign-unassigned` no funcionará hasta configurarlo

**Output esperado:**
```
✅ ACLI instalado (v8.x.x)
✅ ACLI autenticado en mercadolibre.atlassian.net
✅ Slack MCP disponible y autenticado
✅ Permiso Bash(acli jira *) configurado
✅ Estado round-robin inicializado
✅ Equipo configurado (9 miembros)

Setup completo. Podés usar /groot-queue list para empezar.
```

### `assign-unassigned`

**Pre-condición**: si `TEAM` está vacío, abortar con mensaje: "Configurá la sección TEAM del SKILL.md antes de usar este comando."

**Algoritmo**:
1. Leer el estado desde `roundrobin-state.json` (path de la knowledge base). Si no existe, inicializarlo con `next_assignee_index: 0` y `history: []`.
   **IMPORTANTE**: el estado se actualiza con el Write tool después de CADA asignación exitosa (paso 6d). No esperar al final.
2. Si `next_assignee_index >= len(TEAM)`, resetear a 0 (protección ante cambios en la lista).
3. Obtener todos los tickets abiertos (mismo JQL que `list`).
4. Filtrar solo los que **no tienen assignee** (campo `assignee` vacío o null).
5. Ordenar por urgencia descendente (score 5 primero).
6. Para cada ticket sin asignar:
   a. `assignee = TEAM[next_assignee_index]`
   b. Transicionar a "In Progress" **primero** — en una llamada Bash **separada**:
      `acli jira workitem transition --key <KEY> --status "In Progress" --yes`
      - Si falla: reportar el error, **NO avanzar el índice**, continuar con el siguiente ticket
      - ⚠️ CRÍTICO: la transición auto-asigna al usuario autenticado de ACLI, pisando cualquier asignación previa. Por eso la asignación debe ir en una llamada Bash **separada e independiente** — nunca encadenar ambos comandos con `&&` en un solo Bash call, ya que la transición puede completarse de forma asíncrona en Jira y terminar pisando el assign.
   c. Asignar responsable en una **nueva llamada Bash separada**, después de que la transición haya retornado: `acli jira workitem assign --key <KEY> --assignee <email> --yes`
      - El `<email>` se construye con el patrón `<nombre>.<apellido>@mercadolibre.com`. Algunos usernames no coinciden directamente con el email — si falla, buscar el email correcto vía `/fury:fury-users-search`.
      - Si falla: reportar el error, **NO avanzar el índice** (la transición ya ocurrió, pero se reporta)
   d. Verificar asignación en una **nueva llamada Bash separada**: `acli jira workitem view <KEY>` → leer el campo `Assignee:`
      - Si `Assignee` != `<email>`: reintentar el assign una vez más (`acli jira workitem assign --key <KEY> --assignee <email> --yes`)
        - Si sigue sin coincidir: reportar ⚠️ con el ticket y el assignee incorrecto, **NO avanzar el índice**
      - Si `Assignee` == `<email>`: continuar al paso e
   e. Si transición + asignación + verificación exitosas:
      - Calcular nuevo índice: `next_assignee_index = (next_assignee_index + 1) % len(TEAM)`
      - Calcular `last_updated`: timestamp actual en ISO8601 (ej: `2026-05-11T14:30:00Z`)
      - Agregar a `history`: `{ "key": "<KEY>", "assignee": "<username>", "ts": "<last_updated>" }`
      - Si `history` supera 100 entradas, eliminar las más antiguas hasta dejar 100.
      - **ACCIÓN BLOQUEANTE — usar Write tool INMEDIATAMENTE con este contenido exacto:**
        ```json
        {
          "last_updated": "<ISO8601 del momento actual>",
          "next_assignee_index": <nuevo valor calculado>,
          "history": [<history acumulado, máximo 100 entradas>]
        }
        ```
        Path destino: el path de `roundrobin-state.json` de la knowledge base del plugin.
      - Solo continuar al siguiente ticket **después** de que el Write tool retorne sin error.
   e. Si falla el Write: reportar el error, abortar el loop, mostrar cuántos tickets se asignaron exitosamente antes del fallo.
7. **El estado ya fue persistido incrementalmente en el paso 6d. No hay acción adicional aquí.**
   Verificación: si se asignaron N tickets, el Write tool debe haberse ejecutado N veces.
8. Mostrar tabla de resultados:

```
Asignaciones realizadas (N tickets):
| Key          | Summary                  | Transición  | Asignado a   | Estado  |
|--------------|--------------------------|-------------|--------------|---------|
| SSHP-XXXXX   | ...                      | ✓ En curso  | frgonzalez   | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✓ En curso  | lpadularrosa | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✗ Error     | —            | ✗ Skip  |

Estado del round-robin:
  Próximo en turno: maescobar (índice 2)
  Última actualización: <ISO8601 de la última asignación exitosa>
```

Si no hay tickets sin asignar, mostrar: "✅ No hay tickets sin assignee en la cola."

**History cap**: mantener máximo 100 entradas en `history`; eliminar las más antiguas si se supera el límite.

### `save SSHP-XXXXXX <descripción>`

**Objetivo**: Guardar la resolución real de un ticket en la knowledge base para mejorar futuros diagnósticos.

**Algoritmo**:
1. Obtener info del ticket: `acli jira workitem view SSHP-XXXXXX`
2. Detectar categoría usando la lógica de clasificación (Dimensión 1 del Paso 2)
3. Generar slug del archivo: `<ticket-key>-<primeras-3-palabras-del-summary>.md` (minúsculas, guiones)
   - Ejemplo: `SSHP-1407882-referencia-circular-lider.md`
4. Buscar si ya existe un archivo para ese ticket en `~/.claude/skills/groot-queue/knowledge/solutions/<categoria>/`:
   - Leer los frontmatter `ticket:` de cada archivo .md de esa carpeta
   - Si ya existe: mostrar `⚠️ Ya existe una solución para SSHP-XXXXXX en <path>. ¿Querés sobrescribir? (sí/no)`
   - Si el usuario dice no: abortar
5. Crear el archivo markdown en `~/.claude/skills/groot-queue/knowledge/solutions/<categoria>/`:

```markdown
---
ticket: SSHP-XXXXXX
category: <categoria-slug>
summary: <descripción provista por el usuario>
date: <fecha-actual-YYYY-MM-DD>
effectiveness: confirmed
---

## Problema
<summary del ticket en Jira>

## Solución Aplicada
<descripción provista por el usuario>

## Señales para identificar este patrón
<inferir del summary y descripción del ticket — 2-4 señales concretas>

## Tags
<keywords relevantes del ticket, separados por coma>
```

6. Mostrar confirmación:
```
✅ Solución guardada en:
   ~/.claude/skills/groot-queue/knowledge/solutions/<categoria>/<slug>.md

Categoría: <Nombre de categoría>
Fecha: <YYYY-MM-DD>
```

**Mapeo de categorías a carpetas de `solutions/`**:

| Categoría detectada | Carpeta |
|---------------------|---------|
| Jerarquía/Líder | `hierarchy-leader` |
| Warehouse/Site | `warehouse-assignment` |
| Roles/Permisos | `role-permission` |
| Visibilidad Usuario | `user-visibility` |
| Atributos | `attribute-modification` |
| Labour Share | `labor-share` |
| CAD/Perfil | `cad-profile` |
| Error UI Groot | `groot-ui-error` |
| Vincular/Desvincular | `link-unlink-account` |
| Otro | `queue-management` |

---

### `add-rule`

**Objetivo**: Sumar una nueva regla de triage a `triage-rules.md` mediante un flujo interactivo, para que el equipo pueda incorporar patrones detectados sin editar el archivo a mano.

**Alcance**: Solo edita `triage-rules.md` (sección de reglas + bloque "Algoritmo de triage"). Para soluciones puntuales a un ticket seguir usando `save`.

**Algoritmo**:

1. **Leer** `~/.claude/skills/groot-queue/knowledge/triage-rules.md` completo. Identificar:
   - El último número usado por cada familia: `R-DESC-NN`, `R-DER-NN`, `R-FIX-NN`.
   - La sección "Algoritmo de triage" (lista numerada al final).

2. **Recolectar datos** preguntando al usuario uno por uno (usar `AskUserQuestion` para opciones cerradas, prompt directo para texto libre):

   a. **Tipo de regla** (single-select): `DESCARTAR` / `DERIVAR` / `FIX_APLICADO`
   b. **Título corto** (texto): frase breve que describe el patrón (ej: "Tax ID inválido → IAM Soporte")
   c. **Señales** (texto multilínea): bullets concretos (summary/description matchers, URLs, contexto). Pedir al menos 2 señales.
   d. **Razón** (texto): por qué corresponde el veredicto (1-3 oraciones)
   e. **Verificación previa** (texto, opcional): condiciones que invalidarían la regla y deberían reclasificar. Si el usuario dice "ninguna" o vacío, omitir el campo.
   f. **Acción** (texto): qué hacer concretamente — para `DESCARTAR`: "Cerrar como Won't Do / Cancelled". Para `DERIVAR`: "Derivar a **<Equipo>**". Para `FIX_APLICADO`: "Cerrar como Done tras verificar query".
   g. **Comentario sugerido** (texto): copy validado para responder al usuario. Importante mantener el texto literal del equipo (no normalizar agresivamente).
   h. **Verificación SQL** (solo si `FIX_APLICADO`, texto): query para confirmar que el fix está aplicado.
   i. **Fuente** (texto): formato `<autor>, <ticket o contexto>, <fecha YYYY-MM-DD>`. Si el usuario no provee fecha, usar la fecha actual.
   j. **Posición en el algoritmo** (single-select): mostrar la lista numerada actual del bloque "Algoritmo de triage" y preguntar después de qué número insertar. Sugerir default según el tipo (FIX_APLICADO al inicio, DERIVAR con señal específica antes que genérica, DESCARTAR al final).

3. **Calcular nuevo ID**: incrementar el contador del tipo elegido. Ej: si la última `R-DER-XX` es `R-DER-10` → la nueva es `R-DER-11`.

4. **Construir bloque de la regla** con el siguiente formato exacto (mismo que las reglas existentes):

   ```markdown
   ### R-XXX-NN — <título>
   - **Señales**:
     - <señal 1>
     - <señal 2>
   - **Razón**: <razón>.
   - **Verificación previa**: <verificación>.   ← omitir línea si no se proveyó
   - **Verificación** (solo FIX_APLICADO):
     ```sql
     <query>
     ```
   - **Acción**: <acción>.
   - **Comentario sugerido**:
     > "<comentario tal cual lo dictó el usuario>"
   - **Fuente**: <fuente>.
   ```

5. **Insertar en la sección correcta** de `triage-rules.md`:
   - `DESCARTAR` → al final de la sección "Reglas `DESCARTAR`", antes del separador `---`.
   - `DERIVAR` → al final de la sección "Reglas `DERIVAR`", antes del separador `---`.
   - `FIX_APLICADO` → al final de la sección "Reglas `FIX_APLICADO`", antes del separador `---`.

   Usar el Edit tool con `old_string` = el último bloque de la sección destino + el separador `---`, y `new_string` = ese bloque + la nueva regla + separador. Mantener líneas en blanco consistentes con el archivo existente.

6. **Actualizar el bloque "Algoritmo de triage"**:
   - Insertar una nueva línea numerada en la posición elegida con el formato: `N. **R-XXX-NN** → <condición de match, 1 oración>.`
   - Renumerar en cascada todas las líneas posteriores.
   - Usar Edit tool con `old_string` = todo el bloque numerado actual, `new_string` = el bloque renumerado con la nueva línea.

7. **Mostrar confirmación**:
   ```
   ✅ Regla R-XXX-NN agregada a triage-rules.md

   Tipo:      <DESCARTAR / DERIVAR / FIX_APLICADO>
   Título:    <título>
   Posición:  #N en el algoritmo
   Fuente:    <fuente>

   La regla se aplicará en la próxima ejecución de `/groot-queue list` o `/groot-queue classify`.
   ```

**Validaciones**:
- Si el usuario aborta en cualquier paso (Ctrl+C / "cancelar"), no escribir nada.
- Si el tipo es `FIX_APLICADO` y no se provee query SQL, advertir pero permitir continuar (algunos fixes no requieren verificación SQL).
- Si el título o señales están vacíos, abortar con error claro.
- No permitir duplicados de ID: re-leer el archivo antes de calcular el contador (por si se ejecutó otro `add-rule` en paralelo en otra sesión).

**Nota**: Este comando **no** crea archivos en `solutions/`. Si la nueva regla tiene un caso concreto de referencia, sugerir al usuario al final: "Para guardar el caso concreto que originó esta regla, usá `/groot-queue save SSHP-XXXXXX <descripción>`."

---

## Reglas

- **WRITE CONTROLADO**: `assign-unassigned` escribe en Jira (transición + asignación). `save` escribe en la knowledge base local. Todos los demás subcomandos son read-only.
- **La base de conocimiento vive fuera de la skill**. No duplicar runbooks ni reglas acá: siempre referenciar `triage-rules.md` / `runbooks.md` / `solutions/` por path absoluto.
- Siempre mostrar el link a Jira: `https://mercadolibre.atlassian.net/browse/SSHP-XXXXXX`
- Las respuestas deben ser en español
- Si no hay argumento, mostrar el menú de subcomandos disponibles
- Para `alerts`, usar Slack MCP tools solo si el usuario lo solicita explícitamente la primera vez; después mantener la preferencia
