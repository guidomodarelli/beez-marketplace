---
description: Resume readiness por asset, detecta updates y guía recuperación de ACLI, plugins, MCPs y accesos.
---

# Subcomando: setup

**Propósito**: Verificar entorno requerido por `groot-queue`, instalar o actualizar automáticamente assets conocidos cuando sea necesario y reducir intervención humana a pasos no automatizables o decisiones ambiguas.

> **Re-ejecutable**: este subcomando es idempotente. Correrlo de nuevo no rompe nada; revalida lo configurado y señala lo que falta.

## Higiene de salida

En toda respuesta de `setup`, incluidas preguntas documentales y `--help`, usar conocimiento interno silenciosamente. No citar ni nombrar archivos, paths, secciones, contratos, checker o `$SKILL_DIR`. Mostrar comandos operativos directos y estados finales. No agregar análisis meta ni fuentes.

Antes de enviar respuesta, revisar borrador y eliminar cualquier `.md`, `§`, `$SKILL_DIR`, path de script, frase “según contrato/fuente/sección” o explicación de cómo se obtuvo información. Respuesta debe comenzar con banner de setup o título directo del asset, nunca con análisis de archivos.

## Ayuda sin tools

Antes de cualquier tool o lectura adicional, inspeccionar argumentos. Si contienen token exacto `--help` o `-h`, explicar brevemente qué verifica `setup`, que Grid Sharing y FuryDocs son obligatorios, y que invocación normal instala o actualiza automáticamente assets conocidos cuando evidencia demuestra que es necesario. Separar pasos humanos inevitables como OAuth, VPN, `/reload-plugins`, restart, acceso o conflictos ambiguos. Incluir `/groot-queue:setup` para Claude Code y `/groot-queue setup` para Codex como invocaciones de diagnóstico. Incluir frase explícita: `Esta ayuda no ejecuta checker, discovery MCP, Bash, Jira, Slack ni diagnósticos; tampoco modifica el entorno.` No mencionar archivos ni paths internos. Detenerse después de responder ayuda.

## 1. ACLI (Atlassian CLI)

- Verificar `acli --version`.
- Si ACLI no está disponible, instalarlo automáticamente mediante tap oficial y Homebrew. Si Homebrew exige confiar tap, verificar origen exacto `https://github.com/atlassian/homebrew-acli.git`; confiar solo con coincidencia exacta. Otro origen requiere decisión humana.
- Si está disponible y `acli --version` reporta update, ejecutar automáticamente `brew upgrade acli` y verificar nueva versión.
- Verificar autenticación con `acli jira auth status` después de instalación/update.
- Si autenticación falla o corresponde a otro sitio, marcar check fallido y mostrar inline `acli jira auth login --web` seguido de `acli jira auth status`; login queda como paso humano.

## 2. Atlassian MCP

El subcomando `derive` usa el MCP de Atlassian para ejecutar la transición "Derivar a otro equipo". Leer `$SKILL_DIR/knowledge/config/atlassian-mcp.md` como referencia canónica de instalación y errores.

- Verificar si el contexto expone un MCP de Atlassian compatible.
- Si el provider no expone esas tools, informar que la derivación automática debe completarse manualmente en Jira.
- Si solo permite comentarios públicos y no notas internas de Jira Service Management, no automatizar la derivación.
- Si tools no están disponibles y inventario confirma plugin oficial ausente, instalar automáticamente `atlassian@claude-plugins-official` en scope `user`. Después pedir `/reload-plugins` y OAuth desde `/mcp`.
- Si existe integración manual, oficial duplicada o inventario ambiguo, no reemplazar ni eliminar nada: mostrar conflicto y pedir elección.
- Si plugin existe pero autenticación falla, no reinstalar; pedir OAuth desde `/mcp`.
- Si está disponible, verificar autenticación y resolver el `cloudId` con las tools del provider actual. No hardcodearlo.

## 3. Slack MCP

El subcomando `alerts` usa Slack MCP para enviar DMs de SLA. Los nombres de las tools varían según provider y configuración.

- Buscar capacidades compatibles para localizar usuarios y enviar mensajes, sin depender de un nombre exacto de tool.
- Si tools no existen y inventario confirma plugin oficial ausente, instalar automáticamente `slack@claude-plugins-official` en scope `user`. Después pedir `/reload-plugins` y OAuth desde `/mcp`; hasta completarlo, `alerts` solo puede ejecutarse con `--dry-run`.
- Si plugin existe pero tools no están autenticadas, no reinstalar; mantener modo degradado y pedir OAuth desde `/mcp`.
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

### 6.1 Reparación automática allowlisted

Invocar `setup` autoriza instalación/update automático de assets conocidos. Antes de ejecutar, leer comandos canónicos del provider en `$SKILL_DIR/knowledge/config/installation.md` y usarlos literalmente. En respuesta, reproducir comando ejecutado sin citar fuente interna. Nunca inventar slash commands como `/install`; instalaciones y updates se ejecutan con CLI `claude` o `codex` desde shell.

Después de primer diagnóstico shell, agrupar failures por causa y ejecutar únicamente acciones necesarias:

- `LOCAL_DEPENDENCY_UNAVAILABLE`: identificar herramienta faltante entre dependencias documentadas e instalarla con Homebrew.
- `PLUGIN_NOT_INSTALLED`: asegurar marketplace técnico conocido e instalar `grid-sharing` para provider activo.
- `REQUIRED_SKILL_UNAVAILABLE` con plugin presente: actualizar `grid-sharing`; no reinstalar mediante comando de install.
- `FURY_PLUGIN_NOT_INSTALLED`: asegurar marketplace técnico conocido e instalar `fury-services`.
- `FURY_REQUIRED_SKILL_UNAVAILABLE`, `FURY_MANIFEST_UNAVAILABLE` o `FURY_MCP_DECLARATION_UNAVAILABLE` con plugin presente: actualizar `fury-services`; no reinstalar mediante comando de install.
- `PLUGIN_VERSION_INCOMPATIBLE`: ejecutar comando canónico de update de `grid-sharing`, nunca comando de install.
- Plugin conocido deshabilitado: habilitarlo automáticamente solo si CLI activa ofrece comando inequívoco; en otro caso pedir paso manual desde gestor de plugins.

Para Claude Code usar scope `user`; después de cambios pedir `/reload-plugins` y restart solo si recarga no alcanza. Para Codex usar comandos propios sin `--scope`; nunca sugerir `/reload-plugins`, pedir restart. Agregar cada marketplace una sola vez después de inspeccionar inventario. No ejecutar uninstall, `--prune`, reemplazos, MCP Fury manual ni cambios de settings.

Si failure es inventario ambiguo/inválido, configuración inválida, origen no oficial, conflicto de integraciones, permiso/ACL, VPN, OAuth o decisión de trust no verificable, no mutar: pedir intervención humana específica.

Después de acciones automáticas, verificar comandos ejecutados y repetir fase shell una sola vez, sin `--reuse-result`. Conservar resultado más reciente. No entrar en loop. Si instalación/update requiere runtime nuevo, continuar diagnóstico runtime actual, marcarlo stale cuando corresponda y pedir `/reload-plugins` o restart.

## 7. Fase runtime MCP — diagnóstico independiente

Ejecutar este diagnóstico después del intento shell incluso cuando la fase shell haya fallado. No reutilizar un resultado runtime anterior.

1. Detectar únicamente tools de discovery inequívocamente pertenecientes al server MCP `fury` del provider actual. En Claude Code, preferir `mcp__plugin_fury-services_fury__list_components` y `mcp__plugin_fury-services_fury__list_tools`; aceptar solo equivalentes exactos del mismo server.
2. Si ambas tools están disponibles, invocar **solo** `list_components` sin argumentos. No mostrar el payload completo.
3. Si la respuesta es válida, exigir un componente cuyo `name` sea exactamente `furydocs`.
4. Si el componente existe, invocar **solo** `list_tools` con `component="furydocs"`. Exigir los nombres exactos `get_doc_structure` y `get_doc_file`; permitir tools adicionales.
5. No invocar `get_doc_structure`, `get_doc_file` ni ninguna otra tool documental.
6. Si tools de discovery no están disponibles o capa falla, registrar check y failure code exactos. Si diagnóstico shell confirmó Fury Services ausente/desactualizado, reparación automática ya debió instalarlo/actualizarlo. Pedir `/reload-plugins`; si persiste, pedir restart y revalidación. No crear conexión MCP `fury` alternativa ni reconstruir transporte.

Esta fase es independiente y no serializable: no escribir su estado en archivos ni variables de entorno y no inferirla desde el JSON shell.

## Output esperado

Priorizar lectura operativa: mostrar resumen y una fila por asset. No renderizar tabla exhaustiva de checks técnicos. Conservar failure codes y checks internos para decidir estado y armar detalles solo cuando exista una acción.

### 1. Resumen superior

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Setup — Groot Queue
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Estado: <✅ LISTO | ⚠️ DEGRADADO | ❌ BLOQUEADO>
<assets listos> assets listos · <bloqueos> bloqueos · <warnings> warnings · <updates> updates
Provider: <Claude Code | Codex>
```

- `✅ LISTO`: ACLI instalado/autenticado, shell completo y runtime FuryDocs completo. Integraciones opcionales pueden tener warnings sin bloquear.
- `⚠️ DEGRADADO`: críticos listos, pero Atlassian MCP, Slack MCP o TEAM limitan alguna función.
- `❌ BLOQUEADO`: falla ACLI, Grid Sharing, Fury Services, FuryDocs o cualquier capa obligatoria shell/runtime. Asset crítico instalado/actualizado en disco pero stale hasta reload/restart sigue bloqueado hasta revalidación exitosa; nunca clasificarlo como degradado.
- Contar siete assets: ACLI, Atlassian MCP, Slack MCP, Grid Sharing, Fury Services, FuryDocs y TEAM.
- Contar cada asset una sola vez aunque tenga varios failure codes. `updates` cuenta assets cuyo update fue detectado durante invocación; después de update exitoso conservar conteo como updates aplicados, mostrar `✅ <versión nueva>` en tabla y registrar `instalada → nueva` en detalle `Acción automática`.

### 2. Tabla resumida por asset

Usar siempre este orden y columnas:

| Asset | Instalado | Conectado | Up-to-date | Impacto | Próximo paso |
|---|---|---|---|---|---|
| 🎫 ACLI | <estado + versión> | <OAuth> | <estado> | 🔴 Bloqueante | <acción o —> |
| 🔗 Atlassian MCP | <estado> | <OAuth> | — | 🟡 Degrada | <acción o —> |
| 💬 Slack MCP | <estado> | <OAuth> | — | 🟡 Degrada | <acción o —> |
| 🧩 Grid Sharing | <plugin + skill> | <VPN + identidad + lecturas> | <versión remota> | 🔴 Bloqueante | <acción o —> |
| 🔥 Fury Services | <plugin + skill + manifest> | <MCP CLI + discovery> | <verificable o ❔> | 🔴 Bloqueante | <acción o —> |
| 📚 FuryDocs | — | <componente + tools> | — | 🔴 Bloqueante | <acción o —> |
| 👥 TEAM | <cantidad o vacío> | — | — | 🟡 Degrada | <acción o —> |

Reglas de agregación:

- **ACLI**: `Instalado` usa resultado y versión de `acli --version`; `Conectado` usa `acli jira auth status`. `Up-to-date` muestra `⬆️ instalada → disponible` cuando CLI reporta update; muestra `✅ <versión>` cuando verificación de versión no reporta update; si no puede determinarse, `❔ No verificable`.
- **Atlassian MCP**: `Instalado` refleja disponibilidad inequívoca de tools; `Conectado` exige OAuth y recurso corporativo resuelto. No mostrar `cloudId`.
- **Slack MCP**: `Instalado` refleja tools compatibles; `Conectado` exige probe autenticado read-only.
- **Grid Sharing**: `Instalado` exige `grid_plugin` y `grid_required_skill`; `Conectado` exige `ping`, `identity`, `general_read` y `required_document`; `Up-to-date` usa exclusivamente `skill_version`.
- **Fury Services**: `Instalado` exige plugin, skill, manifest y declaración MCP; `Conectado` exige MCP CLI y discovery runtime. Marcar `Up-to-date` como `❔ No verificable` si no existe comparador de versión explícito; nunca inferirlo desde instalación.
- **FuryDocs**: `Conectado` exige componente exacto y ambas tools requeridas. Instalación y versión no aplican porque es componente de Fury Services.
- **TEAM**: mostrar cantidad verificada; vacío produce warning sin bloquear demás assets.

`Próximo paso` debe ser corto y accionable: `Actualizar ACLI`, `Instalar plugin`, `Completar OAuth en /mcp`, `Conectar VPN`, `Ejecutar /reload-plugins`, `Reiniciar provider`, `Solicitar acceso`, `Configurar TEAM` o `—`.

### 3. Iconos

- `✅`: listo y verificado.
- `⬆️`: update disponible.
- `⚠️`: degradado.
- `❌`: fallo.
- `⏭️`: no ejecutado porque dependencia anterior falló.
- `❔`: no verificable con fuente disponible.
- `—`: no aplica o no requiere acción.

No usar `✅` para estado inferido. Si capa no corrió, usar `⏭️` con failure code seguro en detalle, no presentarla como fallo independiente.

### 4. Detalles solo cuando requieren atención

Después de tabla, crear sección por asset únicamente si tiene `❌`, `⚠️`, `⬆️` o próximo paso distinto de `—`. No explicar assets completamente listos ni repetir tabla técnica.

Cada detalle usa formato de recuperación conversacional: título con icono y asset, causa/failure codes seguros, `Acción automática` con comando + resultado real, `Tenés que hacer vos` solo cuando sea inevitable, y validación. Omitir bloques vacíos.

Nunca mostrar como filas independientes `provider_inventory`, `fury_manifest`, `fury_mcp_declaration`, `general_read`, `required_document` ni otros checks internos. Esos checks alimentan asset agregado correspondiente.

### Cierre

- Considerar críticos locales en todos providers soportados únicamente ACLI instalado y autenticado. Permisos persistentes del provider no forman parte de readiness; operaciones mutables quedan sujetas a autorización cuando se ejecutan. TEAM vacío limita `assign-unassigned`, pero no bloquea resto de readiness.
- Con `✅ LISTO`, cerrar `✅ Setup completo. Podés usar /groot-queue list para empezar.`
- Con `⚠️ DEGRADADO`, cerrar `⚠️ Setup operativo con limitaciones`, nombrar comandos afectados por integraciones opcionales y mostrar próximo paso; no bloquear comandos no afectados.
- Con `❌ BLOQUEADO`, cerrar `❌ Setup bloqueado`, enumerar assets críticos a resolver primero y no afirmar que comandos operativos están disponibles mientras cualquiera de dos fases obligatorias no haya pasado.
- No mostrar referencias visibles a archivos, nombres como `setup.md` o `installation.md`, `$SKILL_DIR`, repo, anchors, secciones, tablas de fuentes ni “guía canónica”. No citar contratos internos aunque usuario pida fundamento. Esos recursos son inputs silenciosos para redactar instrucciones autocontenidas.
- Separar recuperación en `Acción automática`, `Tenés que hacer vos` y `Validación`, omitiendo secciones vacías.
- Ejecutar acciones allowlisted durante misma invocación sin pedir aprobación adicional. Reportar comando, resultado real y verificación; nunca describir acción no ejecutada como completada.
- Pedir acción humana solo para `/reload-plugins`, OAuth, VPN, restart, acceso, conflicto, origen no verificable o decisión destructiva/ambigua.
- Después de pasos humanos pendientes, terminar con `/groot-queue:setup` para Claude Code o `/groot-queue setup` para Codex.
- Nunca sugerir tokens, cookies o headers manuales; nunca hardcodear `cloudId`; nunca crear segundo MCP `fury`.
- Detener respuesta después de comando de revalidación. No agregar “qué hice y por qué”, citas, fuentes ni explicación interna del checker.
