@AGENTS.md

## Reglas de contenido para archivos de knowledge base

- **No incluir LDAPs ni identificadores de usuario específicos** en archivos de knowledge base (soluciones, reglas de triage, runbooks). Usar siempre referencias genéricas: `<ldap_usuario>`, `<ldap_externo>`, `<groot_id>`, `<nombre_usuario>`. Los patrones de prefijo sí son válidos (ej. `ext_*` para identificar el tipo de cuenta). El LDAP real pertenece al ticket SSHP, no a la KB.
- **Orden canónico de campos en frontmatter** de archivos `solutions/**/*.md`: `ticket` → `category` → `summary` → `date` → `effectiveness` → `verdict` → `rule` → `destination` → `source`. Omitir campos opcionales que no apliquen. No usar `derived_to` (usar `destination`). No usar `subverdict`.
