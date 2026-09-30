---
name: nordic-local-mocks
description: Configura y depura mocks HTTP locales en cualquier aplicación Nordic usando nordic-dev/mocks, Mock.intercept y fixtures JSON. Invocar SIEMPRE antes de inspeccionar, crear, modificar, eliminar o validar mocks/fixtures, respuestas 404/500, request bodies, llamadas nordic/restclient, pruebas que generan fixtures, migraciones desde fakes o diferencias con Postman.
metadata:
  tags: "context-optimized-v1.18.2"
---

# Nordic Local Mocks

## Objetivo

Configurar entorno local para que clientes REST existentes reciban respuestas de fixtures, sin cambiar contratos ni recorrer una implementación paralela. Mantener autenticación, autorización, validación de entrada, métodos HTTP y lógica de dominio productivos; sustituir solo transporte upstream durante desarrollo.

## Alcance genérico

No asumir:

- nombre de aplicación, dominio o endpoint;
- `init.ts`, `mocks/index.js` u otra ubicación concreta;
- alias como `@root`;
- helper `isLocalEnvironment`;
- cliente específico como Management, Aggregator o Auth;
- estructura `api/`, `app/` o `utils/`;
- facility, usuario, atributo o mensaje de error de un proyecto.

Descubrir esos valores en cada repositorio. Cualquier path, endpoint, helper, identificador o error concreto de este documento es ejemplo ilustrativo, salvo que corresponda al proyecto inspeccionado.

## Cuándo aplicar

Aplicar workflow cuando usuario mencione:

- `Mock.intercept`, `nordic-dev/mocks` o `frontend-mocks`;
- mocks locales, fixtures de desarrollo o directorios `mocks/*`;
- `npm run dev`, `NODE_ENV=development` o servidor Nordic local;
- migración de fake local en TypeScript/JavaScript hacia fixtures HTTP;
- request que funciona en Postman pero falla desde app;
- errores de hydration, `502`, `404` inesperado o respuesta upstream ausente durante desarrollo.

Ejemplos concretos, no requisitos: `mocks/development`, `process-contingency`, `users-batch-hydrated`, `ARBA00TCOCU` y `User attribute hydration failed`.

## Reglas principales

1. Usar clientes REST y adapters ya existentes. No crear ramas locales que retornen datos directamente si objetivo es probar integración HTTP.
2. Registrar interceptores solo en entorno de desarrollo local. Mantener protección explícita contra producción y separar comportamiento de tests.
3. Cargar entrypoint de mocks explícitamente desde bootstrap server cuando framework/build no lo descubra automáticamente.
4. Reutilizar helper de entorno existente si existe. Si falta, crear helper cohesivo sobre `nordic/env` en ubicación convencional del proyecto.
5. No desactivar autenticación, autorización, CSRF ni schema validation para que fixture responda.
6. Usar allowlists de hosts y paths derivadas de configuración del proyecto; no aceptar destinos controlados por usuario.
7. Usar únicamente datos determinísticos sintéticos e inventados; no copiar nombres, IDs, LDAP, emails, facilities, tokens, cookies, secrets, PII real ni respuestas upstream sensibles.
8. No crear ni persistir nunca una propiedad `headers` en fixtures. Quedan prohibidos `headers: {...}`, `headers: {}`, headers vacíos, placeholders y copias de headers upstream. Si una captura incluye `headers`, eliminar la propiedad completa antes de guardar; si transporte falla sin ella, detenerse e informar el bloqueo en vez de inventarla.
9. No guardar ninguna `property` cuyo nombre empiece en `x-`; omitirla antes de persistir o versionar fixture, sin renombrarla ni trasladarla.
10. Tratar `ignoreParams` como normalización de filename, nunca como control de autorización o validación.

## Descubrimiento inicial

Antes de editar:

1. Leer instrucciones del proyecto y comandos oficiales.
2. Confirmar dependencias/versiones de Nordic y `nordic-dev` en `package.json`.
3. Localizar bootstrap, entrypoint de mocks, clientes REST y fixtures:

```bash
rg -n "Mock\.intercept|nordic-dev/mocks|frontend-mocks|NODE_ENV|PRODUCTION|DEVELOPMENT" . --glob '!node_modules/**'
find . -type f \( -path '*/mocks/*' -o -path '*/clients/*' -o -path '*/services/*' \) -not -path './node_modules/*' -print
```

4. Leer clientes para obtener base URL y path reales desde configuración. No inferirlos por nombre de fixture.
5. Buscar helper de entorno en `utils/`, `config/`, `lib/` o equivalente:
   - si existe, verificar semántica y reutilizarlo;
   - si falta, crear helper genérico usando `nordic/env`, `DEVELOPMENT`/`NODE_ENV` y exclusión de `PRODUCTION`;
   - adaptar nombre, export y alias al proyecto, sin asumir `@root` ni `isLocalEnvironment`.
6. Inventariar fake local, estado en memoria y ramas que evitan clientes: listados, catálogos, búsquedas, mutations, polling y cancelaciones.
7. Identificar requests del flujo inicial, incluyendo método, host, path, query y body serializado.

## Bootstrap

Crear un entrypoint de mocks en ubicación que framework ya cargue, o conectarlo desde bootstrap server. Ejemplo genérico:

```js
const env = require('nordic/env');
const config = require('nordic/config');

const registerLocalMocks = (mock) => {
  const ignoreScope = { ignoreParams: ['scope'] };

  mock.intercept(config.get('<upstream-base-url-key>'), [
    `/${config.get('<upstream-path-key>')}/*`,
  ], ignoreScope);
};

if (!env.PRODUCTION) {
  const mock = require('nordic-dev/mocks')();

  if (env.TEST) {
    // Preserve existing test-only interceptors.
  } else if (env.DEVELOPMENT) {
    registerLocalMocks(mock);
  }
}
```

Si build coloca bootstrap bajo una carpeta generada y no copia entrypoint de mocks, resolver raíz con `process.cwd()` desde el bootstrap. Usar helper existente:

```ts
import { isDevelopmentEnvironment } from '<project-environment-helper>';

if (isDevelopmentEnvironment()) {
  // Resolve repository-root mocks because compiled bootstrap runs from a generated directory.
  // eslint-disable-next-line @typescript-eslint/no-require-imports, import/no-dynamic-require, n/global-require
  require(`${process.cwd()}/<mocks-entrypoint>`);
}
```

Si helper no existe, crearlo antes:

```ts
import env from 'nordic/env';

export const isDevelopmentEnvironment = (): boolean => Boolean(env.DEVELOPMENT) && !env.PRODUCTION;
```

Adaptar import/export al formato real. Verificar build: un `import './mocks'` relativo puede buscar dentro de carpeta generada y fallar aunque compilación TypeScript pase.

## Interceptores

Separar base URL de rule path. Registrar un interceptor por upstream lógico y limitar paths a endpoints requeridos:

```js
mock.intercept(config.get('<service-base-url>'), [
  '/<service-prefix>/<resource>/*',
], {
  ignoreParams: ['scope'],
});
```

Buenas prácticas:

- obtener host/base desde config, no duplicar dominios por ambiente;
- usar paths concretos cuando sea posible;
- evitar `/*` en host compartido;
- conservar método HTTP cuando endpoint cambia estado: `POST`, `PUT`, `PATCH` o `DELETE`;
- registrar rutas de lectura y escritura por separado si requieren fixtures diferentes;
- no interceptar producción aunque `mocks/index.js` sea importado allí.

### Ejemplo ilustrativo de varios clientes

Este mapa es solo ejemplo. Reemplazar nombres por clientes y config keys descubiertos:

| Cliente lógico | Base | Paths posibles |
|---|---|---|
| API de usuarios | base de servicio de usuarios | `/users/*`, `/users/search` |
| API de atributos | base de atributos | `/attributes/*/values` |
| API de autenticación | base interna | `/auth/*` |
| API de compatibilidad | base de integración | `/compatibility/*` |

## Fixtures JSON

`frontend-mocks` suele escribir bajo `mocks/${NODE_ENV}`. Respetar nombres y carpetas generados por framework; modificar contenido únicamente cuando usuario lo pida. Confirmar `.gitignore`: si fixtures deben viajar en PR, versionarlos explícitamente y evitar que queden solo en filesystem local.

### Datos sintéticos y headers

Antes de guardar, generar o versionar una fixture:

1. Usar datos determinísticos inventados, sin copiar respuesta upstream real. Sustituir nombres, IDs, LDAP, emails, facilities y cualquier PII por valores ficticios mínimos.
2. Eliminar siempre la propiedad `headers` completa antes de persistir la fixture. No escribir `headers: {...}`, `headers: {}`, headers parciales ni placeholders para imitar respuesta upstream.
3. Si cliente o transporte parece exigir headers, no agregarlos a la fixture: revisar contrato del cliente, configuración del mock o bootstrap y detener persistencia si el caso no puede resolverse sin esa propiedad. Informar bloqueo concreto.

### Properties excluidas

Recorrer todas las propiedades restantes, incluidas las anidadas, y omitir cualquier clave cuyo nombre empiece exactamente en `x-` (`propertyName.startsWith('x-')`). No confundir esta regla con valores que contengan `x-`: solo se filtran nombres de propiedades. No renombrar ni reemplazar claves excluidas; si fixture depende de ellas, detener persistencia e informar el conflicto.

Response simple preferida:

```json
{
  "status": 200,
  "statusText": "OK",
  "data": {
    "results": []
  }
}
```

### Array de datos versus respuestas secuenciales

Array de recursos pertenece dentro de `data`:

```json
{
  "status": 200,
  "statusText": "OK",
  "data": [
    { "id": 1, "attributes": [] },
    { "id": 2, "attributes": [] }
  ]
}
```

Array externo representa respuestas secuenciales; usarlo para polling u otro endpoint donde cada request consume siguiente estado:

```json
[
  {
    "status": 200,
    "statusText": "OK",
    "data": { "run_id": "fixed-run-id", "status": "PROCESSING" }
  },
  {
    "status": 200,
    "statusText": "OK",
    "data": { "run_id": "fixed-run-id", "status": "FINISHED" }
  }
]
```

No usar array externo para hydration/listados. Un error de este tipo puede hacer que service reciba objeto individual en lugar de lista y falle con error genérico de hydration.

## Query params y body

- Identificar params dinámicos agregados por framework (`scope`, correlation IDs u otros).
- Ignorar solo params que no cambian contenido y no participan en seguridad.
- Si mismo dataset representa múltiples contextos locales, se pueden ignorar params de contexto en filename, pero documentar que response sigue siendo estática.
- No ignorar filters, page, size o IDs si response cambia según esos valores.
- `ignoreParams` no modifica request ni response y no hace matching dinámico.
- POST bodies suelen formar parte del filename; usar `mockFilename` para conocer path final. Filenames largos pueden usar hash automático.
- Si fixture falta, `frontend-mocks` puede intentar upstream y escribir respuesta. En desarrollo controlado, revisar fixture antes para evitar red, tests no deterministas o guardar datos sensibles.

## Migración de fake local

Al migrar cualquier `api/mocks`, `local-mocks` o fake equivalente:

1. Mover tipos públicos a `interfaces/`, `types/` o módulo de contrato, sin depender de archivo mock.
2. Quitar estado global de runs, cancelaciones y catálogos si objetivo es simular upstream por HTTP.
3. Eliminar bypasses locales que evitan clientes REST.
4. Mantener en service/route productivos:
   - schema validation;
   - authentication y authorization;
   - ownership y reglas de negocio;
   - mapeo de response;
   - chunking y límites;
   - compatibilidad;
   - sanitización de errores;
   - polling.
5. Generar fixture por request real del flujo inicial; no inventar filename manual.
6. Usar IDs deterministas para endpoints stateful y arrays secuenciales para polling cuando framework lo soporte.
7. Documentar limitaciones de fixtures estáticos: no simulan persistencia, concurrencia o mutaciones arbitrarias.
8. Actualizar tests que verificaban fake; conservar tests de reglas de negocio y agregar tests HTTP cuando lifecycle sea estable.

## Diagnóstico Postman versus app

1. Confirmar repo y proceso:

```bash
pwd
node -e "const env=require('nordic/env'); console.log({NODE_ENV:env.NODE_ENV,DEVELOPMENT:env.DEVELOPMENT,TEST:env.TEST,PRODUCTION:env.PRODUCTION})"
```

2. Iniciar debug según shell:

```bash
DEBUG=mock:* npm run dev
```

3. Confirmar `Registering new interceptor` para host/path esperado.
4. Comparar logs sanitizados:
   - método;
   - host/path;
   - query no sensible;
   - status;
   - filename generado;
   - response del cliente.
5. Si primer upstream responde `200` y luego app retorna `502`, inspeccionar siguiente request:
   - fixture existe;
   - body serializado coincide;
   - `data` tiene shape esperado;
   - arrays de recursos están dentro de `data`;
   - response secuencial solo aparece donde cliente espera polling.
6. Si no aparece interceptor, corregir bootstrap o cwd.
7. Si response difiere por query/body, crear fixture mediante filename del framework o ajustar `ignoreParams` con justificación.
8. Si browser no permite inspección por auth/certificado, usar logs server-side y no pedir cookies/tokens completos.

## Verificación obligatoria

Adaptar comandos al proyecto. Como mínimo:

```bash
git diff --check
npm run lint
npm run test:unit
npm run build
```

También comprobar:

- no quedan imports o ramas del fake local eliminado;
- cada JSON parsea y contiene `status`, `statusText` y `data`; ninguna fixture contiene propiedad `headers`, ni siquiera vacía, parcial o placeholder;
- fixtures de listados tienen array dentro de `data`;
- fixtures de polling tienen secuencia externa intencional;
- un `GET` y un `POST` interceptados responden usando cliente HTTP real del stack;
- producción no registra interceptores;
- auth, autorización, CSRF y validación siguen activas;
- fixtures no contienen secretos, cookies, authorization headers ni PII real;
- ninguna clave de propiedad, incluida una anidada, empieza en `x-`;
- smoke de desarrollo inicia sin errores y proceso se detiene al terminar.

## Salida esperada

Entregar:

1. causa y alcance;
2. bootstrap y condición de entorno;
3. clientes/paths interceptados descubiertos;
4. fixtures creados sin renombrar paths automáticos;
5. diferencia entre params ignorados y validación real;
6. tests, lint y build ejecutados;
7. limitaciones de fixtures estáticos;
8. estado de seguridad y confirmación de producción no interceptada.
