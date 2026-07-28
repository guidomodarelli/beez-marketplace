@AGENTS.md

## Identidad del equipo

> Fuente de verdad: `plugins/groot-queue/skills/groot-queue/knowledge/teams/groot-team.md`

- **Nosotros somos el equipo Groot**. Groot se compone de dos células: **Kraken** y **Nexus**. Ver [`groot-team.md`](./plugins/groot-queue/skills/groot-queue/knowledge/teams/groot-team.md) para estructura y ownership, y [`nexus-team.md`, sección `Productos a cargo`](./plugins/groot-queue/skills/groot-queue/knowledge/teams/nexus-team.md#productos-a-cargo) para el catálogo Nexus.
- Nunca referirse al equipo como si fuera externo ("escalar al equipo dev Groot"). Somos nosotros.
- Nunca mencionar ni sugerir `context_id` de Jira en soluciones, runbooks, guías ni respuestas. No es útil para diagnóstico ni resolución — es un dato interno de Jira sin valor operativo.

## Single source of truth

- Toda pieza de información (procedimiento, roster, config, catálogo de IDs, formato, criterio) debe vivir en **un solo archivo** bien organizado con secciones claras.
- El resto de archivos que necesiten esa información deben **referenciar** el archivo + sección, nunca copiar el contenido.
- Antes de escribir un bloque de texto en un subcommand o regla, verificar si ya existe en otro archivo de `knowledge/`. Si existe, referenciar. Si no existe y es reutilizable, crearlo en `knowledge/` y referenciar.
- Cuando se detecte información duplicada entre archivos, consolidarla en el archivo más apropiado y reemplazar las copias por referencias.

## Reglas de contenido para archivos de knowledge base

- **No incluir LDAPs ni identificadores de usuario específicos** en archivos de knowledge base (soluciones, reglas de triage, runbooks). Usar siempre referencias genéricas: `<ldap_usuario>`, `<ldap_externo>`, `<groot_id>`, `<nombre_usuario>`. Los patrones de prefijo sí son válidos (ej. `ext_*` para identificar el tipo de cuenta). El LDAP real pertenece al ticket SSHP, no a la KB.
- **Orden canónico de campos en frontmatter** de archivos `solutions/**/*.md`: `ticket` → `category` → `summary` → `date` → `effectiveness` → `verdict` → `rule` → `destination` → `source`. Omitir campos opcionales que no apliquen. No usar `derived_to` (usar `destination`). No usar `subverdict`.

## Uso de subagentes

- No crear subagentes salvo pedido explícito del usuario.
- Para búsquedas, reviews y análisis multiarchivo, trabajar directamente en la sesión principal.
