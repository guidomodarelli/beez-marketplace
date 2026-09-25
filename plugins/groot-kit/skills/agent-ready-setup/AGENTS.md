# agent-ready-setup

## Consistencia de instrucciones

Al agregar o modificar una rule, skill, agent, command, template de instrucciones o cualquier otra instrucción de este skill:

1. Antes de cerrar el cambio, verificar que no contradiga ni duplique las instrucciones que se cargan junto con ella:
   - rules comunes de `assets/common/rules/`;
   - rules, skills, agents y commands de `assets/stacks/<stack>/`;
   - bloque gestionado de `AGENTS.md` (`assets/stacks/<stack>/CLAUDE.md` y `assets/instruction-centralization.md`);
   - proxy `assets/claude-proxy.md`;
   - `SKILL.md`.
2. Revisar el mismo cambio en todos los stacks (`frontend`, `node`, `java`, `go`) cuando aplique. Si una rule aplica igual a todos los stacks, publicarla una sola vez en `assets/common/rules/` en lugar de copiarla en cada stack.
3. Verificar que cada referencia a un archivo o sección apunte a uno existente.
4. Reportar al usuario cada inconsistencia encontrada (contradicción, duplicado o referencia rota) con paths, fragmentos afectados y una recomendación. No resolver en silencio contradicciones que requieran decidir precedencia.
