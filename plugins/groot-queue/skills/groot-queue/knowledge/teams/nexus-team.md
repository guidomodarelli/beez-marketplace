# Célula Nexus — Gestión de usuarios shipping & herramientas internas

> Célula del equipo Groot. Ver [`groot-team.md`](./groot-team.md) para contexto completo del equipo.

Responsable de la gestión directa de usuarios y las herramientas de operaciones internas.

## Dominio

- Administración de usuarios (alta, baja, edición)
- Atributos de usuario (warehouse, facility, crossdocking)
- Jerarquía organizacional (líder directo, gestión)
- Badges y credenciales
- Labour Share entre sites

## Productos a cargo

- **Pidgey** — Centraliza y gestiona el envío de notificaciones y alertas a usuarios Groot por distintos canales, como email y la campana de Kraken Plugin, para usuarios LDAP, MELI y GROOT. [Documentación oficial](https://furydocs.io/pidgey-notifications-api).
- **Alfred** — Orquesta procesos integrados mediante tickets: aplica flujos de aprobación configurables y coordina la ejecución de la lógica de negocio en Buddy Applications. [Documentación oficial](https://furydocs.io/alfred-orchestrator-api).
- **Chat Interno** — Comunicación interna entre operarios y líderes
- **Kraken Menu** — Menú lateral genérico de las apps Groot: niveles, subniveles, favoritos, búsqueda, y visibilidad de entradas según permisos del usuario
- **Godric** — Segmenta usuarios del dominio Kraken / Shipping Operations mediante configuraciones con reglas JsonLogic, evaluaciones asíncronas sobre universos de usuarios y acciones sobre quienes cumplen las reglas. [Documentación oficial](https://furydocs.io/godric-api/).

## Miembros

```
NEXUS_TEAM:
  - name: Gonzalo Greco
    email: gonzalojavier.greco@mercadolibre.com
  - name: Damian Zmijanovich
    email: damian.zmijanovich@mercadolibre.com
  - name: Maria Delfina Casarino
    email: mariadelfina.casarino@mercadolibre.com
  - name: Guillermo Ponce
    email: guillermo.ponce@mercadolibre.com
  - name: Paula Minteguiaga
    email: paula.minteguiaga@mercadolibre.com
  - name: Ariel Vila
    email: ariel.vila@mercadolibre.com
  - name: Daniela Mouse
    email: daniela.mouse@mercadolibre.com
```

## Criterio de asignación (R-DER-13)

- Shuffle aleatorio de la lista de emails al momento de asignar.
- Tomar el primero del orden barajado.
- Usar `acli jira workitem assign --key <KEY> --assignee <email> --yes`.
- Dejar nota interna indicando acceso a xtools/Pidgey (ver comentario sugerido en R-DER-13).
