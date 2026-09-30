---
name: nordic-dev-verify
description: >-
  Verifica en runtime apps Nordic bajo *.adminml.com:8443 con Chrome DevTools MCP:
  preflight de basePath y server, gates Okta/TLS, requests y consola. Usar al
  reproducir, depurar o validar un flujo de UI, un 404/5xx, un stack trace o un
  error de consola, aunque no se pida "validar" ni se nombre la skill.
license: MIT
metadata:
  version: "2.0.0"
  category: "frontend-verification"
  tags: "nordic, runtime, chrome-devtools-mcp, adminml, okta, basepath, debugging, context-optimized-v1.18.2"
  command: "/nordic-dev-verify"
---

# Verificar aplicaciones Nordic en desarrollo

## Objetivo

Confirmar comportamiento observable desde UI, red y consola de una app Nordic levantada en desarrollo. El reporte tiene que permitir distinguir tres cosas: el flujo funciona, el producto falla, o el entorno impide saberlo. Nunca exponer credenciales ni dejar datos de prueba modificados.

## Principio central: sin runtime no hay verificación

Esta skill mide lo que la app hace al ejecutarse. Si el runtime no está disponible, cualquier conclusión sacada de leer código o correr tests sería una suposición presentada como verificación. Por eso, mientras el runtime esté bloqueado:

- clasificar como `BLOCKED`, informar el estado exacto observado y no tratarlo como fallo de producto;
- no pasar a inspección estática, lectura de código ni pruebas como sustituto dentro de esta verificación;
- ofrecer reintentar cuando el usuario levante el server.

Si el usuario después pide explícitamente analizar código o correr tests, eso es otra tarea y se reporta por separado, sin el título "Verificación runtime".

## 1. Resolver destino: host, puerto y basePath

Resolver los tres valores antes de cualquier probe y registrar de dónde salió cada uno (usuario, config o default), porque el reporte y los mensajes de error dependen de ese origen.

### Host

1. Hosts permitidos: `dev.adminml.com` más los subdominios `*.adminml.com` declarados en `/etc/hosts` (ignorar comentarios y duplicados).
2. Rechazar `localhost`, `127.0.0.1`, IPs directas y cualquier otro dominio. Esos hosts saltean el routing, las cookies y el SSO que ve un usuario real, así que un resultado ahí no vale como evidencia. Si el usuario pasa una URL así, pedir la ruta equivalente bajo un host permitido.
3. Elegir el host así: el de la URL del usuario si está permitido; si no, `dev.adminml.com`. Si hay varios alias candidatos y ninguno surge del pedido, preguntar con `AskUserQuestion` en lugar de adivinar.
4. Si ningún host permitido resuelve, finalizar como `BLOCKED` y avisar que falta un alias `adminml.com` válido en `/etc/hosts`.

### Puerto

Usar `8443` salvo que la URL del usuario o la config del proyecto declare otro puerto de forma explícita; en ese caso usarlo y registrar el origen. Scheme `https`, salvo que el proyecto sirva `http` de forma explícita.

### basePath

Las apps de `adminml.com` comparten host y se montan bajo una ruta propia, así que un `basePath` `'/'` o vacío hace que la app responda en una ruta que no es la suya.

1. Buscar `config/default.js` en la raíz del repositorio y leer la clave `basePath` (habitualmente `ragnar.basePath`, a veces en el nivel superior). No ejecutar ni evaluar el archivo: leerlo como texto.
2. Según el valor:
   - **String literal con ruta** (p. ej. `'/tools/user-management'`): usarlo como `basePath` efectivo, con origen `config`.
   - **`'/'` o `''`**: no darlo por inválido todavía. En apps Ragnar es válido cuando los routers declaran el prefijo completo de la app (p. ej. `router.use('/tools/auth/users', ...)`); en ese caso la ruta real sale del prefijo, no del `basePath`. Intentar primero el **descubrimiento del prefijo** (ver abajo). Solo si falla, detenerse y pedir el basePath correcto mostrando este mensaje textual, con su ejemplo:
     ```
     ⚠️  basePath incorrecto en config/default.js

     basePath: '/' no es válido para esta app. Debería contener una ruta específica.

     Ejemplo correcto:
     basePath: '/tools/user-management'

     Pasá el basePath correcto para continuar con la verificación.
     ```
     Esperar la respuesta. Si el usuario no puede o no quiere darlo, finalizar como `BLOCKED` con ese motivo. Al recibirlo, usarlo como `basePath` efectivo con origen `override del usuario`, y advertir que el archivo sigue inválido: el server va a seguir sirviendo en `'/'` hasta que lo corrijan y reinicien.
   - **Valor calculado** (variable de entorno, función, template, import): no intentar resolverlo. Si la URL del usuario trae la ruta, usar esa ruta con origen `URL del usuario`; si no, pedir el basePath efectivo al usuario.
3. Si falta `config/default.js`, registrar una advertencia leve y tomar el basePath de la URL del usuario; si tampoco hay, pedirlo.
4. Esta skill nunca modifica `config/default.js` ni otro archivo del proyecto.

### Descubrimiento del prefijo con basePath `'/'`

Este paso resuelve el destino; no reemplaza la verificación. Primero se descubre el prefijo en runtime, con la sesión activa, porque el browser muestra dónde está montada la app en el server que realmente corre. Leer el código queda como fallback: puede estar en otra rama o tener cambios sin reiniciar, y lo que salga de ahí igual tiene que confirmarse en el browser.

Si el usuario ya informa que las fuentes no comparten un prefijo o que el candidato no se confirmó en el browser, no repetir el descubrimiento: pasar directo al mensaje de basePath incorrecto del paso 2.

1. **No usar el probe HTTP para distinguir rutas antes de autenticar.** En estas apps la autenticación corre antes del routing, así que sin sesión todas las rutas, existan o no, suelen devolver `401`. Ese `401` confirma que la app responde, no que la ruta exista. Un endpoint público como `/ping` con `200` confirma que el server es la app.
2. **Iniciar la sesión.** Correr el preflight y abrir la URL del usuario o la raíz del host con el flujo normal de gates (sección 3). Cualquier ruta sirve: aunque muestre la vista de "no encontrado", la sesión queda activa. El `callbackURL` que Okta conserva en su redirect solo indica a dónde vuelve después del login; no prueba que la app responda en esa ruta.
3. **Armar candidatos desde el browser**, con `evaluate_script` en Chrome DevTools MCP o `browser_evaluate` en Playwright MCP, sin mutar nada:
   - `window.__PRELOADED_STATE__?.baseURL`, cuando la app lo inyecta;
   - los `href` de links del mismo origen (`document.querySelectorAll('a[href]')`);
   - las rutas `/api/...` que la página ya pidió (`performance.getEntriesByType('resource')`); quitarles el `/api` para obtener el prefijo de páginas.

   Tomar como candidato el prefijo común de esas fuentes (p. ej. `/tools/auth`) y, si el usuario pidió una pantalla concreta, la ruta completa (p. ej. `/tools/auth/users/shared`).
4. **Fallback: leer el código como texto**, sin ejecutar nada, solo si la página no expone esas fuentes (p. ej. la raíz no renderiza la app) o si no coinciden en un prefijo:
   - prefijos montados en el router de páginas (habitualmente `app/server/index.js`) y en el de API (habitualmente `api/index.js`), por ejemplo `router.use('/tools/auth/users/shared', ...)`;
   - el `baseURL` del cliente HTTP del front (habitualmente `api/client.js` o `api/client/`), por ejemplo `baseURL: '/api/tools/auth'`; quitarle el prefijo `/api` que agrega Ragnar;
   - rutas absolutas que el código usa para navegar o redirigir, por ejemplo `redirectWithMessage('/tools/auth/users/shared', ...)`.

   Si tampoco así hay un prefijo común, no elegir uno: pasar al mensaje de basePath incorrecto.
5. **Confirmar el candidato** con la sesión activa, venga del browser o del código. Navegar al candidato: queda confirmado si el documento carga con `2xx` y renderiza la app esperada (título o heading propio, no un 404 ni otra app del host). Para comparar varios candidatos sin navegar uno por uno, hacer `fetch` de solo lectura (`GET`) desde la pestaña autenticada, que envía la sesión, y comparar cada candidato contra una **ruta de control inventada** del mismo host (p. ej. `/tools/auth/no-existe`). No decidir por el status: muchas apps muestran su vista de "no encontrado" con `200`, así que la ruta inventada también responde `200`. Decidir por el contenido: el candidato es real si su `<title>` o heading es el de la app y el de la ruta de control no (p. ej. `Kraken Auth Admin` frente a un título vacío). Si ambos renderizan lo mismo, el candidato no queda confirmado.
6. **Registrar el resultado.**
   - Confirmado: usar el candidato como destino con origen `descubierto en runtime` y reportar las fuentes usadas (browser o código). No advertir que `config/default.js` es inválido: `'/'` es correcto para esa app.
   - No confirmado (404, otra app o sin render), o sin prefijo común: mostrar el mensaje de basePath incorrecto y esperar el valor del usuario, como en el paso 2. Aclarar que la skill no modifica `config/default.js`: si el usuario da el valor, se usa como `override del usuario` y el archivo queda como está hasta que lo corrijan y reinicien.
7. **API.** Ragnar monta el router de API bajo `/api`, así que los endpoints quedan en `/api` más el prefijo del router (p. ej. `/api/tools/auth/users/shared`). Usar esa ruta para los probes de API desde la página; un `404` en `/api/<ruta sin prefijo>` indica una ruta mal armada, no un fallo del producto.

## 2. Preflight único del server

Ejecutar los tres probes en orden, con timeout corto, sobre el destino resuelto. Nunca sustituir el host por `localhost` ni IP. Registrar cada resultado con su estado exacto:

| Probe | Comando de referencia | Estados |
| --- | --- | --- |
| Listener local | `lsof -nP -iTCP:<puerto> -sTCP:LISTEN` | `LISTENING` (con proceso), `NOT_LISTENING`, `ERROR` |
| TCP al host | `nc -z -w 5 <host> <puerto>` | `OPEN`, `REFUSED`, `TIMEOUT`, `DNS_ERROR` |
| HTTP de la app | `curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://<host>:<puerto><basePath>` | código HTTP, o `NO_RESPONSE` |

No inferir el estado desde la configuración ni desde lo que muestre el browser: solo cuenta lo que devuelvan los probes.

Interpretar así:

- **`NOT_LISTENING` o `REFUSED`**: server no levantado → gate de runtime (ver abajo).
- **`TIMEOUT`, `DNS_ERROR` o `NO_RESPONSE`**: reportar exactamente ese estado, sin convertirlo en "rechaza conexión"; suele indicar un alias de `/etc/hosts`, una VPN o un proceso colgado. Gate de runtime.
- **`404` bajo el basePath**: la app responde, pero no en esa ruta.
  - Si el origen del basePath es `override del usuario`, explicar que el server sigue montado en `'/'` porque `config/default.js` sigue inválido, y que hay que corregirlo y reiniciar.
  - Si el origen es `config` o `URL del usuario`, no decir que la config es inválida: pedir al usuario que confirme la ruta o el basePath.
  - En ambos casos, gate de runtime.
- **`2xx`, `3xx` (incluida una redirección a Okta), `401` o `403`**: la app responde. Continuar al browser.
- **`5xx`**: la app responde con error. Continuar al browser y registrar el `5xx` como evidencia del flujo, no como bloqueo.

### Gate de runtime

Cuando el runtime queda bloqueado, detener el workflow antes de navegar, sacar snapshots, leer requests o inspeccionar código, e informar el estado observado con este mensaje, reemplazando los valores reales:

`El entorno https://<host>:<puerto><basePath> devolvió <estado del preflight>, así que la verificación runtime queda BLOCKED por ahora. No lo trato como fallo de producto ni sigo con inspección de código o pruebas como sustituto.`

Después, llamar a `AskUserQuestion` con `multiSelect: false`, header `Runtime` y una pregunta equivalente a `Levantá la app/server en <puerto>. ¿Está listo para reintentar el preflight?`, con al menos estas opciones:

- **Listo** — `Levanté la app/server; repetir el preflight completo desde cero.`
- **Todavía no** — `Mantener la verificación BLOCKED y finalizar.`

No reemplazar la llamada por una pregunta abierta ni asumir que el server ya está arriba. Con **Listo**, repetir los tres probes desde cero; la selección por sí sola no prueba nada. Permitir como máximo 2 reintentos: si después del segundo el preflight sigue fallando, o si el usuario elige **Todavía no**, finalizar como `BLOCKED` con el último estado observado.

## 3. Abrir el browser: gates de Okta y TLS

Abrir `https://<host>:<puerto><basePath><ruta afectada>` con Chrome DevTools MCP (`navigate_page`) y detectar si aparece una autenticación corporativa o una advertencia de certificado.

Estas pantallas son pasos interactivos del entorno, no fallos del producto. Mientras estén pendientes:

- dejar el browser abierto y mantener el mismo contexto para conservar la sesión;
- no sacar snapshots, hacer clicks, leer requests ni diagnosticar el flujo;
- no solicitar, ingresar, leer ni reportar credenciales, códigos, cookies o tokens.

**Okta u otro SSO**: pedir al usuario que complete la autenticación y esperar una confirmación explícita (`listo`, `aprobado`). Después verificar que el browser volvió a la ruta original con la sesión activa; si no, `BLOCKED`.

**Advertencia TLS o `Not secure` sobre `https://`**: pedir al usuario que revise host y certificado, y que pulse `Advanced` → `Proceed/Continue ... (unsafe)` solo si reconoce el entorno de desarrollo. No aceptar la excepción por cuenta propia. Después de la confirmación, verificar que la URL sigue en `https://` y que el host coincide exactamente con el destino; si no, `BLOCKED`.

Si `new_page` o `navigate_page` fallan con un error de certificado como `net::ERR_CERT_AUTHORITY_INVALID`, no tratarlo como fallo de la app ni reintentar en otra pestaña: llamar a `list_pages`, porque la pestaña suele quedar abierta en la advertencia o ya redirigida al SSO. Pedir al usuario que resuelva los gates en esa misma pestaña, para no perder la sesión.

Un `401` antes de autenticar, una pantalla de login o la ausencia de requests de la app mientras el gate está pendiente se clasifican como `BLOCKED`, nunca como `FAIL`.

## 4. Ejecutar el flujo

1. Definir antes de interactuar la ruta afectada, el flujo esperado y los requests relevantes.
2. Si el flujo modifica estado, usar un fixture sandbox conocido, registrar su estado inicial y definir cómo restaurarlo. No usar datos productivos ni fixtures compartidos que no puedan restaurarse con seguridad.
3. Capturar la línea base: `take_snapshot` y `list_console_messages`. Los errores que ya estén en consola antes de interactuar son ruido preexistente, y separarlos evita atribuirle al flujo algo que no causó.
4. Ejecutar el flujo desde la UI como lo haría un usuario.
5. Revisar requests XHR/fetch con `list_network_requests`: registrar método, ruta sanitizada y status. No leer headers completos, porque pueden traer cookies, tokens de sesión o valores CSRF. Usar `get_network_request` solo cuando el body sea imprescindible, y mostrarlo sanitizado.
6. Volver a llamar a `list_console_messages` y quedarse con los mensajes nuevos respecto de la línea base; abrir el detalle con `get_console_message` solo para los errores relevantes y correlacionarlos con el paso o request que los disparó.
7. Si ayuda, confirmar el estado final con un probe read-only mediante `evaluate_script`, sin mutar nada.
8. Sacar un snapshot final cuando el resultado visual importe.
9. Restaurar el fixture y verificar la restauración antes de cerrar.

## 5. Clasificar

- `PASS`: el flujo, los requests y la consola se comportan como se esperaba, el estado final coincide y el fixture quedó restaurado.
- `FAIL`: un comportamiento, request o error de consola nuevo contradice lo esperado. Incluir paso reproducible y evidencia sanitizada.
- `BLOCKED`: entorno, preflight, autenticación, TLS, permisos o fixture impiden verificar. Nunca presentar un bloqueo como éxito ni como fallo de producto.

## 6. Reportar

```markdown
## Verificación runtime

- Resultado: PASS | FAIL | BLOCKED
- Destino: https://<host>:<puerto><basePath> (basePath desde: config | override del usuario | URL del usuario | descubierto en runtime)
- Preflight: listener <estado> · TCP <estado> · HTTP <código o estado>
- Ruta: <ruta verificada>
- Flujo: <acciones ejecutadas>
- Requests: <método + ruta sanitizada + status>
- Consola: <errores nuevos durante el flujo o ninguno>
- Ruido preexistente: <errores de la línea base o ninguno>
- Estado: <inicial, final y restauración cuando aplique>
- Evidencia: <snapshots o probes relevantes>
- Bloqueos: <detalle accionable o ninguno>
```

Nunca incluir tokens, cookies, headers de autorización, valores CSRF, PII completa ni bodies sin sanitizar.
