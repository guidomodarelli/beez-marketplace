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

1. **Omitir la pregunta de confirmación** del paso 4.
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

Si no hay tickets sin assignee, mostrar: "✅ No hay tickets sin assignee en la cola." y terminar.

3. Leer `$SKILL_DIR/knowledge/triage-rules.md` y obtener el contenido de **todos** los tickets filtrados (en paralelo si es posible):
   ```bash
   acli jira workitem view <KEY>
   ```
   Para cada ticket, aplicar el algoritmo de triage completo en orden: primero R-DER (tomar la primera que matchee), luego R-DESC (si ninguna R-DER matcheó). Clasificar cada ticket en una de estas categorías:

   - **`DERIVAR-AC`**: matchea una regla R-DER marcada con ⚡ y ninguna condición de escape es ambigua.
   - **`DERIVAR`**: matchea una regla R-DER sin ⚡, o con señal de escape ambigua.
   - **`DESCARTAR-AC`**: matchea una regla R-DESC marcada con ⚡ y el texto del ticket no contiene señal de escape.
   - **`DESCARTAR`**: matchea una regla R-DESC sin ⚡, o con señal de escape ambigua.
   - **`REVISAR_MANUAL`**: matchea una regla que requiere verificación en Groot admin que no puede confirmarse desde el contenido del ticket.
   - **`ASIGNAR`**: no matchea ninguna regla R-DER ni R-DESC, o su veredicto es `VALIDO_GROOT`.

   Las verificaciones previas de R-DESC-03, 04, 05, 06, 07, 08 que requieren Groot admin: si no es posible confirmarlas desde el contenido, clasificar como `REVISAR_MANUAL`.

4. Mostrar el plan consolidado y ejecutar confirmaciones por nivel:

```
📋 Plan de corrida — N tickets sin assignee
═══════════════════════════════════════════════════════════════

🔀 Para derivar (M tickets):
  ⚡ Alta confianza:
  | Key          | Summary  | Regla    | Destino     |
  | SSHP-XXXXX   | ...      | R-DER-09 | IAM Soporte |

  ❓ Confianza estándar:
  | Key          | Summary  | Regla    | Destino      |
  | SSHP-XXXXX   | ...      | R-DER-04 | Helpdesk IA  |

⛔ Para descartar (K tickets):
  ⚡ Alta confianza:
  | Key          | Summary  | Regla     |
  | SSHP-XXXXX   | ...      | R-DESC-02 |
  Comentario: "Hola, desde Groot/Kraken Soporte atendemos exclusivamente errores sistémicos..."

  ❓ Confianza estándar:
  | Key          | Summary  | Regla     |
  | SSHP-XXXXX   | ...      | R-DESC-04 |

⚠️ Revisión manual requerida (J tickets — no se tocan en esta corrida):
  | Key          | Summary  | Motivo                         |
  | SSHP-XXXXX   | ...      | Verificación previa incompleta |

✅ Para asignar a Groot (P tickets):
  | Key          | Summary  | Urgencia |
  | SSHP-XXXXX   | ...      | 🔴 Alta  |

═══════════════════════════════════════════════════════════════
Derivar: M  |  Descartar: K  |  Revisión manual: J  |  Asignar: P
```

Omitir secciones vacías.

Si `GROOT_QUEUE_AUTORUN=true`, omitir todas las confirmaciones y proceder directamente con todos los tickets. Si no, seguir el flujo de confirmación diferenciado:

**Confirmación ⚡ (lote):**

Si hay tickets ⚡ (DERIVAR-AC o DESCARTAR-AC):
```
⚡ Alta confianza — N tickets
¿Procesar todos en lote? (sí / no)
```
- **Sí**: todos los ⚡ van al paso 5.
- **No**: todos los ⚡ se omiten (quedan sin acción; el usuario puede ejecutarlos luego con `/groot-queue derive` o `/groot-queue discard`).

**Confirmación ❓ (uno por uno):**

Si hay tickets ❓ (DERIVAR o DESCARTAR), procesarlos en orden, mostrando para cada uno:

```
[X/K] SSHP-XXXXX — R-DER-04 → Helpdesk IA
  Summary: "..."
  Señales detectadas: <señales concretas que activaron la regla>
¿Derivar? (s)í / (n)o / (q) procesar todos los restantes
```

o para descarte:

```
[X/K] SSHP-XXXXX — R-DESC-04 → Won't Do
  Summary: "..."
  Señales detectadas: <señales concretas que activaron la regla>
¿Descartar? (s)í / (n)o / (q) descartar todos los restantes
```

- **(s)í**: el ticket va al paso 5.
- **(n)o**: el ticket se omite para esta corrida. Mostrar: > "Omitido. Podés ejecutarlo luego con `/groot-queue derive/discard SSHP-XXXXX`."
- **(q)**: el ticket actual y todos los ❓ restantes van al paso 5 (equivale a "sí" en lote para los que quedan).

Mezclar derivaciones y descartes en el mismo loop ordenado por key (no separar en dos rondas).

5. **Fase de derive/discard** — ejecutar **primero**, antes de cualquier asignación:

   Solo se procesan los tickets aprobados en el paso 4 (⚡ aprobados en lote + ❓ aprobados individualmente o por `q`). Los tickets ❓ rechazados con `n` se omiten y se registran como `"omitido"` en la tabla final.

   **Derivar:** Invocar el flujo de `$SKILL_DIR/subcommands/derive.md` para los tickets `DERIVAR-AC` y `DERIVAR` aprobados (la confirmación ya fue obtenida en el paso 4 — omitir la confirmación interna de `derive.md`). Al registrar en el log de auditoría:
   - `DERIVAR-AC`: usar `source = "auto-assign-autoconfianza"`.
   - `DERIVAR`: usar `source = "auto-assign"`.
   - `GROOT_QUEUE_AUTORUN=true`: usar `source = "auto-run"` para todos.

   **Descartar:** Invocar el flujo de `$SKILL_DIR/subcommands/discard.md` para los tickets `DESCARTAR-AC` y `DESCARTAR` aprobados (la confirmación ya fue obtenida en el paso 4 — omitir la confirmación interna de `discard.md`). Al registrar en el log de auditoría:
   - `DESCARTAR-AC`: usar `source = "auto-assign-autoconfianza"`. Usar el **comentario universal** de `triage-rules.md` (con la variante de R-DESC-14 si corresponde) en lugar del comentario por regla.
   - `DESCARTAR`: usar `source = "auto-assign"`. Usar el comentario sugerido de la regla.
   - `GROOT_QUEUE_AUTORUN=true`: usar `source = "auto-run"` para todos.

   Los tickets `REVISAR_MANUAL` y los ❓ omitidos **no se tocan** en este paso.

6. **Fase de asignación** — solo para los tickets clasificados como `ASIGNAR` en el paso 3. Los tickets derivados, descartados o de revisión manual **no participan del reparto**.

   **Barajar el TEAM una sola vez (shuffle aleatorio) y crear los archivos scratch.** El shuffle se ejecuta **una única vez por corrida**. Generar un orden aleatorio real con entropía del sistema (no inventar el orden a mano). En una sola llamada Bash, crear con `mktemp` el archivo de orden `$ORDER` (los emails del TEAM barajados, uno por línea) y copiarlo a la cola de trabajo `$QUEUE`, con este one-liner portable (macOS + Linux):
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

   Para cada ticket `ASIGNAR`, tomar el **primer email** de `$QUEUE` (`head -n1 "$QUEUE"`) — reparto **sin repetición**. Cuando `$QUEUE` quede vacío (más tickets que miembros), **rellenarla con el mismo orden barajado** copiando `$ORDER` de nuevo (`cp "$ORDER" "$QUEUE"`) — **no se vuelve a barajar** — y seguir.

   Para cada ticket `ASIGNAR`:

   a. `assignee` = primer email de `$QUEUE`:
      ```bash
      head -n1 "$QUEUE"
      ```
      Si `$QUEUE` está vacío, rellenarla con `cp "$ORDER" "$QUEUE"` y volver a leer.

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

   e. Si transición + asignación + verificación exitosos:
      - **Consumir el email**: eliminar la primera línea de `$QUEUE` en una llamada Bash:
        ```bash
        tail -n +2 "$QUEUE" > "$QUEUE.tmp" && mv "$QUEUE.tmp" "$QUEUE"
        ```
        Así ese miembro no vuelve al pool hasta la próxima ronda.

7. **Limpieza obligatoria.** Al terminar el loop —tanto si completó como si abortó por un error— eliminar los archivos scratch:
   ```bash
   rm -f "$QUEUE" "$ORDER"
   ```
   No persiste estado entre corridas.

8. Mostrar tabla de asignaciones:

```
Asignaciones realizadas (P tickets):
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

Si no hay tickets `ASIGNAR` (todos fueron derivados/descartados), mostrar: "✅ Todos los tickets sin assignee fueron derivados o descartados — no quedan tickets para asignar."

## 9. Postear notas internas para tickets asignados

Ejecutar este paso solo para los tickets clasificados como `ASIGNAR` en el paso 3 que terminaron con estado **✓ OK** en el paso 8. Los tickets derivados, descartados o de revisión manual no reciben nota interna.

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
7. **Si falla la nota**: registrar `✗ Nota` para ese ticket en la tabla final del paso 10. **No abortar** — la asignación ya fue completada exitosamente.
8. **Si tiene éxito (nota + label)**: registrar `✓ Nota` para ese ticket en la tabla final del paso 10.

> ⚠️ Este paso es **best-effort**: un fallo al postear la nota no afecta la asignación ni bloquea el flujo. El ticket queda asignado y en progreso de todas formas.

## 10. Mostrar tabla final consolidada

```
Resultado final (N tickets sin assignee procesados):

Derivados/Descartados:
| Key          | Summary  | Acción       | Regla     | Estado         |
|--------------|----------|--------------|-----------|----------------|
| SSHP-XXXXX   | ...      | ➡️ Derivado   | R-DER-09  | ✓ OK           |
| SSHP-XXXXX   | ...      | ⛔ Descartado  | R-DESC-02 | ✓ OK           |
| SSHP-XXXXX   | ...      | ⏭️ Omitido    | R-DER-04  | Sin acción     |
| SSHP-XXXXX   | ...      | ⚠️ Manual     | R-DESC-06 | Sin acción     |

Asignaciones:
| Key          | Summary  | Transición  | Asignado a   | Nota    | Estado |
|--------------|----------|-------------|--------------|---------|--------|
| SSHP-XXXXX   | ...      | ✓ En curso  | frgonzalez   | ✓ Nota  | ✓ OK   |
| SSHP-XXXXX   | ...      | ✓ En curso  | lpadularrosa | — Skip  | ✓ OK   |
| SSHP-XXXXX   | ...      | ✗ Error     | —            | — Skip  | ✗ Skip |

Resumen: N total  |  M derivados/descartados  |  K omitidos  |  J revisión manual  |  P asignados  |  E errores
```

- **⏭️ Omitido**: el usuario respondió `n` en la confirmación individual. El ticket sigue sin assignee; ejecutar luego con `/groot-queue derive SSHP-XXXXX` o `/groot-queue discard SSHP-XXXXX`.
