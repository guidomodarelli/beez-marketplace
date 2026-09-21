# Frontend User-Facing Feedback Rules

Aplican a React/Nordic/MELI cuando una acción crítica o async modifica, carga o solicita datos.

## Feedback y estados

- Validar inputs y estado permitido antes de ejecutar submit, search, navigation, edit, retry o mutation; bloquear acción inválida.
- Renderizar loading, éxito, vacío y error de forma explícita y accesible, cerca del control que inició la operación.
- Mantener separado estado de validación, estado de operación y `ErrorUxContext`; no reutilizar un mensaje genérico para estados distintos.
- Limpiar `errorMessage`, `validationMessage` y `ErrorUxContext` al cambiar recurso, facility, acceso, filtro, cerrar/reabrir modal, iniciar un intento nuevo o ejecutar retry.
- No mostrar un error de recurso anterior mientras un recurso nuevo está cargando o listo.

## ErrorUX y CustomErrorUXSnackbar

- Usar `CustomErrorUXSnackbar` únicamente cuando exista un `ErrorUxContext` real y el fallo sea accionable o inesperado y requiera registro/seguimiento en Failure Studio.
- Usar `Message`/`Snackbar` común para loading, información, warnings esperados, validación local, listas vacías y estados de negocio válidos.
- Si no existe contexto ErrorUX, mostrar fallback visual seguro; nunca fabricar un contexto.
- Habilitar retry solo cuando sea seguro/idempotente o reanude progreso conocido; evitar mutaciones duplicadas.
- Mantener mensaje público breve, localizado y separado del detail técnico.
- El detail puede ser rico y correlacionable, pero nunca debe contener condición raw, payload upstream, request/response, headers, cookies, tokens, secretos o PII completa.

## Accesibilidad

- Asociar feedback con el control o región afectada.
- Usar roles y live regions adecuados sin duplicar anuncios para el mismo error.
- Mantener foco y cierre/retry utilizables por teclado.
