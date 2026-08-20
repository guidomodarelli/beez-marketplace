# Clasificación de tickets — referencia compartida

Este archivo concentra el JQL base y la lógica de clasificación que usan los commands `list`, `classify`, `detail`, `solve`, `alerts`, `stats` y `save`.

---

## JQL base

Para listar todos los tickets abiertos (Incidents y Service Requests):

```bash
acli jira workitem search --paginate --jql "project = SSHP AND Squad = Groot AND resolution = Unresolved ORDER BY created DESC"
```

> ⚠️ **Paginación obligatoria para conjuntos completos**: `acli jira workitem search` sin `--paginate` devuelve solo la primera página (~30 resultados). Toda búsqueda que alimente listados completos, clasificación, estadísticas, conteos exhaustivos o mutaciones por lote debe incluir `--paginate`; el orden `created DESC` deja los tickets más viejos fuera del resultado truncado. Consultas por key única o límites intencionales pueden omitirlo solo si documentan que no requieren exhaustividad.

Para listar solo los tickets asignados a un LDAP específico (usado por `assignee=<ldap>`, `assignee=me` y `@me`):

```bash
acli jira workitem search --paginate --jql "project = SSHP AND Squad = Groot AND resolution = Unresolved AND assignee = <ldap> ORDER BY created DESC"
```

Para ver un ticket específico:

```bash
acli jira workitem view SSHP-XXXXXX
```

---

## Triage de veredicto

> Antes de clasificar por categoría/urgencia, aplicar el algoritmo de triage definido en `triage-rules.md`. Ese archivo tiene las reglas `R-DESC-XX` y `R-DER-XX` con el orden de evaluación y los veredictos posibles.

---

## Dimensión 1 — Tipo de Problema

Analizar el summary y description del ticket y asignar UNA de estas categorías:

| Categoría | Descripción | Señales típicas (ES/PT/EN) |
|-----------|-------------|---------------------------|
| **Jerarquía/Líder** | Cambios de líder, gestión, jerarquía | cambio de lider, trocar lider, trocar gestao, hierarquia, jerarquia, lider directo, manager primario, alterar lider, lider incorreto |
| **Warehouse/Site** | Asignación de warehouse, facility, sitio | warehouse, ajustar warehouse, mover reps, mover colaborador, facility, cambiar SVC, trocar site |
| **Roles/Permisos** | Problemas con roles, permisos, autorización | rol, role, permiso, not authorized, no autorizado, boton deshabilitado, asignar rol, nao ve rol |
| **Visibilidad Usuario** | Usuario no aparece en sistemas | no aparece, nao aparece, sem bolhas, no visualizam, nao visualizam, sin visibilidad, tela branca |
| **Atributos** | Modificación de atributos falla | atributo, remover atributo, crossdocking, alteracao nao salva, no guarda el cambio |
| **Labour Share** | Problemas con labour share | labour share, labor share, no impacta |
| **CAD/Perfil** | Problemas de perfil, CAD, autogestión | CAD, autogestao, perfil incorrecto, xtools, cad errado |
| **Error UI Groot** | Errores de interfaz en Groot | erro ao editar, error en groot, se queda cargando, botao sumiu, nao foi possivel realizar, erro no groot |
| **Vincular/Desvincular** | Vincular/desvincular cuenta | vincular, desvincular, conta meli, cuenta meli, trocar senha |
| **Otro** | No encaja en ninguna categoría | — |

Las categorías se mapean 1:1 con los runbooks de `runbooks.md` y con las subcarpetas de `solutions/`:

| Categoría | Carpeta en `solutions/` |
|-----------|-------------------------|
| Jerarquía/Líder | `hierarchy-leader` |
| Warehouse/Site | `warehouse-assignment` |
| Roles/Permisos | `role-permission` |
| Visibilidad Usuario | `user-visibility` |
| Atributos | `attribute-modification` |
| Labour Share | `labor-share` |
| CAD/Perfil | `cad-profile` |
| Error UI Groot | `groot-ui-error` |
| Vincular/Desvincular | `link-unlink-account` |
| Otro | `queue-management` |

---

## Dimensión 2 — Urgencia (1-5)

Calcular un score de urgencia basado en:

| Factor | Peso | Scoring |
|--------|------|---------|
| **Prioridad Jira** | 30% | Highest=5, High=4, Medium=3, Low=2, Lowest=1 |
| **Edad del ticket** | 25% | >72h=5, >48h=4, >24h=3, <24h=2 |
| **Status sin respuesta** | 25% | `WAITING_FOR_SUPPORT` según `jira-field-options.md` >24h sin asignar=5, <24h=3, otros o estado no reconocido=1 |
| **Sin asignar** | 20% | Sin assignee=+1 al score |

Score final: promedio ponderado, redondeado a 1-5.
- Score >= 4 → **Riesgo SLA** (marcar con indicador rojo)

Indicadores visuales de urgencia:
- 1-2: `🟢`
- 3: `🟡`
- 4-5: `🔴`
