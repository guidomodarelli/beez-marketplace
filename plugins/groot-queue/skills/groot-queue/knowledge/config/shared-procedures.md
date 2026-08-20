# Procedimientos compartidos — derive / discard

Procedimientos reutilizados por `derive.md` y `discard.md`. Cada subcomando referencia la sección que necesita.

---

## Escribir labels en Jira

Usar `editJiraIssue` (MCP Atlassian) para agregar labels de trazabilidad al ticket. **Merge de labels** (no reemplazar las existentes):
- Leer las labels actuales del ticket (ya disponibles del fetch inicial; no requiere llamada extra).
- Agregar las labels correspondientes a la lista existente (ver cada subcomando para las labels específicas).
- Actualizar el campo `labels` con la lista combinada.
- Si `editJiraIssue` retorna error de conflicto (el ticket fue modificado entre el fetch y ahora), releer las labels actuales y reintentar una vez antes de reportar el error.

> ⚠️ Las labels son kebab-case, todo en minúsculas, sin espacios.

- Si falla: registrar `✗ Labels` en el resultado. **No abortar** — las acciones principales en Jira ya fueron completadas. Continuar al siguiente ticket.

---

## Evaluar novedad y registrar en knowledge base

Una acción exitosa (derive o discard) **no** crea automáticamente un archivo por ticket. Labels y audit log ya registran aplicación de regla conocida.

### Cuándo crear archivo

Crear archivo en KB solo si las acciones principales en Jira terminaron exitosamente **y** el ticket aporta conocimiento verificable, reusable y ausente en `triage-rules.md` y `solutions/`.

Considerar conocimiento nuevo únicamente cuando agrega al menos uno de estos elementos:
1. Señal real nueva que mejora identificación futura de regla.
2. Excepción o condición previa no documentada que cambia destino o veredicto.
3. Gotcha operativo verificable o evidencia concreta reusable para resolver/derivar/descartar casos futuros.

### Cuándo NO crear archivo

- Ticket se limita a ejemplificar regla existente.
- Repite señales documentadas.
- Solo aporta IDs/datos propios del caso.

### Procedimiento

- Antes de escribir, buscar duplicados semánticos en la regla aplicada y la carpeta de categoría correspondiente. Si hay cobertura suficiente, reportar `KB — (sin conocimiento nuevo)`.
- Si novedad es dudosa, no escribir; reportar `KB — (revisión futura)`.
- Si las acciones principales en Jira fallaron, no crear registro `effectiveness: confirmed`; reportar `KB —`.
- Cuando señal nueva funcione como matcher, documentar variantes ES + PT + EN verificadas contra wording real del ticket, según regla trilingüe del repositorio.
- Antes de escribir, asegurar que el directorio exista: `mkdir -p "$SKILL_DIR/knowledge/solutions/<categoria-slug>"`.

### Path y formato

Cada subcomando define su propio path y frontmatter (ver `derive.md` § 4e y `discard.md` § 5e).

- Si falla el Write: reportar (las acciones en Jira ya están hechas; el registro es secundario, no bloquea).

---

## Reconciliar watcher del ejecutor

Aplicar después de una derivación o descarte cuya acción principal dejó un assignee final verificable. El objetivo es conservar todos los watchers salvo el ejecutor, excepto si ese ejecutor es el assignee final.

1. Obtener `actorAccountId` mediante la capacidad equivalente a `atlassianUserInfo` del MCP Atlassian. Conservarlo sólo en memoria de la invocación; no imprimirlo ni persistirlo.
2. Obtener el ticket actualizado y resolver `assignee.accountId` final. Si no se puede resolver actor o assignee, no revertir acción principal: registrar `partial-error` y `watcher_cleanup = identity_unverified`.
3. Listar watchers con `acli jira workitem list-watchers --key <KEY> --json` y conservar únicamente el conteo y presencia del actor para auditoría.
4. Si `actorAccountId == assignee.accountId`, conservar watcher del ejecutor y registrar `watcher_cleanup = actor_is_assignee`.
5. Si actor no está en watchers, registrar `watcher_cleanup = actor_absent`; no hacer mutación.
6. Si actor está watcher y no es assignee final, ejecutar exclusivamente:
   ```bash
   acli jira workitem watcher remove --key <KEY> --user <actorAccountId>
   ```
7. Listar watchers nuevamente y verificar que actor no esté. Nunca agregar, remover ni reemplazar otro watcher. Altas concurrentes se preservan porque la única mutación usa el ID exacto del actor.
8. Si listar, remover o verificar falla, no revertir la acción principal ni tocar otros watchers. Registrar `partial-error` y warning seguro.

Estados permitidos: `removed`, `actor_is_assignee`, `actor_absent`, `identity_unverified`, `list_failed`, `remove_failed`, `verification_failed`, `not_applicable`.

## Registrar en el log de auditoría

Append-only — una línea JSON por ticket sobre el que se intentó una acción.

- **Formato y schema del log**: ver `$SKILL_DIR/knowledge/README.md` § Auditar derivaciones/descartes automáticos.
- **Appendear** (nunca sobrescribir) al log del **año en curso**: `$SKILL_DIR/knowledge/audit-log-<YYYY>.jsonl`.
- El año se resuelve con `$(date -u +%Y)`.
- No registrar tickets que no matchearon ninguna regla (no hubo acción que auditar).
- Si el append falla: reportar; no bloquea (las acciones en Jira ya están hechas).

### Determinar `source`

| Contexto | Valor |
|----------|-------|
| Invocado desde `assign-unassigned` | `"auto-assign"` |
| Invocado desde `assign-unassigned` con alta confianza ⚡ | `"auto-assign-autoconfianza"` |
| Invocado desde `assign-unassigned` con `GROOT_QUEUE_AUTORUN=true` | `"auto-run"` |
| Invocado directamente por el usuario | `"manual"` |

### Determinar `result`

| Resultado | Valor |
|-----------|-------|
| Acciones principales y watcher cleanup exitosos | `"ok"` |
| Acción principal exitosa pero watcher cleanup parcial, o nota/transición parcial | `"partial-error"` |
| No se completó ninguna acción en Jira | `"failed"` |
| Regla requiere acción manual | `"manual"` |
