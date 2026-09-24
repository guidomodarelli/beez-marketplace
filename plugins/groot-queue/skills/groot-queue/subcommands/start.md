# Subcomando: start

**Propósito**: Mostrar dashboard operativo con tabla de capacidades, totales exactos de cola, acciones recomendadas y catálogo completo de comandos con descripción.

## Higiene de salida

Usar conocimiento interno silenciosamente en toda respuesta, incluidas preguntas documentales y ayuda. No citar ni nombrar archivos, paths, secciones, contratos, scripts, checker o `$SKILL_DIR`. Antes de responder, eliminar `.md`, `§`, paths internos y análisis meta.

Cuando usuario pida output esperado para escenario, renderizar únicamente output final; no anteponer razonamiento ni agregar explicación posterior.

## 1. Argumentos

- Sin argumentos: dashboard + totales + catálogo completo.
- `--help` o `-h`: entrypoint responde ayuda sin tools.
- Cualquier otro argumento, incluido `--all`: responder exactamente `Uso: /groot-queue start` y nada más; detenerse sin tools ni explicación.

## 2. Readiness y auto-recuperación

Consumir estado combinado validado por dispatcher durante misma invocación. No repetir checker, discovery Fury ni probes Grid.

Si readiness falla, entrypoint ejecuta `setup` automáticamente. Si `setup` deja entorno listo dentro de misma invocación, reutilizar estado y continuar. Si requiere OAuth, VPN, `/reload-plugins`, restart, acceso o decisión ambigua, mostrar output de `setup` y detener `start`.

ACLI instalado y autenticado también es precondición. Verificar `acli --version` y `acli jira auth status` de forma read-only. Si falla, ejecutar `setup` automáticamente.

## 3. Datos dinámicos

Después de readiness completo, obtener en paralelo versión, capacidades opcionales, TEAM y tres conteos Jira.

### Versión y provider

Leer versión desde manifest del provider activo. Si no existe versión verificable, mostrar `unknown`; no fallar. Mostrar provider resuelto (`Claude Code` o `Codex`) sin inferir por archivos de otro provider.

### Capacidades opcionales con probes reales

No usar `mcp list | grep` como prueba de conexión.

- **Atlassian MCP**:
  - tool compatible ausente → `— No instalado`;
  - probe read-only de recursos exitoso y workspace corporativo presente → `✅ Conectado`;
  - error auth → `❌ No autenticado`;
  - otro fallo → `⚠️ No verificable`.
- **Slack MCP**:
  - tool compatible ausente → `— No instalado`;
  - probe read-only de perfil actual exitoso → `✅ Conectado`;
  - error auth → `❌ No autenticado`;
  - otro fallo → `⚠️ No verificable`.

No mostrar payloads, identidad, email, account IDs, cloudId ni perfil.

### TEAM

Contar entradas verificadas. Mostrar `✅ Configurado` con `N integrantes` o `⚠️ Vacío` con `Sin integrantes`. No listar identidades.

### Totales exactos de cola

Ejecutar tres búsquedas ACLI en paralelo usando `--count`; no usar `--limit` ni derivar total desde primera página:

```bash
# Abiertos
OPEN_JQL=$(cat <<'JQL'
project = SSHP AND <SQUAD_FIELD_JQL> = "Groot" AND type IN (Incident, "Service Request") AND resolution = Unresolved
JQL
)
acli jira workitem search --count --jql "$OPEN_JQL"

# Sin asignar
UNASSIGNED_JQL=$(cat <<'JQL'
project = SSHP AND <SQUAD_FIELD_JQL> = "Groot" AND type IN (Incident, "Service Request") AND resolution = Unresolved AND assignee IS EMPTY
JQL
)
acli jira workitem search --count --jql "$UNASSIGNED_JQL"

# Alta prioridad con más de 24h
HIGH_PRIORITY_JQL=$(cat <<'JQL'
project = SSHP AND <SQUAD_FIELD_JQL> = "Groot" AND type IN (Incident, "Service Request") AND resolution = Unresolved AND priority IN (Highest, High) AND created <= -24h
JQL
)
acli jira workitem search --count --jql "$HIGH_PRIORITY_JQL"
```

> Expandir `<SQUAD_FIELD_JQL>` al field id real antes de ejecutar; la expansión está centralizada en `$SKILL_DIR/knowledge/config/jira-field-options.md` § `customfield_13781`.

Cada consulta es read-only, independiente, con timeout corto y sin retry. Aceptar resultado solo cuando sea:

- entero no negativo en texto plano;
- formato ACLI exacto `✓ Number of work items in the search: <N>`;
- número JSON no negativo;
- objeto JSON con campo inequívoco `count` o `total` entero no negativo.

Cualquier otro formato → `No disponible`. Nunca inventar cero.

Tabla de totales se muestra siempre, incluso con fallos parciales. Etiqueta tercera métrica debe ser **`Alta prioridad +24h`**, nunca “riesgo SLA”: es heurística de prioridad/edad, no SLA autoritativo.

## 4. Output

No usar logo ASCII, cajas de ancho fijo ni saludo basado en Git.

```text
🌱 Groot Queue · v<VERSION>
Estado: ✅ LISTO · <PROVIDER>
```

### Estado

| Área | Estado | Detalle |
|---|---|---|
| Entorno | ✅ Operativo | <PROVIDER> |
| Jira | <estado Atlassian> | ACLI ✅ |
| Slack | <estado Slack> | <OAuth activo, no autenticado, no instalado o no verificable> |
| Knowledge | ✅ Operativo | Grid Sharing + FuryDocs |
| TEAM | <✅ Configurado o ⚠️ Vacío> | <N integrantes o Sin integrantes> |

No combinar varias capacidades dentro de columna Estado. Usar Detalle para provider, ACLI, OAuth, componentes Knowledge y cantidad TEAM.

Si auto-setup completó reparaciones sin pasos humanos pendientes, agregar después de tabla:

```text
Reparaciones: ✅ <assets instalados/actualizados>
```

No repetir output completo de `setup`.

### Totales de cola

Mostrar siempre:

| Métrica | Total |
|---|---:|
| 📬 Abiertos | <N o No disponible> |
| 👤 Sin asignar | <N o No disponible> |
| 🔥 Alta prioridad +24h | <N o No disponible> |

No agregar nota de muestra parcial: valores disponibles provienen de `--count` y son totales exactos.

## 5. Acciones recomendadas

Construir máximo tres acciones, en orden:

1. Si `Alta prioridad +24h > 0`: `🚨 /groot-queue alerts --dry-run`.
2. Si `Sin asignar > 0`: `👤 /groot-queue assign-unassigned`.
3. Si `Abiertos > 0`: `📊 /groot-queue stats`.
4. Si tres totales son `0`: mostrar `✅ Cola sin acciones urgentes.` sin lista.
5. Si algún total es `No disponible` y no existen acciones derivables: recomendar `📋 /groot-queue list` y `📊 /groot-queue stats`.

```text
Acciones recomendadas

1. 🚨 `/groot-queue alerts --dry-run`
2. 👤 `/groot-queue assign-unassigned`
3. 📊 `/groot-queue stats`
```

No ejecutar acciones automáticamente. `alerts` se recomienda con `--dry-run`; `assign-unassigned` conserva confirmaciones propias.

## 6. Catálogo completo siempre visible

Después de acciones, ejecutar `$SKILL_DIR/scripts/render-catalog.sh` mediante Bash. Tratar stdout como artefacto opaco: copiar byte por byte, sin abreviar, reindentar ni recrear.

Si renderer falla, informar error después de dashboard; no sintetizar catálogo manualmente.

Antes de responder, verificar que catálogo contiene entrada `setup` y línea final `analyze-history`. Si falta alguna, usar stdout original sin transformaciones.

En respuestas documentales, describir output visible sin mencionar implementación interna.

## Reglas

- Mantener latencia baja: datos independientes en paralelo.
- No repetir readiness validado.
- No invocar tools documentales Fury.
- No ejecutar `stats`, `alerts`, `assign-unassigned` ni otro subcomando automáticamente.
- No llamar heurística “riesgo SLA”.
- No mostrar PII ni payloads MCP.
- Mostrar siempre tablas Estado y Totales de cola.
- Catálogo completo siempre aparece en `start`.
