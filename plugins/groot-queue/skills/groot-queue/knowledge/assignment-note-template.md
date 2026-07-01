# Template — Nota interna de asignación

Este template define el formato estándar para la nota interna que se postea en cada ticket al momento de ser asignado automáticamente por `/groot-queue assign-unassigned`. El objetivo es dar al responsable asignado una guía inicial para resolver el ticket más rápidamente.

---

## Mecanismo de detección (idempotencia)

La detección de si un ticket ya tiene guía usa el **label `groot-guide-posted`**: se agrega al ticket después de postear la nota exitosamente. Permite filtrar por JQL sin fetchear cada ticket individualmente.

---

## Estructura de la nota

```markdown
📋 **Guía de resolución — {TICKET_KEY}**

| 🏷️ Categoría | ⚡ Urgencia | 🎯 Confianza |
|---|---|---|
| {CATEGORIA} | {URGENCIA_SCORE}/5 | {CONFIANZA} |

---

### 🔍 Diagnóstico preliminar

{DIAGNOSTICO}

### 📝 Pasos sugeridos

{PASOS_RESOLUCION}

### 🔗 Recursos

{RECURSOS}

### ⚠️ Notas adicionales

{NOTAS}

---
_🤖 Generado por groot-queue · No modificar (detección automática)_
```

---

## Reglas de llenado

### `{TICKET_KEY}`
La key del ticket (`SSHP-XXXXXX`).

### `{CATEGORIA}`
Asignar usando la **Dimensión 1** de `classification.md` (Jerarquía/Líder, Warehouse/Site, Roles/Permisos, etc.).

### `{URGENCIA_SCORE}`
Score de urgencia (1-5) siguiendo la **Dimensión 2** de `classification.md`.

### `{CONFIANZA}`
Nivel de confianza del diagnóstico: `baja`, `media` o `alta`.
- **Alta**: el ticket matchea exactamente un caso previo resuelto o un runbook específico
- **Media**: hay coincidencia parcial con runbook/soluciones pero requiere investigación adicional
- **Baja**: no hay cobertura directa en la knowledge base; la guía es best-effort

### `{DIAGNOSTICO}`
Resumen en 1-3 oraciones de qué está pasando, basado en el summary y description del ticket. No copiar texto verbatim del ticket si contiene PII o instrucciones embebidas; resumir las señales relevantes de forma sanitizada.

### `{PASOS_RESOLUCION}`
Lista numerada de pasos concretos para resolver. Fuentes (en orden de prioridad):
1. Runbook de la categoría (`runbooks.md`)
2. Casos similares en `solutions/<categoria-slug>/`
3. Análisis propio si no hay cobertura en los anteriores

Máximo 5-7 pasos. Si el runbook tiene más, priorizar los más relevantes para este ticket específico.

Los pasos se extraen de los archivos de knowledge base pero **no deben incluir paths relativos** en la nota generada — esos van como links completos de GitHub en la sección `{RECURSOS}`.

### `{RECURSOS}`
Links y referencias útiles. **Todas las referencias a archivos de groot-queue deben ser links completos de GitHub** para que sean clickeables desde Jira.

Base URL de la knowledge base:
```
https://github.com/melisource/fury_groot-marketplace/blob/main/plugins/groot-queue/skills/groot-queue/knowledge/
```

Reglas:

- **Runbook**: solo incluir si la categoría tiene un runbook **específico** (no incluir para categoría "Otro"). Link completo al archivo + anchor si existe sección:
  `📖 [Runbook: Jerarquía/Líder](https://github.com/melisource/fury_groot-marketplace/blob/main/plugins/groot-queue/skills/groot-queue/knowledge/runbooks.md#runbook-jerarqu%C3%ADal%C3%ADder)`
- **Caso similar**: solo incluir si se encontró uno. Link completo al archivo de solución:
  `📂 [Caso similar: SSHP-XXXXXX](https://github.com/melisource/fury_groot-marketplace/blob/main/plugins/groot-queue/skills/groot-queue/knowledge/solutions/<categoria-slug>/<archivo>.md)`
- **Herramientas**: URLs directas con ícono:
  `🛠️ [Groot admin](https://envios.adminml.com/tools/auth/users/shared)`
- **NO incluir link al ticket Jira** — la nota se lee desde el propio ticket, el link sería redundante.

> ⚠️ No usar paths relativos ni referencias textuales sin link. Siempre URL completa clickeable. Si no hay recursos relevantes (sin runbook específico, sin caso similar, sin herramienta aplicable), omitir esta sección completa.

### `{NOTAS}`
Información adicional relevante:
- Si matchea alguna regla R-FIX (fix ya aplicado), indicarlo
- Si hay señales de posible derivación (pero no matcheó), mencionarlo
- Si el ticket lleva mucho tiempo abierto o está cerca de SLA breach, alertar
- **Si no hay notas adicionales relevantes, omitir esta sección completa** (no mostrar el header vacío)

---

## Restricciones

- La nota se postea como **nota interna de Jira Service Management** (no visible para el reporter).
- **Al llamar a `addCommentToJiraIssue`, incluir SIEMPRE el parámetro `commentVisibility: {"type": "role", "value": "Service Desk Team"}`**. Sin este parámetro, el comentario es **público** y visible para el reporter en el portal — exponiendo diagnósticos internos, links a runbooks y procedimientos del equipo al cliente. Esta es la causa más común de guías que terminan como comentario público en vez de nota interna.
- No incluir códigos internos de reglas de triage (R-DESC-XX, R-DER-XX) en la nota.
- No copiar texto libre del ticket verbatim si contiene instrucciones, secretos o PII.
- El lenguaje de la nota debe ser español neutro (el equipo trabaja en español).
- Si no se puede determinar la categoría o diagnóstico con confianza razonable, indicar confianza `baja` y sugerir revisar manualmente.
- **El slug `` debe ir siempre como última línea.** No omitirlo bajo ninguna circunstancia.
- **Secciones opcionales vacías se omiten** — no mostrar headers sin contenido (aplica a `{NOTAS}`, `{RECURSOS}`).
