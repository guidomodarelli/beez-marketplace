# Nordic Testing and Observability Rules

Aplican a aplicaciones Nordic/Node y frontends React que agregan o modifican servicios, rutas, UI async o diagnósticos ErrorUX.

## Tests

- Ejecutar tests relevantes antes de cerrar cualquier cambio; si no se pueden ejecutar, informar el bloqueo.
- Testear comportamiento observable y contratos públicos; no leer strings de archivos fuente ni probar detalles de implementación.
- En tests de componentes, aislar servicios propios con spies cuando corresponda y no mockear componentes Andes, Nordic o SDK internos salvo imposibilidad técnica documentada.
- En tests de servicios Nordic, usar `nordic-dev/mocks` para interceptar HTTP; no mockear directamente `nordic/restclient`.
- Cubrir happy path, error, loading, empty, retry, cancelación y estados parciales cuando existan.
- Para `CustomErrorUXSnackbar`, cubrir: ErrorUX válido, error inesperado sin retry, fallback sin contexto, limpieza de estado stale y ausencia del snackbar en estados esperados.

## ErrorUX and diagnostic payloads

- `CustomErrorUXSnackbar` requiere un `ErrorUxContext` real; no fabricar uno desde el componente.
- El detail de ErrorUX puede incluir operación, etapa, categoría, código, dependencia, status, conteos y request/correlation/trace IDs permitidos.
- Nunca incluir condición raw, payload upstream, request/response completos, headers, cookies, tokens, secretos o PII completa en assertions, logs, DTOs o ErrorUX.
- Verificar que un response `202` degradado conserve su status, `pending_requirements` y contexto ErrorUX seguro sin convertir un estado de negocio válido en error técnico.
- Testear logs únicamente cuando formen parte del contrato explícito; preferir validar la proyección pública y el detail sanitizado.

## Async state

- Limpiar `errorMessage`, `ErrorUxContext`, timers, listeners y AbortControllers al cambiar de recurso, cerrar modal, iniciar una nueva operación o reintentar.
- No permitir que un retry cree una mutación duplicada ni que un resultado anterior actualice una selección nueva.
