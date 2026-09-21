# Payload Validation Boundaries

## Regla canónica

Separar estrictamente payloads de input middleend, DTOs públicos del middleend y respuestas de backend/upstream.

### Backend/upstream

- **NUNCA JAMÁS** aplicar validación completa de schema, negocio, campos o contrato a payloads recibidos desde backend/upstream.
- No revalidar respuestas upstream como si fueran input.
- No agregar Ajv, `@meli/input-validation`, Zod, schemas ni middleware de validación para respuestas upstream.
- No exigir esta validación en reviews, fixes, verificaciones, closeouts o skills.
- Consumir respuesta upstream según contrato del adapter y usar únicamente narrowing estructural mínimo cuando sea necesario para control flow o acceso seguro:
  - preferir HTTP status;
  - distinguir `null`, `array` y `object` cuando cambien el flujo;
  - leer discriminadores mínimos como `PROCESSING` y `FINISHED` cuando cambien la operación.
- Ese narrowing no valida el contrato upstream, no impone reglas de negocio al proveedor y no debe convertirse en una allowlist completa de sus campos.
- Si respuesta upstream no puede consumirse, mapear fallo controlado en adapter/service; no reenviar payload raw ni agregar validación completa.

### Middleend

- **SIEMPRE** validar `req.body`, `req.query` y `req.params` en boundary de entrada del middleend.
- Para validaciones requeridas, preferir Zod o `@meli/input-validation`; usar Ajv solo si Zod y `@meli/input-validation` no están disponibles o no pueden expresar el requisito. Reutilizar el validador ya adoptado por el repositorio cuando exista.
- Validar una única vez por ruta; handlers deben consumir valores ya validados y conservar únicamente reglas de negocio no expresables en schema.
- **SIEMPRE** validar el DTO público que el middleend entrega al client/consumer antes de usarlo, mediante el guard o mecanismo runtime aprobado por el repositorio.
- Los tests de validación deben ejercer el validador real y su contrato observable; no mockear el validador sin imposibilidad técnica justificada.
- Aplicar allowlist de campos públicos, tipos, estados y discriminadores del DTO middleend; rechazar shape no utilizable sin exponer diagnóstico interno.
- Mantener separadas validación de input middleend, validación de DTO middleend y consumo de respuesta upstream.

## Orden de decisión

1. Consultar HTTP status y metadata de transporte disponible.
2. Si control flow lo requiere, hacer narrowing estructural mínimo.
3. Para input middleend, ejecutar schema validation antes del handler.
4. Para DTO middleend, ejecutar guard/validación de contrato antes del consumer.
5. No convertir observación de una respuesta upstream en revalidación completa.

## Tests requeridos

- input middleend inválido rechazado en boundary;
- DTO middleend válido consumido y DTO no utilizable rechazado de forma segura;
- respuestas upstream consumidas sin schema revalidation;
- status `PROCESSING`/`FINISHED`, `array`/`object` o `null` distinguidos solo cuando cambian control flow;
- ausencia de validación duplicada en handlers;
- ausencia de payload upstream raw en respuesta, logs y errores públicos.
