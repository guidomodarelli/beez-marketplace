@AGENTS.md

## Identidad del equipo

> Fuente de verdad: `plugins/groot-queue/skills/groot-queue/knowledge/teams/groot-team.md`

- **Nosotros somos el equipo Groot**. Groot se compone de dos células: **Kraken** (auth/roles) y **Nexus** (gestión de usuarios shipping, Pidgey, Alfred, Chat Interno).
- Nunca referirse al equipo como si fuera externo ("escalar al equipo dev Groot"). Somos nosotros.
- Nunca mencionar ni sugerir `context_id` de Jira en soluciones, runbooks, guías ni respuestas. No es útil para diagnóstico ni resolución — es un dato interno de Jira sin valor operativo.

## Reglas de contenido para archivos de knowledge base

- **No incluir LDAPs ni identificadores de usuario específicos** en archivos de knowledge base (soluciones, reglas de triage, runbooks). Usar siempre referencias genéricas: `<ldap_usuario>`, `<ldap_externo>`, `<groot_id>`, `<nombre_usuario>`. Los patrones de prefijo sí son válidos (ej. `ext_*` para identificar el tipo de cuenta). El LDAP real pertenece al ticket SSHP, no a la KB.
- **Orden canónico de campos en frontmatter** de archivos `solutions/**/*.md`: `ticket` → `category` → `summary` → `date` → `effectiveness` → `verdict` → `rule` → `destination` → `source`. Omitir campos opcionales que no apliquen. No usar `derived_to` (usar `destination`). No usar `subverdict`.
