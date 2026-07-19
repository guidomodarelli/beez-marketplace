---
description: Asigna en Jira todos los tickets sin responsable repartiéndolos de forma equitativa sobre el TEAM configurado.
---

# /groot-queue:assign-unassigned

Asignar todos los tickets sin responsable repartiéndolos de forma **equitativa y sin estado local** entre el TEAM (un único shuffle por corrida, sin repetir; ver abajo). **Este command escribe en Jira** (transiciona estado + asigna responsable + postea nota interna con guía de resolución). Ver también `derive`, que escribe comentario + transición de estado.

## Por qué un único shuffle por corrida y sin estado persistente

La asignación **no persiste estado entre corridas**. Antes existía un `next_assignee_index` guardado localmente, pero como cada miembro del team corría el comando con su propio índice desfasado, la rotación terminaba siendo desigual entre todos. Ahora cada corrida hace **un único barajado (shuffle) del TEAM al inicio** y reparte siguiendo ese orden, **sin repetir**; si hay más tickets que miembros, se vuelve a recorrer **el mismo orden barajado** (no se baraja de nuevo), de modo que nadie recibe un segundo ticket hasta que todos recibieron uno. Como cada ejecución arranca con un barajado nuevo, la equidad no depende de ningún archivo compartido ni del orden en que cada persona ejecute el comando.

Durante la corrida se usan **archivos scratch efímeros** (creados con `mktemp`, fuera del repo): uno guarda el orden barajado de la corrida y otro la cola de trabajo que se va consumiendo. Es un detalle de implementación para que el loop sea robusto a lo largo de muchas llamadas Bash; **se crean frescos en cada corrida y se eliminan al terminar o abortar**, así que no son cache compartida ni sobreviven entre ejecuciones.

## Modo automatizado (sin confirmación humana)

Si la variable de entorno `GROOT_QUEUE_AUTORUN` está definida y su valor es `true`:

1. **Omitir todas las preguntas de confirmación** de los pasos 9e y 10e.
2. Proceder directamente **como si el usuario hubiera respondido "sí"** (derivar y descartar automáticamente).
3. Al registrar en el log de auditoría, usar `source = "auto-run"` (distinto a `"auto-assign"` usado en confirmación interactiva, para distinguir corridas 100% automáticas).
4. Verificar el valor con:
   ```bash
   echo "${GROOT_QUEUE_AUTORUN:-false}"
   ```
   Solo si el output es exactamente `true` se activa el modo automatizado.

> ⚠️ Este modo está pensado para ejecuciones programáticas (cron, n8n, CI) donde no hay operador humano. No activarlo en sesiones interactivas.

## Pre-condición

Leer el `TEAM` desde `$SKILL_DIR/SKILL.md`. Si está vacío, abortar con mensaje:
> "Configurá la sección TEAM del SKILL.md antes de usar este comando."

## Pre-condición: MCP Atlassian (para nota interna de resolución)

El paso 11 postea una nota interna en cada ticket elegible después de filtrar derivables y descartables. Si el MCP de Atlassian no está disponible, la asignación (pasos 6a-6e) se ejecuta igual, pero el paso 11 se salta con un warning al inicio:

**A. Disponibilidad de herramientas:**
Intentar llamar `mcp__Atlassian__getAccessibleAtlassianResources` (o herramienta equivalente).

- Si la herramienta **no existe** en el contexto → mostrar warning y marcar `MCP_AVAILABLE = false`:
  ```
  ⚠️ MCP Atlassian no disponible — las notas internas de resolución no se postearán.
  Las asignaciones se realizarán normalmente. Para habilitar notas, instalá el MCP:
    claude mcp add --transport http "Atlassian" https://mcp.atlassian.com/v1/mcp
  ```
- Si existe → continuar con B.

**B. Autenticación y `cloudId`:**
- Si retorna error de autenticación → marcar `MCP_AVAILABLE = false` y mostrar:
  ```
  ⚠️ MCP Atlassian no autenticado — las notas internas de resolución no se postearán.
  Ejecutá /mcp para completar el flujo OAuth.
  ```
- Si retorna recursos: elegir el que represente `mercadolibre.atlassian.net` y guardar su `cloudId`. Marcar `MCP_AVAILABLE = true`.
- Si `mercadolibre.atlassian.net` no aparece → marcar `MCP_AVAILABLE = false` con warning similar.

**C. Capacidad de nota interna JSM:**
Confirmar que el proveedor expone capacidad de crear **nota interna de Jira Service Management** (no solo comentario público). `addCommentToJiraIssue` por sí sola no alcanza si solo crea comentarios públicos.

- Si solo hay capacidad de comentario público y no nota interna → marcar `MCP_AVAILABLE = false` y mostrar:
  ```
  ⚠️ El MCP de Atlassian disponible no expone capacidad de nota interna JSM — las notas internas de resolución no se postearán.
  Las asignaciones se realizarán normalmente para evitar publicar información interna al reporter.
  ```
- Solo marcar `MCP_AVAILABLE = true` cuando pasaron A, B y esta verificación de capacidad de nota interna.

**D. Si `MCP_AVAILABLE = false`:** el paso 11 se salta automáticamente para todos los tickets (no se intenta postear la nota). La tabla final del paso 12 muestra `— Skip` en la columna Nota para todos los tickets.

## Algoritmo

1. Obtener todos los tickets abiertos **soportados por este flujo** (solo `Incident` y `Service Request`; cualquier otro issue type de SSHP/Groot queda fuera de alcance y no debe tocarse):
   ```bash
   acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type IN (Incident, \"Service Request\") AND resolution = Unresolved ORDER BY created DESC"
   ```
2. Filtrar solo los que **no tienen assignee** (campo `assignee` vacío o null).
3. Ordenar por urgencia descendente (score 5 primero — ver `classification.md`).
4. **Barajar el TEAM una sola vez (shuffle aleatorio) y crear los archivos scratch.** El shuffle se ejecuta **una única vez por corrida**. Generar un orden aleatorio real con entropía del sistema (no inventar el orden a mano). En una sola llamada Bash, crear con `mktemp` el archivo de orden `$ORDER` (los emails del TEAM barajados, uno por línea) y copiarlo a la cola de trabajo `$QUEUE`, con este one-liner portable (macOS + Linux):
   ```bash
   ORDER=$(mktemp -t groot-assign-order.XXXXXX 2>/dev/null || mktemp)
   QUEUE=$(mktemp -t groot-assign-queue.XXXXXX 2>/dev/null || mktemp)
   awk 'BEGIN{srand()} {print rand()"\t"$0}' <<'EOF' | sort -n | cut -f2- > "$ORDER"
   <email del miembro 1>
   <email del miembro 2>
   ...
   <email del miembro N>
   EOF
   cp "$ORDER" "$QUEUE"
   echo "ORDER=$ORDER QUEUE=$QUEUE"   # recordar estos paths para el resto de la corrida
   ```
   `$ORDER` es el **orden barajado de esta corrida** y **no se vuelve a tocar** (el shuffle no se repite). `$QUEUE` es la **cola de trabajo**: su primera línea es siempre el próximo a asignar. Guardar ambos paths para reutilizarlos en los pasos siguientes.
5. Para cada ticket sin asignar, tomar el **primer email** de `$QUEUE` (`head -n1 "$QUEUE"`) — reparto **sin repetición**. Cuando `$QUEUE` quede vacío (más tickets que miembros), **rellenarla con el mismo orden barajado** copiando `$ORDER` de nuevo (`cp "$ORDER" "$QUEUE"`) — **no se vuelve a barajar** — y seguir. Así nadie recibe un segundo ticket hasta que todos hayan recibido uno, y las rondas siguientes repiten el mismo orden del shuffle inicial.
6. Para cada ticket sin asignar:

   a. `assignee` = primer email de `$QUEUE`:
      ```bash
      head -n1 "$QUEUE"
      ```
      Si `$QUEUE` está vacío, rellenarla con `cp "$ORDER" "$QUEUE"` (paso 5) y volver a leer.

   b. **Transicionar a "En curso" PRIMERO** — en una llamada Bash **separada**:
      ```bash
      acli jira workitem transition --key <KEY> --status "En curso" --yes
      ```
      - Si falla: reportar el error, **NO eliminar la línea de `$QUEUE`** (el email queda al frente para que ese miembro no pierda su turno) y continuar con el siguiente ticket.
      - ⚠️ **CRÍTICO**: la transición auto-asigna al usuario autenticado de ACLI, pisando cualquier asignación previa. Por eso la asignación debe ir en una llamada Bash **separada e independiente** — nunca encadenar ambos comandos con `&&` en un solo Bash call, ya que la transición puede completarse de forma asíncrona en Jira y terminar pisando el assign.

   c. Asignar responsable en una **nueva llamada Bash separada**, después de que la transición haya retornado:
      ```bash
      acli jira workitem assign --key <KEY> --assignee <email> --yes
      ```
      - El `<email>` es el que se leyó de `$QUEUE` en el paso 6a. Ya es un email completo del TEAM; no construirlo desde el username.
      - Si falla: reportar el error, **NO eliminar la línea de `$QUEUE`** (la transición ya ocurrió, pero se reporta).

   d. Verificar asignación en una **nueva llamada Bash separada**:
      ```bash
      acli jira workitem view <KEY>
      ```
      → leer el campo `Assignee:`
      - Si `Assignee` != `<email>`: reintentar el assign una vez más (`acli jira workitem assign --key <KEY> --assignee <email> --yes`).
        - Si sigue sin coincidir: reportar ⚠️ con el ticket y el assignee incorrecto, **NO eliminar la línea de `$QUEUE`**.
      - Si `Assignee` == `<email>`: continuar al paso e.

   e. Si transición + asignación + verificación exitosas:
      - **Consumir el email**: eliminar la primera línea de `$QUEUE` en una llamada Bash:
        ```bash
        tail -n +2 "$QUEUE" > "$QUEUE.tmp" && mv "$QUEUE.tmp" "$QUEUE"
        ```
        Así ese miembro no vuelve al pool hasta la próxima ronda (cuando se rellena `$QUEUE` desde `$ORDER`).

7. **Limpieza obligatoria.** Al terminar el loop —tanto si completó como si abortó por un error— eliminar los archivos scratch:
   ```bash
   rm -f "$QUEUE" "$ORDER"
   ```
   No persiste estado entre corridas: la próxima ejecución (de quien sea) creará `$ORDER` y `$QUEUE` nuevos y barajará desde cero.

8. Mostrar tabla preliminar de asignación:

```
Asignaciones realizadas (N tickets):
| Key          | Summary                  | Transición  | Asignado a   | Estado  |
|--------------|--------------------------|-------------|--------------|---------|
| SSHP-XXXXX   | ...                      | ✓ En curso   | frgonzalez   | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✓ En curso   | lpadularrosa | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✗ Error     | —            | ✗ Skip  |

Reparto de esta corrida:
  | Miembro      | Tickets |
  |--------------|---------|
  | frgonzalez   | 1       |
  | lpadularrosa | 1       |
```

- La nota interna de resolución **todavía no se postea en este punto**. Primero hay que detectar si el ticket será derivado o descartado en los pasos 9 y 10.

Si no hay tickets sin asignar, mostrar: "✅ No hay tickets sin assignee en la cola."

## 9. Detección post-asignación de tickets derivables

Solo ejecutar este paso si hubo al menos un ticket con estado **✓ OK** en la tabla del paso 8.

**9a. Cargar reglas de derivación:**
Leer `$SKILL_DIR/knowledge/triage-rules.md`.

**9b. Evaluar cada ticket ✓ OK:**
Para cada ticket asignado exitosamente, obtener su contenido actualizado con:
```bash
acli jira workitem view <KEY>
```
Aplicar **únicamente las reglas R-DER** del algoritmo de triage (misma lógica que el paso 2b de `derive.md`). Tomar la primera regla que matchee. Clasificar el match como:
- **⚡ alta confianza**: la regla está marcada con ⚡ en `triage-rules.md` y ninguna condición de escape es ambigua en el texto del ticket.
- **normal**: cualquier otro match (sin ⚡, o con señal de escape ambigua).

**9c. Si ningún ticket matchea una regla R-DER:** no mostrar nada adicional y continuar al paso 10.

**9d. Si uno o más tickets matchean:**

Separar en dos grupos y mostrar:

```
🔀 Tickets derivables detectados (N):

⚡ Alta confianza — se derivan automáticamente (M tickets):
| Key          | Summary                  | Regla     | Equipo destino |
|--------------|--------------------------|-----------|----------------|
| SSHP-XXXXX   | ...                      | R-DER-09  | IAM Soporte    |

❓ Requieren confirmación (K tickets):
| Key          | Summary                  | Regla     | Equipo destino |
|--------------|--------------------------|-----------|----------------|
| SSHP-XXXXX   | ...                      | R-DER-04  | Helpdesk IA    |

¿Derivar los K tickets de confirmación manual? (sí / no)
```

Si solo hay tickets ⚡, omitir la tabla de confirmación y la pregunta.
Si solo hay tickets no-⚡, omitir la tabla ⚡.

**9e. Ejecución:**

- **Tickets ⚡**: ejecutar derivación **sin esperar confirmación** (análoga a `GROOT_QUEUE_AUTORUN=true` para ese subset). Invocar el flujo de `$SKILL_DIR/subcommands/derive.md`. Al registrar en el log de auditoría, usar `source = "auto-assign-autoconfianza"`.

- **Tickets no-⚡**:
  - **Si `GROOT_QUEUE_AUTORUN=true`:** proceder directamente. Al registrar, usar `source = "auto-run"`.
  - **Si no (modo interactivo):**
    - **Sí** (o "s", "yes", "y"): ejecutar derivación. Al registrar, usar `source = "auto-assign"`.
    - **No**: mostrar: > "Derivación omitida. Podés ejecutarla luego con `/groot-queue derive <KEY1> <KEY2> ...`" y continuar al paso 10.

## 10. Detección post-asignación de tickets descartables

Solo ejecutar este paso si hubo al menos un ticket con estado **✓ OK** en la tabla del paso 8 que **no fue incluido como derivable en el paso 9**.

**10a. Cargar reglas de descarte:**
Si `triage-rules.md` ya fue leído en el paso 9a, reutilizar. Si no, leer `$SKILL_DIR/knowledge/triage-rules.md`.

**10b. Evaluar cada ticket ✓ OK no derivable:**
Para cada ticket asignado exitosamente que no matcheó una regla R-DER en el paso 9:
- Si el contenido ya fue obtenido en el paso 9b, reutilizarlo; si no, obtenerlo con:
  ```bash
  acli jira workitem view <KEY>
  ```
- Aplicar **únicamente las reglas R-DESC del algoritmo de triage** de `triage-rules.md`, en orden: R-DESC-03, R-DESC-06, R-DESC-07, R-DESC-08, R-DESC-04, R-DESC-09, R-DESC-05, R-DESC-02, R-DESC-10, R-DESC-01, R-DESC-11, R-DESC-12.
- Tomar la primera regla que matchee. Clasificar el match como:
  - **⚡ alta confianza**: la regla está marcada con ⚡ en `triage-rules.md` **y** el texto del ticket no contiene señal de escape (no menciona haber intentado la operación con error, no hay descripción ambigua o incompleta).
  - **normal**: regla sin ⚡, o regla ⚡ con señal de escape ambigua.
- Las verificaciones previas (R-DESC-03, R-DESC-04, R-DESC-05, R-DESC-06, R-DESC-07, R-DESC-08) que requieren inspección en Groot admin: si no es posible confirmarlas desde el contenido del ticket, marcar como `REVISAR_MANUAL` y no incluirlo en ninguno de los dos grupos.

**10c. Si ningún ticket matchea una regla R-DESC:** no mostrar nada adicional y continuar al paso 11.

**10d. Si uno o más tickets matchean:**

Separar en dos grupos y mostrar:

```
⛔ Tickets descartables detectados (N):

⚡ Alta confianza — se descartan automáticamente (M tickets):
| Key          | Summary                  | Regla      |
|--------------|--------------------------|------------|
| SSHP-XXXXX   | ...                      | R-DESC-02  |
| Comentario: "Hola, desde Groot/Kraken Soporte atendemos exclusivamente errores sistémicos..."

❓ Requieren confirmación (K tickets):
| Key          | Summary                  | Regla      | Acción          |
|--------------|--------------------------|------------|-----------------|
| SSHP-XXXXX   | ...                      | R-DESC-04  | Cerrar Won't Do |

⚠️ Revisión manual requerida (J tickets):
| Key          | Summary                  | Motivo                         |
|--------------|--------------------------|--------------------------------|
| SSHP-XXXXX   | ...                      | Verificación previa incompleta |

¿Descartar los K tickets de confirmación manual? (sí / no)
```

Si solo hay tickets ⚡, omitir la tabla de confirmación y la pregunta.
Si solo hay tickets no-⚡, omitir la tabla ⚡.

Al explicar este paso en modo ayuda, usar explícitamente las frases `R-DESC`, `tickets descartables` y `¿Descartar los K tickets de confirmación manual?`.

**10e. Ejecución:**

- **Tickets ⚡**: ejecutar descarte **sin esperar confirmación**. Invocar el flujo de `$SKILL_DIR/subcommands/discard.md` con `source = "auto-assign-autoconfianza"`. Usar el **comentario universal** de la sección `## Comentario universal — auto-descarte de alta confianza` de `triage-rules.md` (con la variante específica de R-DESC-14 si corresponde) en lugar del comentario por regla.

- **Tickets no-⚡**:
  - **Si `GROOT_QUEUE_AUTORUN=true`:** proceder directamente como si la respuesta fuera "sí". La confirmación ya fue obtenida implícitamente — al llegar al paso 4 de `discard.md`, omitir la pregunta. Al registrar, usar `source = "auto-run"`.
  - **Si no (modo interactivo):**
    - **Sí** (o "s", "yes", "y"): ejecutar el flujo de `$SKILL_DIR/subcommands/discard.md`. La confirmación ya fue obtenida — omitir la pregunta interna de `discard.md`. Al registrar, usar `source = "auto-assign"`.
    - **No**: mostrar: > "Descarte omitido. Podés ejecutarlo luego con `/groot-queue discard <KEY1> <KEY2> ...`" y continuar al paso 11.

## 11. Postear notas internas solo para tickets asignados que siguen siendo Groot

Ejecutar este paso **después** de las detecciones de derivación y descarte. La nota se postea únicamente para tickets con estado **✓ OK** que:
- **no** matchearon una regla `R-DER` en el paso 9, y
- **no** matchearon una regla `R-DESC` en el paso 10.

Si un ticket fue identificado como derivable o descartable, **no** postear la guía de resolución de Groot aunque el usuario haya decidido no ejecutar la derivación o el descarte todavía. En esos casos la nota sería ruido o podría orientar mal al siguiente equipo.

**Procedimiento por ticket elegible:**

1. Leer las referencias (reutilizar si ya fueron cargadas en pasos anteriores):
   - `$SKILL_DIR/knowledge/classification.md`
   - `$SKILL_DIR/knowledge/runbooks.md`
   - `$SKILL_DIR/knowledge/assignment-note-template.md`
2. Obtener el contenido actualizado del ticket en una llamada separada antes de analizarlo:
   ```bash
   acli jira workitem view <KEY>
   ```
   Reutilizar ese output para toda la generación de la nota en este paso.
3. Con el contenido del ticket recién obtenido:
   - Clasificar el ticket en Dimensión 1 (categoría) y Dimensión 2 (urgencia).
   - Buscar el runbook de esa categoría en `runbooks.md`.
   - Resolver primero la carpeta real de `solutions/` usando el mapeo de `classification.md` (por ejemplo: `Jerarquía/Líder` → `hierarchy-leader`, `Warehouse/Site` → `warehouse-assignment`, `Roles/Permisos` → `role-permission`, `Otro` → `queue-management`).
   - Buscar casos previos similares en `$SKILL_DIR/knowledge/solutions/<categoria-slug>/`.
4. Generar la nota siguiendo estrictamente el template:
   - Completar cada campo (`{CATEGORIA}`, `{DIAGNOSTICO}`, `{PASOS_RESOLUCION}`, etc.) según las reglas de llenado del template.
   - Respetar las restricciones: español neutro, sin códigos de regla, sin PII, sin texto verbatim no sanitizado.
   - **Incluir siempre el slug `<!-- groot-auto-guide -->` como última línea del body** (requerido para detección de idempotencia).
5. Postear la nota como **nota interna de Jira Service Management** usando MCP Atlassian:
   - `cloudId`: valor de `mercadolibre.atlassian.net` (resuelto en la pre-condición MCP Atlassian).
   - `issueIdOrKey`: `"<KEY>"`
   - `commentBody`: la nota generada en el paso 4 (con el slug al final)
   - `contentFormat`: `"markdown"`
   - `commentVisibility`: `{"type": "role", "value": "Service Desk Team"}`

   > ⚠️ **OBLIGATORIO**: el parámetro `commentVisibility` con valor `{"type": "role", "value": "Service Desk Team"}` es lo que hace que el comentario sea una **nota interna** (solo visible para agentes, no para el reporter en el portal). Sin este parámetro, `addCommentToJiraIssue` crea un comentario **público** que el reporter puede ver — esto expone información interna de diagnóstico y runbooks al cliente. Nunca omitir `commentVisibility`.
6. **Si la nota se posteó exitosamente**, agregar el label `groot-guide-posted` al ticket usando `editJiraIssue` (MCP Atlassian):
   - Leer las labels actuales del ticket (del contenido ya obtenido en paso 2).
   - Agregar `groot-guide-posted` a la lista existente (merge, no reemplazar).
   - Si falla el label: registrar warning pero **no abortar** — la nota ya fue posteada y el slug garantiza la idempotencia como fallback.
7. **Si falla la nota**: registrar `✗ Nota` para ese ticket en la tabla final del paso 12. **No abortar** — la asignación ya fue completada exitosamente.
8. **Si tiene éxito (nota + label)**: registrar `✓ Nota` para ese ticket en la tabla final del paso 12.

> ⚠️ Este paso es **best-effort**: un fallo al postear la nota no afecta la asignación ni bloquea el flujo. El ticket queda asignado y en progreso de todas formas.

## 12. Mostrar tabla final consolidada

```
Resultado final (N tickets):
| Key          | Summary                  | Transición  | Asignado a   | Nota    | Estado  |
|--------------|--------------------------|-------------|--------------|---------|---------|
| SSHP-XXXXX   | ...                      | ✓ En curso  | frgonzalez   | ✓ Nota  | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✓ En curso  | lpadularrosa | — Skip  | ➡️ DERIVABLE |
| SSHP-XXXXX   | ...                      | ✓ En curso  | jperez       | — Skip  | ⛔ DESCARTABLE |
| SSHP-XXXXX   | ...                      | ✗ Error     | —            | — Skip  | ✗ Skip  |
```

- La columna **Nota** muestra `✓ Nota` si la nota interna se posteó con éxito, `✗ Nota` si falló, o `— Skip` si MCP no estaba disponible, el ticket no fue asignado exitosamente, o el ticket fue identificado como derivable/descartable.
- Los tickets identificados como `R-DER` o `R-DESC` deben quedar claramente marcados como `➡️ DERIVABLE` o `⛔ DESCARTABLE` en la columna Estado hasta que el flujo automático correspondiente los procese o el usuario decida resolverlos manualmente.
