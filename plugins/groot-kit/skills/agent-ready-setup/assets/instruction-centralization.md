## Centralización recursiva de instrucciones

`AGENTS.md` es fuente canónica para instrucciones de agente. Regla aplica a cada `CLAUDE.md` del proyecto, tanto en raíz como en subdirectorios.

Para cada `CLAUDE.md`, usar únicamente `AGENTS.md` hermano ubicado en mismo directorio. Nunca sustituirlo por `AGENTS.md` de raíz, directorio padre u otro nivel.

Cuando usuario solicite agregar, modificar o eliminar contenido de cualquier `CLAUDE.md`:

1. Identificar directorio exacto de `CLAUDE.md` solicitado.
2. Resolver `AGENTS.md` hermano en ese directorio.
3. Aplicar cambio en `AGENTS.md`.
4. No editar directamente `CLAUDE.md`.
5. Evitar instrucciones duplicadas o contradictorias entre ambos archivos.

La referencia `@AGENTS.md` se resuelve relativa al directorio que contiene `CLAUDE.md`.

### Normalización por directorio

- Si existe solo `AGENTS.md`, crear `CLAUDE.md`. En raíz, incluir `@AGENTS.md` más instrucción de centralización; en subdirectorios, incluir únicamente `@AGENTS.md`.
- Si existe solo `CLAUDE.md`, crear `AGENTS.md` hermano, mover allí contenido de `CLAUDE.md` y omitir únicamente primera línea cuando sea exactamente `@AGENTS.md`; después reemplazar `CLAUDE.md` por proxy correspondiente a su ubicación.
- Si ambos existen y `CLAUDE.md` ya está normalizado, no modificarlo.
- Si `CLAUDE.md` contiene instrucciones adicionales ausentes en `AGENTS.md`, migrarlas a `AGENTS.md` sin perder contenido y normalizar `CLAUDE.md`.
- Si ambos archivos son contradictorios, no sobrescribir automáticamente; informar paths exactos y solicitar resolución explícita.

Aplicar búsqueda recursiva cuando se solicite normalizar proyecto completo. Preservar contenido antes de migrarlo. No seguir ni sobrescribir symlinks automáticamente; tratar symlinks, directorios, archivos ilegibles y conflictos como resolución manual. Reportar archivos creados, migrados, normalizados, omitidos y conflictos.
