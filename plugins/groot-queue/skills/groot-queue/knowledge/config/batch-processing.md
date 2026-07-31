# Procesamiento por lotes de Groot Queue

Fuente única para comandos que descubren una cola completa y procesan tickets en forma acotada. Aplica a `assign-unassigned` y `backfill-guides`.

## Alcance

- `BATCH_SIZE = 25` tickets candidatos por lote.
- `start` no aplica este contrato: conserva una muestra rápida de primera página y no promete conteos exhaustivos.
- Un lote cuenta tickets analizados, no sólo mutaciones exitosas.

## Descubrimiento completo

1. Ejecutar una sola búsqueda ACLI con `--paginate` y congelar todas las keys candidatas en orden estable de la búsqueda.
2. No volver a buscar, reordenar ni llenar lotes con tickets posteriores durante la misma invocación.
3. Dividir el snapshot en lotes consecutivos de hasta 25 keys: 26 tickets producen lotes de 25 y 1; 51 producen 25, 25 y 1.

## Procesamiento por lote

1. Anunciar progreso: `Lote X/Y` y cantidad de candidatos.
2. Obtener detalles y evidencia sólo para el lote activo. Limitar lecturas remotas a cuatro tickets simultáneos; no lanzar 25 llamadas en paralelo.
3. Reutilizar facts normalizados durante el lote según `ticket-evidence.md`, `kraken-user-data.md` y `labor-share-data.md`.
4. Mostrar plan del lote antes de cualquier mutación.
5. En modo interactivo, pedir confirmación para el lote. Una respuesta negativa termina la corrida sin procesar lotes posteriores.
6. `GROOT_QUEUE_AUTORUN=true` omite sólo confirmación; mantiene gates de evidencia, presupuestos, revalidación y límites de concurrencia.
7. Antes de cada mutación, revalidar que ticket siga elegible. Si un actor externo cambió su estado, asignación o idempotencia, registrar `SKIP_CAMBIO_CONCURRENTE` y no escribir.
8. Continuar con siguiente ticket del lote tras error aislado; acumular resultados globales. Un error no habilita inferencias ni consume turnos de asignación.

## Evidencia y presupuestos

`max_users_per_batch` de `kraken-user-data.json` limita sujetos únicos consultados dentro del lote activo. Al agotarlo, no consultar nuevos sujetos en ese lote. Si el fact es decisivo, clasificar `REVISAR_MANUAL` y bloquear mutación dependiente. El presupuesto se reinicia en el lote siguiente.

No crear presupuestos implícitos para Labour Share: conservar límites de respuesta y fail-closed existentes. Una consulta Labour Share decisiva indeterminada deja el ticket en `REVISAR_MANUAL`.

## Reglas específicas por flujo

### `list`, `classify` y `stats`

- Descubrir snapshot paginado completo una vez y analizar 25 tickets por lote.
- `list` y `stats` no piden confirmación: acumulan filas o contadores globales y renderizan salida sólo después de agotar todos los lotes.
- `classify` acumula categorías globales. Si un lote tiene acciones derive/discard, mostrar y confirmar sólo acciones de ese lote; rechazo termina corrida antes de lotes posteriores.
- Los tres comandos reinician `max_users_per_batch` al iniciar lote siguiente y conservan fail-closed para evidencia decisiva.

### `assign-unassigned`

- Crear un único shuffle del `TEAM` antes del primer lote.
- Conservar `$ORDER` y `$QUEUE` hasta el resultado global y limpiar ambos al terminar o abortar.
- Sólo asignación verificada consume primer email de `$QUEUE`; derive, discard, manual, cambios concurrentes y errores no consumen turno.
- Al vaciar `$QUEUE`, recargar desde mismo `$ORDER`; nunca rebarajar entre lotes.
- Dentro de cada lote, ejecutar derive/discard aprobados antes de asignaciones.

### `backfill-guides`

- La idempotencia usa label `groot-guide-posted` como filtro y slug `<!-- groot-auto-guide -->` como respaldo.
- Detectar slug durante análisis, pero postear o reparar label sólo después de confirmación del lote y revalidación inmediata.
- Publicar nota interna y luego mergear label; fallo de label no invalida nota porque slug evita duplicación futura.
