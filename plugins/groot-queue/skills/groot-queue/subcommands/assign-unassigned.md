---
description: Asigna en Jira todos los tickets sin responsable repartiéndolos al azar de forma equitativa sobre el TEAM configurado.
---

# /groot-queue:assign-unassigned

Asignar todos los tickets sin responsable repartiéndolos al azar entre el TEAM, de forma **equitativa y sin estado local**. **Este command escribe en Jira** (transiciona estado + asigna responsable). Ver también `derive`, que escribe comentario + transición de estado.

## Por qué aleatorio y sin estado persistente

La asignación **no persiste estado entre corridas**. Antes existía un `next_assignee_index` guardado localmente, pero como cada miembro del team corría el comando con su propio índice desfasado, la rotación terminaba siendo desigual entre todos. Ahora cada corrida baraja el TEAM al azar y reparte sin repetir, así que la equidad no depende de ningún archivo compartido ni del orden en que cada persona ejecute el comando.

Durante la corrida se usa **un archivo scratch efímero** (creado con `mktemp`, fuera del repo) que guarda la cola barajada y la posición actual. Es un detalle de implementación para que el loop sea robusto a lo largo de muchas llamadas Bash; **se crea fresco en cada corrida y se elimina al terminar o abortar**, así que no es cache compartida ni sobrevive entre ejecuciones.

## Pre-condición

Leer el `TEAM` desde `~/.claude/skills/groot-queue/SKILL.md`. Si está vacío, abortar con mensaje:
> "Configurá la sección TEAM del SKILL.md antes de usar este comando."

## Algoritmo

1. Obtener todos los tickets abiertos:
   ```bash
   acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type = Incident AND resolution = Unresolved ORDER BY created DESC"
   ```
2. Filtrar solo los que **no tienen assignee** (campo `assignee` vacío o null).
3. Ordenar por urgencia descendente (score 5 primero — ver `classification.md`).
4. **Crear el archivo scratch efímero y barajar el TEAM al azar** dentro de él. Generar un orden aleatorio real con entropía del sistema (no inventar el orden a mano). En una sola llamada Bash, crear el temp file con `mktemp` y escribir los emails del TEAM barajados, uno por línea, con este one-liner portable (macOS + Linux):
   ```bash
   QUEUE=$(mktemp -t groot-assign-queue.XXXXXX 2>/dev/null || mktemp)
   awk 'BEGIN{srand()} {print rand()"\t"$0}' <<'EOF' | sort -n | cut -f2- > "$QUEUE"
   <email del miembro 1>
   <email del miembro 2>
   ...
   <email del miembro N>
   EOF
   echo "QUEUE=$QUEUE"   # recordar este path para el resto de la corrida
   ```
   El archivo `$QUEUE` es la **cola barajada** de esta corrida. La primera línea es siempre el próximo a asignar. Guardar el path para reutilizarlo en los pasos siguientes.
5. Para cada ticket sin asignar, tomar el **primer email** de `$QUEUE` (`head -n1 "$QUEUE"`) — reparto **sin repetición**. Cuando `$QUEUE` quede vacío (más tickets que miembros), **volver a barajar** el TEAM con el mismo comando del paso 4 sobre el mismo `$QUEUE` y seguir. Así nadie recibe un segundo ticket hasta que todos hayan recibido uno en este batch.
6. Para cada ticket sin asignar:

   a. `assignee` = primer email de `$QUEUE`:
      ```bash
      head -n1 "$QUEUE"
      ```
      Si `$QUEUE` está vacío, rebarajar primero (paso 5) y volver a leer.

   b. **Transicionar a "In Progress" PRIMERO** — en una llamada Bash **separada**:
      ```bash
      acli jira workitem transition --key <KEY> --status "In Progress" --yes
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
        Así ese miembro no vuelve al pool hasta el próximo rebarajado.
      - Continuar al siguiente ticket.

7. **Limpieza obligatoria.** Al terminar el loop —tanto si completó como si abortó por un error— eliminar el archivo scratch:
   ```bash
   rm -f "$QUEUE"
   ```
   No persiste estado entre corridas: la próxima ejecución (de quien sea) creará un `$QUEUE` nuevo y barajará desde cero.

8. Mostrar tabla de resultados:

```
Asignaciones realizadas (N tickets):
| Key          | Summary                  | Transición  | Asignado a   | Estado  |
|--------------|--------------------------|-------------|--------------|---------|
| SSHP-XXXXX   | ...                      | ✓ En curso  | frgonzalez   | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✓ En curso  | lpadularrosa | ✓ OK    |
| SSHP-XXXXX   | ...                      | ✗ Error     | —            | ✗ Skip  |

Reparto de esta corrida:
  | Miembro      | Tickets |
  |--------------|---------|
  | frgonzalez   | 1       |
  | lpadularrosa | 1       |
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
