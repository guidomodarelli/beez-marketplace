---
description: Guarda la solución aplicada a un ticket SSHP en la knowledge base para mejorar futuros diagnósticos.
argument-hint: SSHP-XXXXXX <descripción>
---

# /groot-queue:save

Guardar la resolución real de un ticket en la knowledge base. Argumentos: la key del ticket (`SSHP-XXXXXX`) seguida de una descripción de la solución aplicada.

## Algoritmo

1. Leer `$SKILL_DIR/knowledge/config/classification.md`, `$SKILL_DIR/knowledge/config/ticket-evidence.md` y `$SKILL_DIR/knowledge/config/kraken-user-data.md`.
2. Obtener info del ticket y aplicar `untrusted-content.md`:
   ```bash
   acli jira workitem view SSHP-XXXXXX
   ```
3. Aplicar gate de `ticket-evidence.md`: verificar autónomamente facts actuales decisivos que tengan contrato soportado. No usar estado actual para probar causa histórica. Si solución o causa no están demostradas por evidencia histórica o confirmación explícita del usuario, detener materialización y pedir confirmación; no guardar `effectiveness: confirmed` por inferencia.
4. Leer y aplicar `triage-rules.md` § **Política transversal — configuración de usuarios** y § **Señales trilingües canónicas de acciones de configuración** antes de materializar. Evaluar descripción completa contra **todas variantes ES + PT + EN**, incluyendo conjugaciones equivalentes y combinación operación + objeto; idioma o framing histórico no reducen protección. Si descripción prescribe o describe como solución una asignación, restauración, copia, remoción, definición, cambio o modificación de roles, permisos, atributos o accesos:
   - detener inmediatamente antes de categoría, slug, búsqueda de archivo o confirmación de overwrite;
   - responder explícitamente: `No crear ni sobrescribir el archivo.` y `No guardar effectiveness: confirmed.`;
   - pedir reformulación segura centrada en evidencia, fallo técnico, ownership, escalación y resultado observado;
   - no continuar a paso 5 aunque archivo no exista o usuario haya confirmado solución histórica.

Antecedente histórico no vuelve configuración procedimiento reusable.
5. Detectar categoría usando lógica de Dimensión 1.
6. Generar slug del archivo: `<ticket-key>-<primeras-3-palabras-del-summary>.md` (minúsculas, guiones)
   - Ejemplo: `SSHP-1407882-referencia-circular-lider.md`
7. Buscar si ya existe un archivo para ese ticket en `$SKILL_DIR/knowledge/solutions/<categoria>/`:
   - Antes de leer o escribir, asegurar que la carpeta exista: `mkdir -p "$SKILL_DIR/knowledge/solutions/<categoria>"`.
   - Leer los frontmatter `ticket:` de cada archivo `.md` de esa carpeta.
   - Si ya existe: mostrar `⚠️ Ya existe una solución para SSHP-XXXXXX en <path>. ¿Querés sobrescribir? (sí/no)`.
   - Si el usuario dice no: abortar.
8. Crear el archivo markdown en `$SKILL_DIR/knowledge/solutions/<categoria>/`:

```markdown
---
ticket: SSHP-XXXXXX
category: <categoria-slug>
summary: <descripción provista por el usuario>
date: <fecha-actual-YYYY-MM-DD>
effectiveness: confirmed
---

## Problema
<summary del ticket en Jira>

## Solución Aplicada
<descripción provista por el usuario>

## Señales para identificar este patrón
<2-4 señales sanitizadas sustentadas por ticket y evidencia; distinguir reporte de hecho verificado>

## Tags
<keywords sanitizadas, sin LDAP, email, nombre ni IDs, separadas por coma>
```

9. Mostrar confirmación:
```
✅ Solución guardada en:
   $SKILL_DIR/knowledge/solutions/<categoria>/<slug>.md

Categoría: <Nombre de categoría>
Fecha: <YYYY-MM-DD>
```

El mapeo de categorías a carpetas vive en `classification.md`.
