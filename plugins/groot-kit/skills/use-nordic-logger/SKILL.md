---
name: use-nordic-logger
description: Reemplaza console.* por Logger y migra logging legacy desde LoggerFactory, frontend-logger o métodos verbose y silly hacia clase Logger. Usar siempre que aparezca console.log/warn/error, PII o tokens en logs, diagnóstico upstream, request/correlation IDs, ErrorUX/Failure Studio o cualquier error de aplicación Nordic/MELI, aunque el usuario solo pida 'agregar un log'.
metadata:
  tags: "context-optimized-v1.19.0"
---

# Usar Logger de Nordic o MELI

## Objetivo

Modernizar logging sin mezclar entry points ni introducir APIs incompatibles. Conservar mensajes accionables, contexto estructurado seguro y niveles semánticos.

## Elegir entry point

Inspeccionar `package.json` y versión resuelta antes de editar imports o dependencias.

| Tipo de proyecto | Requisito | Import recomendado | Dependencias |
|---|---|---|---|
| Aplicación Nordic | Nordic `v9.8.0+` | `import { Logger } from 'nordic/logger';` | Mantener entry point Nordic. No agregar `@meli/logger` directamente. |
| Librería o aplicación no Nordic | Sin dependencia de Nordic para logging | `import { Logger } from '@meli/logger';` | Reemplazar `frontend-logger` por `@meli/logger` y actualizar lockfile. |

Si aplicación usa Nordic anterior a `v9.8.0`, no generar código incompatible. Informar bloqueo y proponer actualización de Nordic antes de migrar a clase `Logger`.

## Reemplazar console.*

Tratar cualquier `console.*` en código de aplicación como candidato de migración, aunque no exista `LoggerFactory` ni `frontend-logger`.

1. Crear instancia `Logger` desde entry point definido por tipo de proyecto.
2. Elegir nivel por semántica, no mediante reemplazo textual ciego:
   - `console.log` y `console.info` → `logger.info` para flujo esperado.
   - `console.debug` → `logger.debug` para diagnóstico.
   - `console.warn` → `logger.warn` para condición degradada o inesperada.
   - `console.error` → `logger.error` para operación fallida.
   - `console.trace` → `logger.trace` para detalle diagnóstico; no asumir preservación automática de stack trace.
3. Convertir argumentos sueltos en mensaje accionable y objeto de contexto estructurado seguro.
4. Mantener `console.*` de tooling explícitamente exento, por ejemplo con `eslint-disable no-console`, salvo pedido de migración.

## Migrar API

1. Buscar imports default y named de `LoggerFactory` desde `nordic/logger` o `frontend-logger`.
2. Cambiar import por named import `Logger` desde entry point correspondiente.
3. Cambiar `LoggerFactory(name)` por `new Logger(name)`.
4. Reemplazar `logger.verbose(...)` y `logger.silly(...)` por `logger.trace(...)`.
5. Conservar `info`, `warn`, `error` y `debug`; APIs mantienen comportamiento.
6. Usar nuevos niveles con intención:
   - `trace`: diagnóstico detallado, incluido reemplazo de `verbose` y `silly`.
   - `fatal`: fallo irrecuperable que impide continuar. No convertir errores recuperables en `fatal`.
7. Reemplazar `console.*` por nivel equivalente cuando código de aplicación requiera logging. Mantener usos de tooling explícitamente exentos, salvo pedido de migración.

## Diseñar logs

- Crear instancia estable por módulo, salvo patrón local distinto.
- Escribir mensaje con operación y resultado, por ejemplo `products:getProducts failed`.
- Adjuntar contexto mínimo útil: IDs estables, método HTTP, route template, status code, request ID, filtros seguros.
- No registrar tokens, cookies, authorization headers, secretos, payloads completos, PII completa ni URLs con query sensible.
- Preferir campos sanitizados y acotados sobre objetos `request`, `response` o `error` completos.
- Registrar fallo antes de responder desde API o SSR, sin exponer detalle técnico a usuario.

## Validar migración

- Confirmar ausencia de imports y llamadas legacy dentro de scope migrado: `LoggerFactory`, `frontend-logger`, `.verbose(` y `.silly(`.
- Confirmar entry point según tipo de proyecto y Nordic `v9.8.0+` cuando corresponda.
- Ejecutar tests, lint y typecheck relevantes.
- Verificar en runtime que logs sigan emitiéndose con nivel, mensaje y contexto esperados.
- Revisar diff de `package.json` y lockfile para librerías o aplicaciones no Nordic.

## Ejemplos

Consultar [nordic-logger-examples.md](references/nordic-logger-examples.md) para migraciones Nordic, librerías y logging estructurado seguro.
