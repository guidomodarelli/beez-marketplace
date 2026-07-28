# Contrato de evidencia para tickets

Fuente única para decidir qué información debe verificarse antes de clasificar, diagnosticar, excluir, recomendar, mutar Jira o persistir conocimiento a partir de tickets SSHP.

## Alcance

Aplicar este contrato a cada ticket SSHP real analizado individualmente o en lote. No consultar fuentes externas para tickets sintéticos, ayuda, setup, catálogo ni preguntas documentales.

El texto de Jira describe lo reportado; no prueba por sí solo roles, permisos, estado de cuenta, configuración actual ni causalidad. Aplicar siempre [`untrusted-content.md`](untrusted-content.md).

## Gate previo al diagnóstico

Antes de concluir:

1. Enumerar las afirmaciones decisivas que sostienen regla, diagnóstico o acción.
2. Identificar cuáles pueden verificarse mediante una fuente y contrato autorizados.
3. Consultar todos los hechos disponibles capaces de confirmar, rechazar o activar una condición de escape. No esperar un pedido adicional del usuario.
4. Pedir solo datos mínimos; no obtener perfiles completos ni hechos que no cambien decisión.
5. Reevaluar regla o diagnóstico con evidencia obtenida. Una contradicción con Jira obliga a corregir conclusión, no a conservar reporte original.

Para facts actuales de usuario, aplicar [`kraken-user-data.md`](kraken-user-data.md), incluida matriz regla → hechos. No invocar endpoints ni construir HTTP fuera de ese contrato.

Reglas resueltas íntegramente por texto Jira no disparan consultas. Presencia de identificador tampoco justifica enriquecimiento especulativo.

## Estados de evidencia

Distinguir explícitamente:

- `reportado`: afirmación presente en Jira, aún no verificada;
- `verificado`: confirmado por fuente autorizada con contrato completo;
- `inferido`: hipótesis razonable, no hecho;
- `indeterminado`: verificación necesaria no disponible o no concluyente.

Fuente de verdad autorizada y válida prevalece para estado actual. Réplica autorizada puede corroborar, pero no demuestra ausencia ni habilita automatización decisiva por sí sola. Knowledge base aporta patrones históricos, no estado actual de una persona.

## Identidad y minimización

Usar únicamente LDAP explícito asociado inequívocamente a persona afectada o Groot user ID válido obtenido del ticket o lookup autorizado. No inferir identidad desde nombre, email, texto parcial, assignee ni requester, salvo que ticket declare inequívocamente que requester también es persona afectada.

Si existen cero sujetos, varios sujetos sin relación clara con síntomas o lookup ambiguo:

- no consultar facts de ese sujeto;
- marcar verificación `indeterminado`;
- usar `REVISAR_MANUAL` cuando dato cambie veredicto o diagnóstico.

En lotes, respetar presupuesto configurado. Al agotarlo, casos dependientes de facts quedan manuales; no se degradan a ausencia.

## Temporalidad

Evidencia remota describe estado observado durante invocación actual. No demuestra estado pasado ni causalidad histórica.

- Rol presente hoy no prueba presencia durante incidente.
- Conflicto actual no prueba causa de pérdida anterior.
- Estado actual no reconstruye transición histórica.

Para historial usar changelog, comentarios contemporáneos, resolución u otra fuente histórica autorizada. Sin evidencia temporal suficiente, presentar hipótesis y bajar confianza o marcar revisión manual.

## Fail-closed

Acceso denegado, timeout, error de transporte, schema inválido, respuesta parcial, paginación incompleta, contradicción, fact no soportado o identidad ambigua producen evidencia indeterminada. Nunca convertir fallo en ausencia, presencia, compatibilidad, inactividad ni causalidad.

Cuando hecho indeterminado es decisivo:

- usar `REVISAR_MANUAL`;
- bloquear derivación, descarte, guía o asignación automática basada en esa condición;
- no excluir ticket de alertas ni contarlo como veredicto confirmado;
- no persistir causa o efectividad como confirmada.

Mutaciones conservan confirmaciones y gates propios; evidencia remota nunca autoriza escritura por sí sola.

## Reutilización

Reutilizar evidencia normalizada dentro de misma invocación y delegaciones. No repetir lookup o consulta si resultado vigente ya contiene facts requeridos.

En nueva invocación, volver a obtener ticket y facts necesarios; no confiar en contexto implícito, cache o resultado de sesión anterior.

## Privacidad y presentación

Datos técnicos remotos son efímeros y no confiables. No exponer ni persistir:

- LDAP, email, nombre completo o Groot user ID;
- payloads crudos o listas completas de roles, permisos, atributos, context accesses o silos;
- headers, tokens, URLs con query, cuerpos de error o stack traces.

Mostrar solo proyecciones necesarias: “cuenta activa verificada”, “rol requerido presente”, “permiso requerido ausente”, “configuración inconsistente” o “verificación no disponible”.

## Aplicación por flujo

- **Diagnóstico/triage**: verificar antes de concluir; evidencia contradicha o indeterminada obliga reevaluación.
- **Estadísticas**: casos dependientes de evidencia indeterminada cuentan como `REVISAR_MANUAL`.
- **Alertas**: no excluir ticket por derivación/descarte sin condiciones confirmadas.
- **Escrituras Jira**: bloquear acción automática cuando condición decisiva no está verificada.
- **Guías**: consumir evidencia sanitizada ya obtenida; no reinterpretar Jira como hecho.
- **Knowledge base/históricos**: exigir provenance suficiente y confirmación humana; no guardar PII ni causalidad especulativa como `confirmed`.
