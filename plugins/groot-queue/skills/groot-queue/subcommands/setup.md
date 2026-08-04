---
description: Verifica ACLI, integraciones y el readiness completo de Grid Sharing y FuryDocs para usar groot-queue.
---

# Subcomando: setup

**Propósito**: Verificar el entorno requerido por `groot-queue`, diagnosticar dependencias y resolver faltantes con instrucciones autocontenidas y asistencia automatizada bajo aprobación explícita.

> **Re-ejecutable**: este subcomando es idempotente. Correrlo de nuevo no rompe nada; revalida lo configurado y señala lo que falta.

## Ayuda sin tools

Antes de cualquier tool o lectura adicional, inspeccionar los argumentos. Si contienen el token exacto `--help` o `-h`, explicar brevemente qué verifica `setup`, que Grid Sharing y FuryDocs son obligatorios, y que ante una falla muestra directamente comandos copiables, ofrece ejecutar la parte automatizable con autorización explícita y separa los pasos humanos como OAuth, VPN, `/reload-plugins` o restart. Incluir `/groot-queue:setup` para Claude Code y `/groot-queue setup` para Codex como invocaciones de diagnóstico. Incluir frase explícita: `Esta ayuda no ejecuta checker, discovery MCP, Bash, Jira, Slack ni diagnósticos; tampoco modifica el entorno.` No mencionar archivos ni paths internos. Detenerse después de responder ayuda.

## 1. ACLI (Atlassian CLI)

- Verificar `acli --version`.
- Si ACLI no está disponible, marcar el check como fallido, leer la sección ACLI de `$SKILL_DIR/knowledge/config/installation.md` y mostrar inline los comandos de instalación, login web y status. Ofrecer ejecutar la instalación después de aprobación; login queda como paso humano.
- Si está disponible, verificar autenticación con `acli jira auth status`.
- Si la autenticación falla o corresponde a otro sitio, marcar el check como fallido y mostrar inline `acli jira auth login --web` seguido de `acli jira auth status`; no ejecutar login automáticamente.

## 2. Atlassian MCP

El subcomando `derive` usa el MCP de Atlassian para ejecutar la transición "Derivar a otro equipo". Leer `$SKILL_DIR/knowledge/config/atlassian-mcp.md` como referencia canónica de instalación y errores.

- Verificar si el contexto expone un MCP de Atlassian compatible.
- Si el provider no expone esas tools, informar que la derivación automática debe completarse manualmente en Jira.
- Si solo permite comentarios públicos y no notas internas de Jira Service Management, no automatizar la derivación.
- Si no está disponible o autenticación falla, marcar check según contrato, leer sección Atlassian MCP de `$SKILL_DIR/knowledge/config/installation.md` y mostrar inline opción oficial recomendada, comando copiable, OAuth desde `/mcp` y validación. Ofrecer instalar plugin oficial después de aprobación; no instalar, habilitar ni autenticar antes de recibirla.
- Si está disponible, verificar autenticación y resolver el `cloudId` con las tools del provider actual. No hardcodearlo.

## 3. Slack MCP

El subcomando `alerts` usa Slack MCP para enviar DMs de SLA. Los nombres de las tools varían según provider y configuración.

- Buscar capacidades compatibles para localizar usuarios y enviar mensajes, sin depender de un nombre exacto de tool.
- Si no existen, informar que `alerts` solo puede ejecutarse con `--dry-run`, leer sección Slack MCP de `$SKILL_DIR/knowledge/config/installation.md` y mostrar inline instalación oficial, OAuth y validación dry-run. Ofrecer instalar plugin después de aprobación.
- Si existen pero no están autenticadas, mantener modo degradado y mostrar directamente paso OAuth desde `/mcp`; no iniciar OAuth automáticamente.
- Si están autenticadas, marcar el check como listo.

## 4. Autorización interactiva de ACLI

No inspeccionar, crear ni exigir archivos de settings del provider. Los permisos persistentes son opcionales y no forman parte del readiness. Si una operación futura usa ACLI, el provider puede solicitar autorización en ese momento según su política activa.

## 5. Verificación del TEAM

- Leer la sección TEAM de `$SKILL_DIR/SKILL.md`.
- Si está vacía, advertir que `assign-unassigned` no funcionará hasta configurarla.

## 6. Fase shell — diagnóstico fresco obligatorio

Este diagnóstico es propio de `setup` y se ejecuta independientemente de cualquier gate previo. No reutilizar un estado en memoria ni `GROOT_QUEUE_READINESS_RESULT_FILE`.

1. Leer y aplicar `$SKILL_DIR/knowledge/config/groot-queue-readiness.md` y usar `$SKILL_DIR/knowledge/config/groot-queue-readiness.json` como configuración máquina-legible.
2. Identificar el provider activo como `claude` o `codex`. Usar `GROOT_QUEUE_ACTIVE_PROVIDER` solo si contiene uno de esos valores; en otro caso usar el provider que ejecuta la skill. Usar `auto` únicamente cuando no sea posible distinguirlo.
3. Ejecutar `$SKILL_DIR/scripts/check-groot-queue-readiness.sh --provider <provider>` sin `--reuse-result`.
4. Capturar tanto el exit code como el único objeto JSON de stdout. No imprimir el objeto completo, bodies, identidad, tokens ni paths de instalación.
5. Exigir `schema_version: 2` y `scope: "shell"`. Usar exclusivamente `checks`, `failures`, `provider`, `ok` y `exit_code` para completar las filas shell.

La fase shell solo está lista con exit code `0`, `schema_version: 2`, `scope: "shell"`, `ok: true` y `exit_code: 0`. La presencia textual de una skill, plugin o declaración MCP no reemplaza ninguna capa del checker.

Si fase shell falla, no instalar, habilitar, configurar ni actualizar nada todavía. Mostrar cada failure code seguro y leer `$SKILL_DIR/knowledge/config/installation.md#recuperacion-conversacional-de-ai-assets` junto con secciones del recurso afectado. Agrupar failures por causa y reproducir directamente en chat comandos, pasos humanos y validación; nunca remitir persona a archivo, path o anchor. Ofrecer ejecutar acciones automatizables enumeradas y esperar aprobación explícita antes de cualquier mutación.

## 7. Fase runtime MCP — diagnóstico independiente

Ejecutar este diagnóstico después del intento shell incluso cuando la fase shell haya fallado. No reutilizar un resultado runtime anterior.

1. Detectar únicamente tools de discovery inequívocamente pertenecientes al server MCP `fury` del provider actual. En Claude Code, preferir `mcp__plugin_fury-services_fury__list_components` y `mcp__plugin_fury-services_fury__list_tools`; aceptar solo equivalentes exactos del mismo server.
2. Si ambas tools están disponibles, invocar **solo** `list_components` sin argumentos. No mostrar el payload completo.
3. Si la respuesta es válida, exigir un componente cuyo `name` sea exactamente `furydocs`.
4. Si el componente existe, invocar **solo** `list_tools` con `component="furydocs"`. Exigir los nombres exactos `get_doc_structure` y `get_doc_file`; permitir tools adicionales.
5. No invocar `get_doc_structure`, `get_doc_file` ni ninguna otra tool documental.
6. Si tools de discovery no están disponibles o una capa falla, registrar check y failure code exactos definidos en `$SKILL_DIR/knowledge/config/groot-queue-readiness.md`. Leer protocolo conversacional y sección Fury Services/FuryDocs de `$SKILL_DIR/knowledge/config/installation.md`; mostrar inline verificación, `/reload-plugins`, restart y revalidación. Si inventario indica plugin ausente o incompleto, incluir comando de instalación/update y ofrecer ejecutarlo con aprobación. No crear conexión MCP `fury` alternativa ni reconstruir transporte.

Esta fase es independiente y no serializable: no escribir su estado en archivos ni variables de entorno y no inferirla desde el JSON shell.

## Output esperado

Renderizar una tabla con el resultado real de cada check. No conservar placeholders ni inventar valores no verificables.

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Setup — Groot Queue
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
| Check                              | Estado      | Detalle seguro |
|------------------------------------|-------------|----------------|
| ACLI instalado                     | <resultado> | <versión o estado> |
| ACLI autenticado                   | <resultado> | <sitio o estado> |
| Atlassian MCP + cloudId            | <resultado> | <validado o no verificable> |
| Slack MCP                          | <resultado> | <autenticado, limitado o ausente> |
| TEAM configurado                   | <resultado> | <cantidad o vacío> |
| Provider inventory                 | <resultado> | <provider + failure code si aplica> |
| Grid Sharing plugin                | <resultado> | <check real> |
| Grid Sharing skill                 | <resultado> | <check real> |
| Fury plugin                        | <resultado> | <check real> |
| Fury skill                         | <resultado> | <check real> |
| Fury manifest                      | <resultado> | <check real> |
| Fury MCP declaration              | <resultado> | <check real> |
| Fury MCP CLI                       | <resultado> | <check real> |
| Grid network + ping                | <resultado> | <check real> |
| Grid plugin version                | <resultado> | <check real> |
| Grid identity + VPN                | <resultado> | <check real> |
| Grid general read                  | <resultado> | <check real> |
| Grid required document             | <resultado> | <check real> |
| Fury runtime discovery             | <resultado> | <check real> |
| FuryDocs component                 | <resultado> | <check real> |
| FuryDocs required tools            | <resultado> | <check real> |
```

Mapear las filas shell respectivamente a `provider_inventory`, `grid_plugin`, `grid_required_skill`, `fury_plugin`, `fury_required_skill`, `fury_manifest`, `fury_mcp_declaration`, `fury_mcp_cli`, `ping`, `skill_version`, `identity`, `general_read` y `required_document`.

Mapear las filas runtime a los checks conceptuales del contrato:

- `Fury runtime discovery`: `fury_runtime_discovery_tools` y `fury_component_discovery`.
- `FuryDocs component`: `furydocs_component`.
- `FuryDocs required tools`: `fury_tool_discovery` y `furydocs_required_tools`.

Si una capa no corrió, mostrarla como no ejecutada con su failure code seguro; no presentarla como exitosa.

- `✅` = check verificado.
- `❌` = check crítico fallido.
- `⚠️` = integración opcional degradada o no verificable.

### Cierre

- Considerar críticos locales en todos providers soportados únicamente ACLI instalado y autenticado. Permisos persistentes del provider no forman parte de readiness; operaciones mutables quedan sujetas a autorización cuando se ejecutan. TEAM vacío limita `assign-unassigned`, pero no bloquea resto de readiness.
- Mostrar `✅ Setup completo. Podés usar /groot-queue list para empezar.` únicamente cuando críticos locales estén listos, fase shell esté lista y todos checks runtime estén listos.
- En cualquier otro caso, mostrar `⚠️ Setup incompleto`, listar cada limitación comprobada y remediación completa en español, y no afirmar que comandos operativos están disponibles mientras cualquiera de dos fases obligatorias no haya pasado.
- No mostrar referencias visibles a archivos, nombres como `setup.md` o `installation.md`, `$SKILL_DIR`, repo, anchors, secciones, tablas de fuentes ni “guía canónica”. No citar contratos internos aunque usuario pida fundamento. Esos recursos son inputs silenciosos para redactar instrucciones autocontenidas.
- Separar recuperación en `Puedo hacerlo por vos`, `Tenés que hacer vos`, `Comandos para copiar y pegar` y `Validación`, omitiendo secciones vacías.
- Si existen acciones automatizables, cerrar con `Puedo ejecutar esos comandos por vos. ¿Querés que lo haga?` y esperar respuesta. No ejecutar mutaciones en misma respuesta del diagnóstico.
- Cuando usuario apruebe en turno posterior, ejecutar solo comandos ofrecidos, reportar resultado real y verificar inventario read-only. Después pedir pasos humanos pendientes (`/reload-plugins`, OAuth, VPN o restart) y terminar con `/groot-queue:setup` para Claude Code o `/groot-queue setup` para Codex.
- Si no existen acciones automatizables, mostrar pasos humanos y revalidación directamente.
- Nunca sugerir tokens, cookies o headers manuales; nunca hardcodear `cloudId`; nunca crear segundo MCP `fury`.
- Detener respuesta después de comando de revalidación u oferta `¿Querés que lo haga?`. No agregar “qué hice y por qué”, citas, fuentes ni explicación interna del checker.
