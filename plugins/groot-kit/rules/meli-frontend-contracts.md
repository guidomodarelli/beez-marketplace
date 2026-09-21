# MELI Frontend and Nordic Contract Rules

Aplican a frontends MELI/Nordic que usan Andes, `nordic/i18n`, `nordic/logger` o ImageProvider.

## User-facing copy

- Todo texto visible de React —labels, botones, placeholders, helper/error text, toasts y aria labels— debe pasar por `i18n.gettext`.
- Reutilizar claves existentes antes de crear msgids nuevos; no editar catálogos generados manualmente si el workflow de i18n los administra.

## Andes and assets

- Usar componentes Andes para controles que Andes ya provee; no crear reemplazos custom.
- Usar tokens Andes y Sass Modules; no hardcodear colores, typography, spacing, breakpoints, radius o elevation.
- Usar `ImageProvider` para imágenes, iconos y fondos con rutas relativas o dependientes del entorno; preservar lazy loading y evitar URLs absolutas.

## Nordic server boundaries

- Validar `req.body`, `req.query` y `req.params` una sola vez en el boundary de la ruta con el validador aprobado por el proyecto.
- No pasar inputs no validados a servicios o clientes upstream.
- No exponer respuestas upstream raw, condiciones internas, tokens, cookies, headers de autorización ni PII en DTOs, HTML, logs o ErrorUX.
- Mantener scope y configuración de cliente en `config/`; no agregar `scope` a query params ni hardcodear ambientes.

## Logging

- Usar `nordic/logger`; no usar `console.*` en código de aplicación.
- Emitir mensajes con operación, etapa, resultado, código y contexto seguro; nunca loggear payloads completos o secretos.
