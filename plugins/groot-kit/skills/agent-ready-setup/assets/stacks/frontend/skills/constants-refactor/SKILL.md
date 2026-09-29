---
name: constants-refactor
description: Analiza y refactoriza constantes, literales con significado de dominio y contratos cross-layer. Usar al crear, modificar, mover o revisar constantes, limpiar hardcodes, centralizar límites/códigos/rutas/regex, responder comentarios de PR sobre constantes o reducir duplicación entre capas. Ubica cada valor según su significado, no según su cantidad de usos, y preserva comportamiento.
metadata:
  tags: "context-optimized-v1.17.3"
---

# Constants Refactor

## Objetivo

Dar una fuente canónica en `constants/` a cada constante estática con significado de dominio o de contrato, aunque exista un solo consumidor actual: la cantidad de usos no decide la ubicación. Aplicar además las rules del proyecto, que prevalecen sobre esta skill:

- `../../rules/frontend-style.md` › `Module placement`: dentro de un subrouter quedan solo las declaraciones route-local necesarias para montarlo o definir su schema; lo reutilizado o con significado de dominio va a `constants/`.
- `../../rules/security.md` › `Secrets & PII`: secretos, credenciales y tokens nunca se declaran como constantes.
- `../../rules/api-configuration.md`: scopes y valores por entorno viven en `config/`.

No confundir constantes con variables calculadas en runtime, estado mutable o resultados de llamadas, que no deben extraerse como constantes.

Aplicar workflow completo cuando usuario pida implementar. Entregar solo análisis cuando usuario pida review o informe sin cambios.

## Quick start

1. Resolver repositorio, lenguaje/framework, rama base y alcance exacto.
2. Separar `git diff BASE...HEAD` de cambios no commiteados.
3. Inventariar declaraciones `const`, atoms escalares `as const`, objetos/arrays `as const`, enums/union literals, regex, límites, códigos, paths, timeouts y strings repetidos.
4. Comparar inventario con `constants/`, `config/`, `permissions/`, `utils/`, tipos/interfaces, schemas y módulos de dominio existentes.
5. Clasificar cada candidato: `mover a constants/`, `mantener como variable runtime` o `no tocar`.
6. Implementar fuentes canónicas, migrar consumers y tests.
7. Ejecutar validaciones y reportar bloqueos reales sin ocultarlos.

## Organización física por dominio

Cuando `constants/` contenga varios módulos relacionados, agruparlos por dominio funcional y boundary, no solo por tipo primitivo o por orden de creación:

```text
constants/
├── <domain-a>/
│   ├── index.ts
│   ├── <domain-a>.ts
│   └── <domain-a>-errors.ts
├── <domain-b>/
│   └── index.ts
└── <shared-concern>.ts
```

Aplicar estas reglas:

- Mover juntas las constantes que representan el mismo dominio o contrato —por ejemplo códigos, rutas, límites, estados y tipos de un flujo— y mantener separadas las preocupaciones transversales realmente reutilizadas.
- Usar `index.ts` como entrypoint del dominio cuando haya varios módulos. Reexportar desde allí sin redeclarar valores, objetos `as const`, enums o tipos; una sola definición evita divergencias.
- Evitar colisiones entre un archivo y una carpeta con el mismo basename (`constants/<domain>.ts` y `constants/<domain>/`). Si se conserva el specifier público, mover la implementación al directorio y usar `index.ts` como fachada.
- Conservar shims legacy como archivos que solo reexportan la ubicación canónica cuando el path profundo no colisiona con una carpeta nueva. Mantener imports públicos existentes cuando la resolución siga siendo válida y migrarlos por boundary cuando no lo sea.
- Representar rutas relacionadas como un objeto `...ROUTES` con propiedades semánticas y `as const`; evitar constantes escalares sueltas para fragments del mismo boundary. Derivar rutas compuestas desde ese objeto y preservar separación entre mount paths y BFF paths.
- Preservar el alias soportado por runtime y evitar cambiar imports masivamente solo por uniformidad. Verificar TypeScript, Jest, bundler y server por separado cuando sus resolvers difieran.
- No colocar en `constants/` expresiones cuyo valor se obtiene o cambia durante runtime; esas expresiones son variables runtime, no constantes estáticas.
- Revisar el boundary de cada constante: no exportar al cliente valores server-only, detalles internos de upstream o metadata sensible. Las constantes compartidas deben ser seguras para el bundle donde se consumen.
- Mantener constantes puras y sin side effects. Evitar que los barrels importen servicios u otros módulos que introduzcan ciclos; los módulos de dominio pueden depender de constantes compartidas, no al revés.
- Tras mover constantes, validar valores, referencias, tipos, identidad de objetos cuando importe y resolución de barrels/shims mediante tests de comportamiento o typecheck; no testear strings del archivo fuente.

## Pedidos explícitos de reubicación

Cuando usuario pida mover constantes de módulo o feature hacia `constants/`:

1. Buscar primero archivo de dominio existente, por ejemplo `constants/<domain>/<feature>.ts`; no crear `constants.ts` genérico.
2. Mover a `constants/` toda constante estática con significado de dominio o contrato: límites, estados, regex, rutas, códigos, configuración fija, estilos, paginación, delays y mapas, aunque se usen una sola vez. Un único consumidor nunca es motivo para mantenerla local.
3. Mantener fuera de `constants/` las variables calculadas en runtime, el estado mutable, los resultados de llamadas y los valores listados en «Mantener fuera de `constants/`» y «Separar destinos».
4. Separar tipos runtime de UI: constants no deben importar valores desde `app/`, componentes o tipos que dependan de constants.
5. Mantener specifiers públicos existentes solo cuando el barrel los soporte; no introducir un alias nuevo por uniformidad.

### Barrels y contratos públicos

Antes de migrar consumers, recorrer destino y todos sus barrels ascendentes. Si un barrel usa lista explícita de exports, agregar el nuevo símbolo allí; `export *` en barrel interno no implica exposición desde entrypoint raíz. Ejecutar typecheck después de actualizar barrels y antes de cerrar refactor.

### Atoms escalares y agregados

- Cuando un literal tenga significado de dominio unitario y estable, definirlo una sola vez como atom escalar en `constants/`, aunque hoy tenga un solo consumidor: `const SEMANTIC_ATOM = 'value' as const`.
- Construir arrays y agregados contractuales desde atoms: `const CONTRACT_VALUES = [SEMANTIC_ATOM, OTHER_ATOM] as const`.
- Nombrar atoms por rol semántico y dominio (`LABOUR_SHARE_SOURCE_SCANNER`), no por valor genérico (`VALUE`, `ITEM`, `TYPE`).
- Derivar unions desde el array contractual correspondiente, no desde un array de otro dominio. Mantener arrays distintos cuando tengan semánticas distintas aunque compartan atoms (`mixed` no pertenece a una lista de valores individuales).
- Compartir atom después de comprobar equivalencia de significado, boundary, serialización y consumers. La coincidencia textual aislada no justifica reutilizar un atom existente, pero tampoco justifica mantenerlo en el consumidor.
- Mantener atoms puros, sin servicios, permisos, imports server-only ni side effects; los valores estáticos se declaran en `constants/` y no se calculan al importar.
- Preservar orden, identidad y forma observable. No reemplazar referencias canónicas por `Array.from`, spread, `Object.freeze` o composición dinámica cuando eso cambie identidad, mutabilidad o serialización requerida por consumers.
- No atomizar variables calculadas, estado mutable, resultados de llamadas ni datos derivados de input. Mover declaraciones constantes estáticas completas —incluidos fixtures y mapas contractuales— aunque tengan un solo consumidor; no fragmentarlas solo por estética.
- Un refactor de constants debe limitarse a extracción, composición y migración de referencias; no agregar condicionales, guards, normalización ni cambios de validación salvo pedido explícito separado.
- Priorizar composición simple y legible. Mantener regex literales cuando derivarlas dinámicamente agregue helpers, escapes o complejidad sin reducir un drift comprobado; en ese caso cubrir sincronización con tests.
- Si patrón canónico ya existe como variable (por ejemplo, string compartido entre schemas legacy), reutilizarlo mediante `new RegExp(CANONICAL_PATTERN)` cuando consumidor requiera `RegExp`; no duplicar equivalente literal solo para evitar una advertencia de lint.
- Cuando `security/detect-non-literal-regexp` marque una conversión segura desde constante canónica, usar suppress puntual y documentado en inglés, limitado a esa línea o bloque; no eliminar fuente única ni silenciar regla para archivo completo sin motivo.

## Alcance y exclusiones

- Interpretar `@constants/` como carpeta `constants/` salvo que repositorio ya defina otro alias explícito.
- Preferir aliases e imports existentes; no crear alias nuevo solo para este refactor.
- Respetar exclusiones explícitas del usuario por dominio, módulo, ruta o PR.
- Si usuario excluye un dominio, no modificar servicios, rutas, permisos, guards ni tests de ese dominio, aunque compartan strings con otro flujo.
- No editar manualmente catálogos generados de traducciones salvo pedido explícito y workflow del repositorio.
- No hacer commit, push, comentarios de PR ni cambios externos sin autorización explícita.

## Inventario

### Fuentes que revisar

Adaptar al layout del repositorio:

- `constants/`, `config/`, `settings/`
- `interfaces/`, `types/` y exports runtime dentro de módulos de tipos
- API, backend, frontend, servicios, adapters, middlewares y utilidades
- schemas y validadores
- hooks, loaders, SSR y clientes backend-for-frontend cuando existan
- tests y mocks
- comentarios inline y reviews del PR, cuando exista PR

### Búsquedas mínimas

Adaptar comandos al shell y lenguaje:

```bash
rg -n "export const|const [A-Z][A-Z0-9_]+|as const|enum " .
rg -n "['\"](status|reason|error|code|path|timeout|limit)" src api app lib utils tests
rg -n "timeout|max\(|min\(|regex\(|enumeration\(|allowlist|whitelist" src api app lib utils
rg -n "from ['\"].*/(interfaces|types|constants)/" src api app lib utils tests
```

Para PR:

- determinar base y HEAD desde GitHub/git;
- leer comentarios inline, threads y estado `resolved/outdated`;
- separar comentarios abiertos aplicables de comentarios ya resueltos u obsoletos;
- no tratar boilerplate de bots como hallazgo.

## Clasificación

### Mover a `constants/`

Mover toda declaración estática con significado de dominio o contrato, sin exigir reutilización previa:

- constantes de contrato, aunque tengan un solo consumidor;
- límites, estados, códigos, rutas, regex, allowlists, atributos y claves públicas;
- configuración fija que no varía por entorno y metadata no sensible;
- runtime constants ubicadas dentro de `interfaces/` o `types/`;
- literales unitarios y elementos de arrays contractuales, aunque hoy no estén repetidos;
- estilos, statuses HTTP, timeouts, paginación, delays y mapas estáticos.

La decisión de mover depende del significado del valor, no de la cantidad de referencias. Crear o ampliar el archivo de dominio correspondiente aunque el valor aparezca una sola vez.

### Mantener fuera de `constants/`

Dejar fuera:

- variables calculadas en runtime, estado mutable, resultados de llamadas, respuestas, datos derivados de input y expresiones cuyo valor cambie durante la ejecución, porque no son constantes;
- literales triviales sin significado propio (`0`, `1`, `-1`, `true`, `false`, string vacío de inicialización);
- declaraciones route-local necesarias para montar un subrouter o definir su schema (`frontend-style.md` › `Module placement`); los límites y valores de dominio que ese schema usa sí van a `constants/`.

Si un valor con significado de dominio puede declararse y permanecer fijo durante la ejecución, tratarlo como constante y moverlo a `constants/`.

### Separar destinos

- secretos, credenciales y tokens → `node-melitk-secrets`; nunca `constants/` ni código fuente;
- autorización → módulo `permissions/`, `auth/` o equivalente del dominio, no `constants` genérico;
- valores por entorno/deployment, base URLs y scopes → `config/` vía `nordic/config`, no `constants`;
- rutas backend-for-frontend compartidas → `constants/routes.ts` o equivalente;
- paths upstream privados → cliente/adapter;
- copy, labels y msgids user-facing → catálogo i18n del proyecto, no `constants/`;
- estados internos de un parser sin significado de dominio → módulo del parser; si una regex o estado forma parte de un contrato, va a `constants/`.

## Diseño seguro

### Preservar semántica de validación

Centralizar fuente de patrón no debe cambiar mecanismo de validación sin necesidad.

Preferir:

```ts
export const FACILITY_KIND_PATTERN = /^(warehouse|xd|sc)$/;

string().secure().regex(FACILITY_KIND_PATTERN)
```

No reemplazar automáticamente por un validador distinto: puede cambiar sanitización, coerción, clasificación (`format` vs `enum`) y forma de errores observables.

Para límites compartidos, usar misma constante en schema y validación manual. Mantener separados límites con objetivos distintos, por ejemplo lookup frente a payload malformed para logging.

Al componer arrays desde atoms, preservar orden, referencia e identidad cuando forman parte del contrato. `Array.from`, spread, `Object.freeze` y regex dinámicas requieren validación explícita porque pueden cambiar identidad, mutabilidad, flags o serialización.

### Seguridad y autorización

- Mantener validación basada en schemas en cada boundary usando el validador aprobado por el proyecto.
- Mantener allowlists; no reemplazar allowlist por valores derivados de input no confiable.
- No incluir tokens, cookies, headers, secrets, payloads sensibles ni PII en logs.
- No mover permisos a `constants` si existe estructura específica de autorización.
- No tocar autorización al hacer un refactor de valores salvo pedido explícito.
- No cambiar métodos HTTP, CSRF, auth ni authz como efecto colateral de mover rutas.
- No introducir dependencias nuevas para resolver duplicación si utilidades existentes alcanzan.

### Ciclos y tipos

- Usar objetos `as const` y unions derivados.
- No usar `enum` (`frontend-style.md` › `TypeScript`).
- Mantener imports type-only desde `interfaces/` o `types/` cuando corresponda.
- Evitar que `constants/` importe valores desde módulos de tipos si esos módulos deben depender de `constants/`.
- Preferir dirección unidireccional: `atoms/constants → tipos/consumers` o imports type-only sin ciclo runtime.
- Derivar tipos desde atoms/agregados del mismo dominio; no importar valores runtime desde `interfaces/` o `types/` hacia `constants/`.
- Verificar reglas de ciclo, resolución de imports y aliases configurados por el repositorio.

### Naming y comentarios

- Nombrar en `UPPER_SNAKE_CASE` por rol, con unidades en el nombre (`REQUEST_TIMEOUT_MS`), según `frontend-style.md` › `Naming`.
- Comentar solo el porqué no obvio (origen de un límite upstream, formato esperado), según `frontend-style.md` › `Comments`: sin bloques multilínea ni docstrings.

## Implementación

1. Crear o ampliar archivo de dominio cohesivo en `constants/`.
2. Identificar los valores estáticos con significado de dominio y definirlos allí; crear atoms antes de arrays/agregados contractuales cuando corresponda, aunque cada atom tenga un solo consumidor.
3. Construir arrays/agregados y tipos derivados desde atoms, conservando contratos separados.
4. Mantener nombre semántico; no usar nombres genéricos como `VALUE`, `LIMIT`, `DATA`.
5. Mover valores sin cambiar strings, orden, default, serialización o respuesta.
6. Actualizar barrels, imports de producción, tests y fixtures constantes.
7. Revisar diff por dominio excluido antes de continuar.
8. No mezclar refactor de constantes con cambios funcionales no solicitados.

## Verificación

Ejecutar comandos definidos por repo. Como base genérica:

```bash
git diff --check
```

Luego detectar y ejecutar comandos disponibles para lint, typecheck, tests y build. Para TypeScript, normalmente:

```bash
npx tsc --noEmit
```

Para feedback rápido, ejecutar primero suites focales de schemas, rutas, servicios, parser y componentes afectados. Luego ejecutar suite completa. En refactors con atoms, comprobar además valores, orden, identidad de arrays/tuplas, serialización y rechazo de valores inválidos.

También comprobar:

```bash
rg -n "@constants" .
rg -n "from ['\"].*/(interfaces|types).*(ERROR_CODES|STATUS|FACILITY|REASON)" src api app lib utils
```

No marcar tarea como completa si tests, lint o build fallan. Si falla por cambio preexistente, aislarlo, documentar archivo/línea y no modificarlo sin autorización.

## Formato de salida

Usar este formato salvo que usuario pida otro:

```markdown
## Alcance
- Base, HEAD, archivos y cambios locales excluidos.

## Candidatos movidos
| Archivo/línea | Valor | Destino | Motivo |

## Valores fuera de `constants/`
| Archivo/línea | Valor | Motivo (no es constante, trivial, route-local, secreto, config o i18n) |

## Cambios aplicados
- Fuentes canónicas.
- Consumers y tests.
- Exclusiones respetadas.

## Validación
| Comando | Resultado |

## Riesgos o bloqueos
- Fallos reales, preexistentes o no ejecutados.
```

Ser explícito cuando cambio es solo estructural y cuando una sustitución puede modificar comportamiento observable. No decir “todo funciona” si suite completa no pasó.
