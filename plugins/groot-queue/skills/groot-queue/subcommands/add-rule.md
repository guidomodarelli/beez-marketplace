---
description: Agrega una nueva regla de triage (DESCARTAR / DERIVAR / FIX_APLICADO) a triage-rules.md mediante flujo interactivo.
---

# /groot-queue:add-rule

Sumar una nueva regla de triage a `triage-rules.md` mediante un flujo interactivo, para que el equipo pueda incorporar patrones detectados sin editar el archivo a mano.

**Alcance**: Solo edita `triage-rules.md` (sección de reglas + bloque "Algoritmo de triage"). Para soluciones puntuales a un ticket seguir usando `/groot-queue:save`.

## Algoritmo

1. **Leer** `$SKILL_DIR/knowledge/rules/triage-rules.md` completo. Identificar:
   - El último número usado por cada familia: `R-DESC-NN`, `R-DER-NN`, `R-FIX-NN`.
   - La sección "Algoritmo de triage" (lista numerada al final).

2. **Recolectar datos** preguntando al usuario uno por uno (usar `AskUserQuestion` para opciones cerradas, prompt directo para texto libre):

   a. **Tipo de regla** (single-select): `DESCARTAR` / `DERIVAR` / `FIX_APLICADO`
   b. **Título corto** (texto): frase breve que describe el patrón (ej: "Tax ID inválido → IAM Soporte")
   c. **Señales** (texto multilínea): bullets concretos (summary/description matchers, URLs, contexto). Pedir al menos 2 señales.
   d. **Razón** (texto): por qué corresponde el veredicto (1-3 oraciones)
   e. **Verificación previa** (texto, opcional): condiciones que invalidarían la regla y deberían reclasificar. Si el usuario dice "ninguna" o vacío, omitir el campo.
   f. **Acción** (texto): qué hacer concretamente — para `DESCARTAR`: "Cerrar como Won't Do / Cancelled". Para `DERIVAR`: "Derivar a **<Equipo>**". Para `FIX_APLICADO`: "Cerrar como Done tras verificar query".
   g. **Comentario sugerido** (texto): copy validado para responder al usuario. Importante mantener el texto literal del equipo (no normalizar agresivamente).
   h. **Verificación SQL** (solo si `FIX_APLICADO`, texto): query para confirmar que el fix está aplicado.
   i. **Fuente** (texto): formato `<autor>, <ticket o contexto>, <fecha YYYY-MM-DD>`. Si el usuario no provee fecha, usar la fecha actual.
   j. **Posición en el algoritmo** (single-select): mostrar la lista numerada actual del bloque "Algoritmo de triage" y preguntar después de qué número insertar. Sugerir default según el tipo (FIX_APLICADO al inicio, DERIVAR con señal específica antes que genérica, DESCARTAR al final).

3. **Calcular nuevo ID**: incrementar el contador del tipo elegido. Ej: si la última `R-DER-XX` es `R-DER-12` → la nueva es `R-DER-13`.

4. **Construir bloque de la regla** con el siguiente formato exacto (mismo que las reglas existentes):

   ```markdown
   ### R-XXX-NN — <título>
   - **Señales**:
     - <señal 1>
     - <señal 2>
   - **Razón**: <razón>.
   - **Verificación previa**: <verificación>.   ← omitir línea si no se proveyó
   - **Verificación** (solo FIX_APLICADO):
     ```sql
     <query>
     ```
   - **Acción**: <acción>.
   - **Comentario sugerido**:
     > "<comentario tal cual lo dictó el usuario>"
   - **Fuente**: <fuente>.
   ```

5. **Insertar en la sección correcta** de `triage-rules.md`:
   - `DESCARTAR` → al final de la sección "Reglas `DESCARTAR`", antes del separador `---`.
   - `DERIVAR` → al final de la sección "Reglas `DERIVAR`", antes del separador `---`.
   - `FIX_APLICADO` → al final de la sección "Reglas `FIX_APLICADO`", antes del separador `---`.

   Usar el Edit tool con `old_string` = el último bloque de la sección destino + el separador `---`, y `new_string` = ese bloque + la nueva regla + separador. Mantener líneas en blanco consistentes con el archivo existente.

6. **Actualizar el bloque "Algoritmo de triage"**:
   - Insertar una nueva línea numerada en la posición elegida con el formato: `N. **R-XXX-NN** → <condición de match, 1 oración>.`
   - Renumerar en cascada todas las líneas posteriores.
   - Usar Edit tool con `old_string` = todo el bloque numerado actual, `new_string` = el bloque renumerado con la nueva línea.

7. **Mostrar confirmación**:
   ```
   ✅ Regla R-XXX-NN agregada a triage-rules.md

   Tipo:      <DESCARTAR / DERIVAR / FIX_APLICADO>
   Título:    <título>
   Posición:  #N en el algoritmo
   Fuente:    <fuente>

   La regla se aplicará en la próxima ejecución de `/groot-queue:list` o `/groot-queue:classify`.
   ```

## Validaciones

- Si el usuario aborta en cualquier paso (Ctrl+C / "cancelar"), no escribir nada.
- Si el tipo es `FIX_APLICADO` y no se provee query SQL, advertir pero permitir continuar (algunos fixes no requieren verificación SQL).
- Si el título o señales están vacíos, abortar con error claro.
- No permitir duplicados de ID: re-leer el archivo antes de calcular el contador (por si se ejecutó otro `add-rule` en paralelo en otra sesión).

**Nota**: Este comando **no** crea archivos en `solutions/`. Si la nueva regla tiene un caso concreto de referencia, sugerir al usuario al final: "Para guardar el caso concreto que originó esta regla, usá `/groot-queue:save SSHP-XXXXXX <descripción>`."
