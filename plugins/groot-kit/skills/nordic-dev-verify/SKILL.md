---
name: nordic-dev-verify
description: Verifica flujos runtime de aplicaciones web Nordic en entorno local o de desarrollo mediante browser y Chrome DevTools MCP. Activar de forma proactiva siempre que el usuario proporcione una URL Nordic bajo `dev.adminml.com` o `*.adminml.com`, mencione una acción de UI o reporte un stack trace, error de consola, request XHR/fetch, `404`, `5xx`, `JSON.parse`, fallo de red o comportamiento inesperado al ejecutar la aplicación; también cuando pida ejecutar, reproducir, depurar, probar, validar o confirmar un flujo frontend. Usar aunque no diga explícitamente “validar”, no pida una prueba manual o no mencione esta skill por nombre.
---

# Verificar aplicaciones Nordic en desarrollo

## Objetivo

Validar comportamiento observable desde UI y requests de red sin exponer credenciales ni dejar datos de prueba modificados. Reportar evidencia suficiente para distinguir resultado exitoso, fallo real o bloqueo de entorno.

## Hosts permitidos

Usar exclusivamente `dev.adminml.com` o subdominios `*.adminml.com` declarados en `/etc/hosts`:

1. Descubrir hosts con dominio `adminml.com` en `/etc/hosts`, ignorando comentarios y duplicados; incluir siempre `dev.adminml.com` como host permitido.
2. Seleccionar un host descubierto para listener, health check, navegación, browser y diagnóstico de requests.
3. Rechazar URLs con otros dominios, `localhost`, `127.0.0.1` o IPs directas; solicitar una ruta equivalente bajo host permitido cuando sea necesario.
4. Si no existe ningún host permitido resoluble, clasificar verificación como `BLOCKED` y reportar que falta alias `adminml.com` válido en `/etc/hosts`.

## Preflight obligatorio del servidor local

Antes de cualquier probe remoto, navegación o interacción con browser:

1. Verificar que exista un proceso escuchando en el puerto local `8443`:
   - ejecutar `lsof -nP -iTCP:8443 -sTCP:LISTEN` o un probe equivalente disponible en el entorno;
   - registrar resultado como `LISTENING` con proceso identificado, `CLOSED`/`REFUSED`, `TIMEOUT` o `ERROR`;
   - no inferir que server está levantado únicamente porque una URL fue configurada.
2. Confirmar que server responde en `https://<adminml-host>:8443` usando host permitido seleccionado y timeout corto; usar `http://<adminml-host>:8443` solo si scheme del proyecto lo exige. Un listener sin respuesta de aplicación no cuenta como server levantado. Nunca sustituir `<adminml-host>` por `localhost`, `127.0.0.1` o IP directa.
3. Si no hay proceso escuchando en `8443`, o server no responde:
   - detener workflow completo antes de cualquier otro probe, navegación, snapshot, click, lectura de requests, inspección estática o prueba unitaria;
   - informar estado observado sin clasificarlo como fallo de producto;
   - no continuar con ningún fallback mientras el runtime siga bloqueado;
   - ejecutar inmediatamente `AskUserQuestion` y esperar su respuesta antes de cualquier otra acción.
4. La pregunta interactiva es obligatoria para este bloqueo. Usar `AskUserQuestion` con `multiSelect: false`, header `Runtime`, y una pregunta equivalente a `Levantá la app/server en 8443. ¿Está listo para reintentar el preflight?`. Ofrecer como mínimo estas opciones:
   - **Listo** — `Levanté la app/server en 8443; repetir listener y health check desde cero.`
   - **Todavía no** — `Mantener verificación BLOCKED y finalizar sin inspección estática ni pruebas.`
   No reemplazar la llamada por una pregunta abierta, una instrucción textual ni asumir que el usuario ya levantó el server.
5. Si el usuario elige **Listo**, repetir listener y health check desde cero; no continuar basándose únicamente en esa selección. Si el usuario elige **Todavía no**, o si los checks siguen fallando, finalizar como `BLOCKED` sin abrir browser, ejecutar probes adicionales, inspeccionar código o correr pruebas.
6. Continuar con browser y flujo runtime solo cuando proceso y server estén confirmados como disponibles. La ausencia de runtime nunca habilita inspección estática o pruebas como sustituto dentro de esta skill.

## Preparar verificación

1. Verificar primero disponibilidad TCP del puerto `8443` en `<adminml-host>`, usando únicamente `dev.adminml.com` o un subdominio `*.adminml.com` descubierto en `/etc/hosts`, sin inferirla únicamente desde el browser:
   - ejecutar `nc -z -w 5 <adminml-host> 8443` o un probe TCP equivalente disponible en el entorno;
   - registrar resultado como `OPEN`, `REFUSED/CLOSED`, `TIMEOUT` o `DNS/ERROR`;
   - no afirmar que el servidor rechaza conexión ni clasificar el entorno como bloqueado por conexión sin este probe y su resultado registrado.
2. Confirmar servidor disponible en `https://<adminml-host>:8443`.
3. Abrir la ruta en browser usando `<adminml-host>` y detectar si redirige a Okta u otro proveedor corporativo, o si browser muestra una advertencia de certificado/TLS.
4. Si aparece autenticación Okta:
   - pausar el workflow inmediatamente y dejar browser abierto;
   - informar al usuario que debe completar/aprobar autenticación;
   - esperar confirmación explícita del usuario (por ejemplo, `listo` o `aprobado`) antes de continuar;
   - no solicitar, ingresar, leer ni reportar credenciales, códigos, cookies o tokens;
   - después de confirmación, verificar que browser volvió a ruta original y que sesión quedó activa; si no, clasificar como `BLOCKED`.
5. Si una URL empieza con `https://` pero browser muestra `Not secure`, o aparece un intersticial de certificado:
   - pausar el workflow y dejar browser abierto;
   - informar al usuario que debe revisar el host y el certificado;
   - pedirle que pulse `Advanced` y el enlace equivalente a `Proceed/Continue ... (unsafe)` solo si reconoce y acepta el entorno de desarrollo;
   - esperar confirmación explícita del usuario antes de ejecutar cualquier snapshot, click, probe o lectura de requests;
   - no hacer click en la excepción TLS por cuenta propia ni ocultar la advertencia;
   - después de confirmación, verificar que la URL sigue usando `https://` y que el host coincide exactamente con el destino esperado; si no, clasificar como `BLOCKED`.
6. Identificar ruta afectada, flujo esperado y requests relevantes antes de interactuar.
7. Si flujo modifica estado, elegir fixture sandbox conocido, registrar estado inicial y definir restauración antes de ejecutar acción.
8. No usar datos productivos ni fixtures compartidos cuyo estado no pueda restaurarse con seguridad.

## Protocolo de espera por autenticación y seguridad del browser

La aprobación del usuario es un punto de sincronización obligatorio, no una instrucción implícita para continuar. Tras abrir Okta o una advertencia TLS/`Not secure`, no ejecutar snapshot final, clicks, probes, lectura de requests de la aplicación ni diagnóstico de negocio hasta recibir confirmación explícita. Mantener el mismo browser/contexto para conservar sesión; nunca reiniciar o reemplazarlo durante la espera salvo que el usuario lo solicite.

No clasificar una pantalla de login, un `401` previo a autenticación, una advertencia TLS o la ausencia de requests de aplicación como `FAIL` del producto. Clasificar como `BLOCKED` y pedir al usuario completar/aprobar el paso interactivo; solo investigar el flujo después de confirmar callback exitoso y conexión HTTPS aceptada conscientemente.

## Ejecutar flujo

1. Abrir ruta afectada mediante Chrome DevTools MCP.
2. Capturar snapshot inicial de página.
3. Ejecutar flujo desde UI como lo haría usuario.
4. Inspeccionar requests XHR/fetch con `list_network_requests` y registrar método, ruta sanitizada y status.
5. No leer headers completos: pueden contener cookies, tokens de sesión o valores CSRF.
6. Usar `get_network_request` solo cuando body sea imprescindible para diagnóstico y pueda guardarse o mostrarse sanitizado.
7. Agregar probe read-only adyacente con `evaluate_script` cuando permita confirmar estado final sin mutarlo.
8. Capturar snapshot final cuando resultado visual sea relevante.
9. Restaurar fixture a estado inicial y verificar restauración antes de cerrar.

## Clasificar resultado

- `PASS`: flujo y requests esperados funcionan, estado final coincide con expectativa y fixture quedó restaurado.
- `FAIL`: comportamiento o request contradice resultado esperado. Incluir paso reproducible y evidencia sanitizada.
- `BLOCKED`: entorno, autenticación, servidor, permisos o fixture impiden verificar. No presentar bloqueo como éxito.

### Regla para rechazo de conexión

Usar el mensaje `El entorno https://<adminml-host>:8443 rechaza conexión, por lo que verificación runtime queda bloqueada por ahora; no lo trataré como fallo de producto. La inspección seguirá sobre código y pruebas para aislar regresión reproducible localmente.` solo cuando el probe TCP haya devuelto `REFUSED/CLOSED` y la navegación del browser muestre también rechazo de conexión; reemplazar `<adminml-host>` por host permitido real. Si el puerto está `OPEN`, no usar ese mensaje: continuar diagnóstico de HTTP, TLS, autenticación o aplicación. Para `TIMEOUT` o `DNS/ERROR`, reportar exactamente ese estado y no convertirlo en `REFUSED/CLOSED`.

## Reportar verificación

Usar estructura breve:

```markdown
## Verificación runtime

- Resultado: PASS | FAIL | BLOCKED
- Ruta: <ruta verificada>
- Flujo: <acciones ejecutadas>
- Requests: <método + ruta sanitizada + status>
- Estado: <inicial, final y restauración cuando aplique>
- Evidencia: <snapshots o probes relevantes>
- Ruido preexistente: <errores ajenos observados o ninguno>
- Bloqueos: <detalle accionable o ninguno>
```

Nunca incluir tokens, cookies, headers de autorización, valores CSRF, PII completa ni bodies sin sanitizar.
