---
description: Asigna en Jira todos los tickets sin responsable usando round-robin sobre el TEAM configurado.
---

# /groot-queue:assign-unassigned

Asignar todos los tickets sin responsable usando round-robin. **Este es el único command que escribe en Jira** (transiciona estado + asigna responsable).

## Pre-condición

Leer el `TEAM` desde `~/.claude/skills/groot-queue/SKILL.md`. Si está vacío, abortar con mensaje:
> "Configurá la sección TEAM del SKILL.md antes de usar este comando."

## Algoritmo

1. Leer el estado desde `~/.claude/skills/groot-queue/knowledge/roundrobin-state.json`. Si no existe, inicializarlo con `next_assignee_index: 0` y `history: []`.
   **IMPORTANTE**: el estado se actualiza con el Write tool después de CADA asignación exitosa (paso 6e). No esperar al final.
2. Si `next_assignee_index >= len(TEAM)`, resetear a 0 (protección ante cambios en la lista).
3. Obtener todos los tickets abiertos:
   ```bash
   acli jira workitem search --jql "project = SSHP AND Squad = Groot AND type = Incident AND resolution = Unresolved ORDER BY created DESC"
   ```
4. Filtrar solo los que **no tienen assignee** (campo `assignee` vacío o null).
5. Ordenar por urgencia descendente (score 5 primero — ver `classification.md`).
6. Para cada ticket sin asignar:

   a. `assignee = TEAM[next_assignee_index]`

   b. **Transicionar a "In Progress" PRIMERO** — en una llamada Bash **separada**:
      ```bash
      acli jira workitem transition --key <KEY> --status "In Progress" --yes
      ```
      - Si falla: reportar el error, **NO avanzar el índice**, continuar con el siguiente ticket.
      - ⚠️ **CRÍTICO**: la transición auto-asigna al usuario autenticado de ACLI, pisando cualquier asignación previa. Por eso la asignación debe ir en una llamada Bash **separada e independiente** — nunca encadenar ambos comandos con `&&` en un solo Bash call, ya que la transición puede completarse de forma asíncrona en Jira y terminar pisando el assign.

   c. Asignar responsable en una **nueva llamada Bash separada**, después de que la transición haya retornado:
      ```bash
      acli jira workitem assign --key <KEY> --assignee <email> --yes
      ```
      - El `<email>` se lee directamente del campo `email` del miembro en la sección TEAM del SKILL.md. No construir el email desde el username.
      - Si falla: reportar el error, **NO avanzar el índice** (la transición ya ocurrió, pero se reporta).

   d. Verificar asignación en una **nueva llamada Bash separada**:
      ```bash
      acli jira workitem view <KEY>
      ```
      → leer el campo `Assignee:`
      - Si `Assignee` != `<email>`: reintentar el assign una vez más (`acli jira workitem assign --key <KEY> --assignee <email> --yes`).
        - Si sigue sin coincidir: reportar ⚠️ con el ticket y el assignee incorrecto, **NO avanzar el índice**.
      - Si `Assignee` == `<email>`: continuar al paso e.

   e. Si transición + asignación + verificación exitosas:
      - Calcular nuevo índice: `next_assignee_index = (next_assignee_index + 1) % len(TEAM)`.
      - Calcular `last_updated`: timestamp actual en ISO8601 (ej: `2026-05-11T14:30:00Z`).
      - Agregar a `history`: `{ "key": "<KEY>", "assignee": "<username>", "ts": "<last_updated>" }`.
      - Si `history` supera 100 entradas, eliminar las más antiguas hasta dejar 100.
      - **ACCIÓN BLOQUEANTE — usar Write tool INMEDIATAMENTE con este contenido exacto:**
        ```json
        {
          "last_updated": "<ISO8601 del momento actual>",
          "next_assignee_index": <nuevo valor calculado>,
          "history": [<history acumulado, máximo 100 entradas>]
        }
        ```
        Path destino: `~/.claude/skills/groot-queue/knowledge/roundrobin-state.json`.
      - Solo continuar al siguiente ticket **después** de que el Write tool retorne sin error.

   f. Si falla el Write: reportar el error, abortar el loop, mostrar cuántos tickets se asignaron exitosamente antes del fallo.

7. **El estado ya fue persistido incrementalmente en el paso 6e. No hay acción adicional aquí.**
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

## History cap

Mantener máximo 100 entradas en `history`; eliminar las más antiguas si se supera el límite.
