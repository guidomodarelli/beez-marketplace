---
description: Asigna en Jira todos los tickets sin responsable balanceando la carga abierta del equipo (menor backlog primero, azar como desempate).
---

# /groot-queue:assign-unassigned

Asignar todos los tickets sin responsable **balanceando la carga del equipo**: cada ticket va al miembro con menos tickets abiertos en SSHP/Groot, usando el azar solo para desempatar. **Este command escribe en Jira** (transiciona estado + asigna responsable). Ver también `derive`, que escribe comentario + transición de estado.

## Por qué balanceo de carga con la verdad de Jira

El objetivo es **equilibrar la carga total** del equipo, no solo repartir parejo los tickets de una corrida. Antes existía un `next_assignee_index` guardado localmente, pero como cada miembro del team corría el comando con su propio índice desfasado, la rotación terminaba siendo desigual. Ahora, al arranque de cada corrida se trae desde **Jira (la fuente de verdad compartida)** cuántos incidentes no resueltos de SSHP/Groot —el mismo universo de tickets que se asignan— tiene a su nombre cada miembro del TEAM; ese conteo es el **peso**. Cada ticket nuevo se asigna al miembro de menor peso (desempatando al azar) y el peso se incrementa en memoria tras cada asignación exitosa. Como todos leen los mismos contadores de Jira, la equidad no depende del orden en que cada persona ejecute el comando ni de ninguna cache local.

Durante la corrida se usa **un archivo scratch efímero** (creado con `mktemp`, fuera del repo) que guarda la tabla de carga (`<peso>\t<email>`) y se actualiza por cada asignación. Es un detalle de implementación para que el loop sea robusto a lo largo de muchas llamadas Bash; **se crea fresco en cada corrida y se elimina al terminar o abortar**, así que no es cache compartida ni sobrevive entre ejecuciones.

## Pre-condición: TEAM

Leer el `TEAM` desde `~/.claude/skills/groot-queue/SKILL.md`. Si está vacío, abortar con mensaje:
> "Configurá la sección TEAM del SKILL.md antes de usar este comando."

## Pre-condición: MCP Atlassian (para el snapshot de carga)

El snapshot de carga inicial se obtiene con el **MCP de Atlassian**. **Verificar antes de proceder. Si alguno de estos pasos falla, abortar y no continuar.**

**A. Disponibilidad de herramientas:**
Intentar llamar `mcp__Atlassian__getAccessibleAtlassianResources` (o herramienta equivalente si el proveedor usa otro prefijo).

Si la herramienta **no existe** en el contexto → abortar con:
```
❌ MCP Atlassian no disponible.

/groot-queue:assign-unassigned necesita el MCP de Atlassian para leer la carga actual del equipo.
Instalalo con:
  claude mcp add --transport http "Atlassian" https://mcp.atlassian.com/v1/mcp
Luego completá el flujo OAuth con /mcp dentro de Claude Code.
Podés verificar el entorno completo con /groot-queue setup.
```

**B. Autenticación y `cloudId`:**
Usar el resultado de la llamada anterior:
- Si retorna error de autenticación (401 / 403 o equivalente) → abortar indicando que se ejecute `/mcp` y se complete el OAuth para `mercadolibre.atlassian.net`.
- Si retorna recursos: elegir el que represente `mercadolibre.atlassian.net` y guardar su `cloudId` (se reutiliza en el paso 4).
- Si `mercadolibre.atlassian.net` **no aparece** → abortar indicando verificar el workspace autorizado en el OAuth y correr `/groot-queue setup`.

## Algoritmo

1. Obtener los incidentes abiertos **sin responsable** (el filtro de no-asignados va en el propio JQL con `assignee IS EMPTY`):
   ```bash
   acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type = Incident AND resolution = Unresolved AND assignee IS EMPTY ORDER BY created DESC"
   ```
2. Confirmar que ninguno trae `assignee` (el JQL ya excluye los asignados; descartar cualquier residuo con `assignee` no vacío por las dudas).
3. Ordenar por urgencia descendente (score 5 primero — ver `classification.md`).
4. **Construir el snapshot de carga del TEAM** (peso inicial) con el MCP de Atlassian.

   **4a. Consultar Jira** vía `mcp__Atlassian__searchJiraIssuesUsingJql` (o equivalente):
   - `cloudId`: el validado en la pre-condición para `mercadolibre.atlassian.net`.
   - `jql`: contar la carga sobre **el mismo universo de tickets que se asignan** (paso 1) — incidentes no resueltos de SSHP/Groot — pero filtrando por los emails del TEAM:
     ```
     project = SSHP AND Squad = Groot AND type = Incident AND resolution = Unresolved AND assignee in ("<email1>", "<email2>", ..., "<emailN>")
     ```
     Ambas consultas comparten la misma base (`project = SSHP AND Squad = Groot AND type = Incident AND resolution = Unresolved`) y solo difieren en el filtro de assignee: el paso 1 toma los **sin responsable** (`assignee IS EMPTY`) y este paso toma los **del TEAM** (`assignee in (...)`). Son dos subconjuntos complementarios del mismo universo.
   - `fields`: solo `["assignee"]` (no necesitamos más).
   - Paginar hasta traer todos los resultados (seguir `nextPageToken` / `startAt` hasta agotar).

   **4b. Tabular el peso por miembro** y escribirlo al archivo scratch efímero. Cada miembro del TEAM arranca en `0`; sumar 1 por cada ticket cuyo `assignee` coincida con su email. Los miembros sin tickets quedan en `0` (peso 0); ignorar cualquier assignee que aparezca en Jira pero **no** esté en el TEAM.
      ```bash
      LOAD=$(mktemp -t groot-assign-load.XXXXXX 2>/dev/null || mktemp)
      # escribir una línea por miembro del TEAM con: <peso inicial>\t<email>
      printf '%s\t%s\n' \
        <peso_email1> "<email1>" \
        <peso_email2> "<email2>" \
        ... \
        <peso_emailN> "<emailN>" > "$LOAD"
      echo "LOAD=$LOAD"   # recordar este path para el resto de la corrida
      ```
      `$LOAD` es la **tabla de carga** de esta corrida. Guardar el path para reutilizarlo en los pasos siguientes.

5. Para cada ticket sin asignar, asignar al **miembro de menor peso**, desempatando **al azar** (entropía del sistema, no a mano). El peso se incrementa solo tras una asignación exitosa, así que a medida que avanza la corrida la carga se equilibra sola.
6. Para cada ticket sin asignar (en orden de urgencia):

   a. Elegir `assignee` = miembro de menor peso en `$LOAD`, con desempate aleatorio:
      ```bash
      awk 'BEGIN{srand()} {print $1"\t"rand()"\t"$2}' "$LOAD" | sort -k1,1n -k2,2n | head -n1 | cut -f3
      ```
      El `<email>` resultante ya es un email completo del TEAM; no construirlo desde el username.

   b. **Transicionar a "In Progress" PRIMERO** — en una llamada Bash **separada**:
      ```bash
      acli jira workitem transition --key <KEY> --status "In Progress" --yes
      ```
      - Si falla: reportar el error, **NO incrementar el peso** (no se asignó nada) y continuar con el siguiente ticket.
      - ⚠️ **CRÍTICO**: la transición auto-asigna al usuario autenticado de ACLI, pisando cualquier asignación previa. Por eso la asignación debe ir en una llamada Bash **separada e independiente** — nunca encadenar ambos comandos con `&&` en un solo Bash call, ya que la transición puede completarse de forma asíncrona en Jira y terminar pisando el assign.

   c. Asignar responsable en una **nueva llamada Bash separada**, después de que la transición haya retornado:
      ```bash
      acli jira workitem assign --key <KEY> --assignee <email> --yes
      ```
      - Si falla: reportar el error, **NO incrementar el peso** (la transición ya ocurrió, pero se reporta).

   d. Verificar asignación en una **nueva llamada Bash separada**:
      ```bash
      acli jira workitem view <KEY>
      ```
      → leer el campo `Assignee:`
      - Si `Assignee` != `<email>`: reintentar el assign una vez más (`acli jira workitem assign --key <KEY> --assignee <email> --yes`).
        - Si sigue sin coincidir: reportar ⚠️ con el ticket y el assignee incorrecto, **NO incrementar el peso**.
      - Si `Assignee` == `<email>`: continuar al paso e.

   e. Si transición + asignación + verificación exitosas:
      - **Incrementar el peso** del miembro asignado en `$LOAD`, en una llamada Bash:
        ```bash
        awk -v e="<email>" 'BEGIN{OFS="\t"} $2==e{$1=$1+1} {print}' "$LOAD" > "$LOAD.tmp" && mv "$LOAD.tmp" "$LOAD"
        ```
        Así el siguiente ticket considera la carga actualizada y el reparto tiende al equilibrio.
      - Continuar al siguiente ticket.

7. **Limpieza obligatoria.** Al terminar el loop —tanto si completó como si abortó por un error— eliminar el archivo scratch:
   ```bash
   rm -f "$LOAD"
   ```
   No persiste estado entre corridas: la próxima ejecución (de quien sea) leerá la carga fresca desde Jira y creará un `$LOAD` nuevo.

8. Mostrar tabla de resultados:

```
Asignaciones realizadas (N tickets):
| Key          | Summary                  | Transición  | Asignado a   | Estado  |
|--------------|--------------------------|-------------|--------------|---------|
| SSHP-XXXXX   | ...                      | ✓ En curso  | frgonzalez   | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✓ En curso  | lpadularrosa | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✗ Error     | —            | ✗ Skip  |

Balance de carga (incidentes no resueltos de SSHP/Groot):
  | Miembro      | Carga inicial | + Asignados | Carga final |
  |--------------|---------------|-------------|-------------|
  | frgonzalez   | 5             | 2           | 7           |
  | maescobar    | 8             | 0           | 8           |
  | jgibelli     | 6             | 1           | 7           |
```

Si no hay tickets sin asignar, mostrar: "✅ No hay tickets sin assignee en la cola."

## 9. Detección post-asignación de tickets derivables

Solo ejecutar este paso si hubo al menos un ticket con estado **✓ OK** en la tabla del paso 8.

**9a. Cargar reglas de derivación:**
Leer `~/.claude/skills/groot-queue/knowledge/triage-rules.md`.

**9b. Evaluar cada ticket ✓ OK:**
Para cada ticket asignado exitosamente, obtener su contenido actualizado con:
```bash
acli jira workitem view <KEY>
```
Aplicar **únicamente las reglas R-DER** del algoritmo de triage (misma lógica que el paso 2b de `derive.md`). Tomar la primera regla que matchee.

**9c. Si ningún ticket matchea una regla R-DER:** no mostrar nada adicional, terminar.

**9d. Si uno o más tickets matchean**, mostrar la tabla y la pregunta de confirmación:

```
🔀 Tickets derivables detectados (N):
| Key          | Summary                  | Regla     | Equipo destino |
|--------------|--------------------------|-----------|----------------|
| SSHP-XXXXX   | ...                      | R-DER-10  | IAM Soporte    |
| SSHP-XXXXX   | ...                      | R-DER-07  | IAM Soporte    |

¿Querés derivar estos N tickets ahora? (sí / no)
```

**9e. Esperar respuesta del usuario:**
- **Sí** (o "s", "yes", "y"): ejecutar el flujo completo de `~/.claude/skills/groot-queue/subcommands/derive.md` con las keys de los tickets derivables, exactamente como si el usuario hubiera corrido `/groot-queue derive <KEY1> <KEY2> ...`. Al registrar en el log de auditoría (paso 4e de `derive.md`), usar `source = "auto-assign"`.
- **No** (o cualquier otra respuesta): terminar mostrando:
  > "Derivación omitida. Podés ejecutarla luego con `/groot-queue derive <KEY1> <KEY2> ...`"

## 10. Detección post-asignación de tickets descartables

Solo ejecutar este paso si hubo al menos un ticket con estado **✓ OK** en la tabla del paso 8 que **no fue incluido como derivable en el paso 9**.

**10a. Cargar reglas de descarte:**
Si `triage-rules.md` ya fue leído en el paso 9a, reutilizar. Si no, leer `~/.claude/skills/groot-queue/knowledge/triage-rules.md`.

**10b. Evaluar cada ticket ✓ OK no derivable:**
Para cada ticket asignado exitosamente que no matcheó una regla R-DER en el paso 9:
- Si el contenido ya fue obtenido en el paso 9b, reutilizarlo; si no, obtenerlo con:
  ```bash
  acli jira workitem view <KEY>
  ```
- Aplicar **únicamente los pasos 14–22 del algoritmo de triage** de `triage-rules.md` (reglas R-DESC), en orden: R-DESC-03, R-DESC-06, R-DESC-07, R-DESC-08, R-DESC-04, R-DESC-09, R-DESC-05, R-DESC-02, R-DESC-01.
- Tomar la primera regla que matchee.
- Las verificaciones previas (R-DESC-03, R-DESC-04, R-DESC-05, R-DESC-06, R-DESC-07, R-DESC-08) que requieren inspección en Groot admin: si no es posible confirmarlas desde el contenido del ticket, marcar como `REVISAR_MANUAL` y no incluirlo en la lista de descartables.

**10c. Si ningún ticket matchea una regla R-DESC:** no mostrar nada adicional, terminar.

**10d. Si uno o más tickets matchean**, mostrar la tabla y la pregunta de confirmación:

```
⛔ Tickets descartables detectados (N):
| Key          | Summary                  | Regla      | Acción           |
|--------------|--------------------------|------------|------------------|
| SSHP-XXXXX   | ...                      | R-DESC-02  | Cerrar Won't Do  |
| SSHP-XXXXX   | ...                      | R-DESC-04  | Cerrar Won't Do  |

¿Querés descartar estos N tickets ahora? (sí / no)
```

**10e. Esperar respuesta del usuario:**
- **Sí** (o "s", "yes", "y"): ejecutar el flujo completo de `~/.claude/skills/groot-queue/subcommands/discard.md` con las keys de los tickets descartables. La confirmación ya fue obtenida en este paso — al llegar al paso 4 de `discard.md`, omitir la pregunta de confirmación y pasar directamente a la ejecución. Al registrar en el log de auditoría (paso 5e de `discard.md`), usar `source = "auto-assign"`.
- **No** (o cualquier otra respuesta): terminar mostrando:
  > "Descarte omitido. Podés ejecutarlo luego con `/groot-queue discard <KEY1> <KEY2> ...`"
