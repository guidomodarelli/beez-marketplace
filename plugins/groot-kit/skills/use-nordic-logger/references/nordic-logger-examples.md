# Ejemplos de migración a Logger

## Aplicación Nordic v9.8.0 o superior

Usar entry point `nordic/logger`; no agregar `@meli/logger` directamente.

### Antes

```ts
import LoggerFactory from 'nordic/logger';

const logger = LoggerFactory('products');

logger.info('products:getProducts started');
logger.verbose('products:getProducts request details', { step: 1 });
logger.silly('products:getProducts low-level details');
```

Import legacy también puede ser named:

```ts
import { LoggerFactory } from 'nordic/logger';
```

### Después

```ts
import { Logger } from 'nordic/logger';

const logger = new Logger('products');

logger.info('products:getProducts started');
logger.trace('products:getProducts request details', { step: 1 });
logger.trace('products:getProducts low-level details');
```

## Librería o aplicación no Nordic

Reemplazar dependencia `frontend-logger` por `@meli/logger` usando package manager del proyecto. Ejemplo con npm:

```bash
npm uninstall frontend-logger
npm install @meli/logger
```

### Antes

```ts
import LoggerFactory from 'frontend-logger';

const logger = LoggerFactory('products-library');
```

Import legacy también puede ser named:

```ts
import { LoggerFactory } from 'frontend-logger';
```

### Después

```ts
import { Logger } from '@meli/logger';

const logger = new Logger('products-library');
```

## Reemplazo de console.*

### Antes

```ts
console.error('get products failed', error);
```

### Después

```ts
import { Logger } from 'nordic/logger';

const logger = new Logger('products');

logger.error('products:getProducts failed', {
  errorMessage: error instanceof Error ? error.message : 'Non-Error value thrown',
  siteId,
});
```

Para librería o aplicación no Nordic, mantener ejemplo y cambiar únicamente import a `@meli/logger`.

## Route API con contexto seguro

```ts
import { Logger } from 'nordic/logger';

const logger = new Logger('products');

logger.error('products:getProducts failed', {
  method: req.method,
  route: req.route?.path,
  statusCode,
  siteId,
  limit,
  offset,
  requestId: req.headers['x-request-id'],
});
```

Preferir route template sobre URL completa para evitar query params sensibles y cardinalidad innecesaria.

## Middleware con contexto seguro

```ts
import { Logger } from 'nordic/logger';

const logger = new Logger('products');

logger.warn('validateProductsQuery: rejected invalid query parameters', {
  method: req.method,
  route: req.route?.path,
  requestId: req.headers['x-request-id'],
});
```

No adjuntar `req`, headers completos, cookies, tokens, payloads completos ni error sin sanitizar.

## Niveles disponibles

| Nivel | Uso |
|---|---|
| `trace` | Diagnóstico detallado; reemplaza `verbose` y `silly`. |
| `debug` | Diagnóstico útil durante desarrollo o troubleshooting. |
| `info` | Eventos operativos esperados. |
| `warn` | Condición inesperada o degradada que permite continuar. |
| `error` | Operación fallida o excepción recuperable. |
| `fatal` | Fallo irrecuperable que impide continuar. |

## Checklist

1. Usar named import `Logger`.
2. Crear instancia con `new Logger(name)`.
3. Elegir `nordic/logger` solo para aplicaciones Nordic `v9.8.0+`.
4. Elegir `@meli/logger` para librerías y aplicaciones no Nordic.
5. Cambiar `verbose` y `silly` por `trace`.
6. Ejecutar tests, lint y typecheck.
7. Verificar emisión real de logs sin secretos ni PII.

## Referencia API standalone

- [`@meli/logger`](https://github.com/melisource/fury_node-common-libs/tree/master/packages/logger)
