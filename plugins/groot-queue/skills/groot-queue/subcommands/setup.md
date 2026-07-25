---
description: Verifica dependencias, integraciones, permisos y el preflight completo de Grid Sharing para usar groot-queue.
---

# Subcomando: setup

**Propósito**: Verificar el entorno requerido por `groot-queue`, diagnosticar dependencias y mostrar remediaciones seguras sin asumir que una integración está disponible.

> **Re-ejecutable**: este subcomando es idempotente. Correrlo de nuevo no rompe nada; revalida lo configurado y señala lo que falta.

## Ayuda sin tools

Antes de cualquier tool o lectura adicional, inspeccionar los argumentos. Si contienen el token exacto `--help` o `-h`, explicar brevemente qué verifica `setup`, que Grid Sharing es obligatorio para completar el setup y que no se realizan instalaciones ni cambios sin autorización explícita. Detenerse después de responder la ayuda.

## 1. ACLI (Atlassian CLI)

- Verificar: `acli --version`.
- Si no está instalado, mostrar instrucciones para `brew install acli` o https://acli.atlassian.com; no instalarlo automáticamente.
- Si está instalado, verificar autenticación con `acli jira serverinfo`.
  - Si falla, mostrar `acli jira auth login --web` y pedir seleccionar `https://mercadolibre.atlassian.net`.

## 2. Atlassian MCP

El subcomando `derive` usa el MCP de Atlassian para ejecutar la transición "Derivar a otro equipo". Leer `$SKILL_DIR/knowledge/config/atlassian-mcp.md` como referencia canónica de instalación y errores.

- Verificar si el contexto expone un MCP de Atlassian compatible.
- Si el provider no expone esas tools, informar que la derivación automática debe completarse manualmente en Jira.
- Si solo permite comentarios públicos y no notas internas de Jira Service Management, no automatizar la derivación.
- Si no está disponible, mostrar las opciones de configuración de la referencia canónica; no instalar ni habilitar nada sin autorización explícita.
- Si está disponible, verificar autenticación y resolver el `cloudId` con las tools del provider actual. No hardcodearlo.

## 3. Slack MCP

El subcomando `alerts` usa Slack MCP para enviar DMs de SLA. Los nombres de las tools varían según provider y configuración.

- Buscar capacidades compatibles para localizar usuarios y enviar mensajes, sin depender de un nombre exacto de tool.
- Si no existen, informar que `alerts` solo puede ejecutarse con `--dry-run` y mostrar la remediación correspondiente al provider.
- Si existen pero no están autenticadas, indicar el flujo de login disponible.
- Si están autenticadas, marcar el check como listo.

## 4. Permisos ACLI en settings

- Verificar que `.claude/` existe en el directorio actual.
- Verificar que `.claude/settings.local.json` contiene `"Bash(acli jira *)"` en `permissions.allow`.
- Si falta, explicar el cambio mínimo y pedir autorización antes de crear o modificar el archivo.

## 5. Verificación del TEAM

- Leer la sección TEAM de `$SKILL_DIR/SKILL.md`.
- Si está vacía, advertir que `assign-unassigned` no funcionará hasta configurarla.

## 6. Grid Sharing — diagnóstico completo obligatorio

Este diagnóstico es propio de `setup` y se ejecuta independientemente de cualquier gate previo. No reutilizar un estado en memoria ni `GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE`: ejecutar un preflight fresco para que la tabla refleje el entorno actual.

1. Leer y aplicar `$SKILL_DIR/knowledge/config/grid-sharing-preflight.md`.
2. Identificar el provider activo como `claude`, `codex` o `copilot`. Usar `GROOT_QUEUE_ACTIVE_PROVIDER` solo si contiene uno de esos valores; en otro caso usar el provider que ejecuta la skill. Usar `auto` únicamente cuando no sea posible distinguirlo.
3. Ejecutar `$SKILL_DIR/scripts/check-groot-queue-readiness.sh --provider <provider>` sin `--reuse-result`.
4. Capturar tanto el exit code como el único objeto JSON de stdout. No imprimir el objeto completo, bodies, identidad, tokens ni paths de instalación.
5. Usar exclusivamente `checks`, `failures`, `provider`, `ok` y `exit_code` para completar las filas de Grid.

`ok: true` junto con exit code `0` es un requisito crítico para declarar el setup completo. La presencia textual de la skill o del plugin no reemplaza ninguna capa del checker.

Si Grid falla, no instalar, habilitar ni actualizar el plugin. Mostrar cada failure code seguro y la remediación en español asociada a su exit code en el contrato central. Cualquier instalación, habilitación o actualización requiere autorización explícita del usuario antes de ejecutarse.

## Output esperado

Renderizar una tabla con el resultado real de cada check. No conservar placeholders ni inventar valores no verificables.

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Setup — Groot Queue
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
| Check                              | Estado     | Detalle seguro |
|------------------------------------|------------|----------------|
| ACLI instalado                     | <resultado> | <versión o estado> |
| ACLI autenticado                   | <resultado> | <sitio o estado> |
| Atlassian MCP + cloudId            | <resultado> | <validado o no verificable> |
| Slack MCP                          | <resultado> | <autenticado, limitado o ausente> |
| Permiso Bash(acli jira *)          | <resultado> | <archivo o estado> |
| TEAM configurado                   | <resultado> | <cantidad o vacío> |
| Grid provider inventory + plugin   | <resultado> | <provider + failure code si aplica> |
| Grid required skill                | <resultado> | <check real> |
| Grid network + ping                | <resultado> | <check real> |
| Grid plugin version                | <resultado> | <check real> |
| Grid identity + VPN                | <resultado> | <check real> |
| Grid general read                  | <resultado> | <check real> |
| Grid required document             | <resultado> | <check real> |
```

Para las filas de Grid, mapear respectivamente los checks `provider_inventory`, `required_skill`, `ping`, `skill_version`, `identity`, `general_read` y `required_document`. Si una capa no corrió, mostrarla como no ejecutada con su failure code seguro; no presentarla como exitosa.

- `✅` = check verificado.
- `❌` = check crítico fallido.
- `⚠️` = integración opcional degradada o no verificable.

### Cierre

- Mostrar `✅ Setup completo. Podés usar /groot-queue list para empezar.` únicamente cuando los checks críticos locales estén listos y Grid termine con exit code `0` y `ok: true`.
- En cualquier otro caso, mostrar `⚠️ Setup incompleto`, listar cada limitación comprobada y su remediación en español, y no afirmar que los comandos operativos están disponibles mientras Grid no haya pasado.
