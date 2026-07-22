# Equipo Groot

Groot es el equipo de desarrollo responsable del sistema de gestión de usuarios de shipping en Mercado Libre (`shipping-users-mgmt-api`). Administra usuarios de warehouse/fulfillment, roles, permisos, atributos, jerarquía organizacional, badges, credenciales y Labour Share entre sites.

## Células

Groot se compone de dos células:

### Kraken — Auth & Roles

Responsable de autenticación, autorización y gestión de roles (BISO roles). Mantiene el sistema de permisos que consume Groot y otros sistemas de shipping.

**Dominio**:
- Roles y permisos de usuario
- BISO roles (creación, asignación, remoción masiva con threshold 20%)
- Validación de autorización ("NO AUTORIZADO")
- Vinculación learning → rol

### Nexus — Gestión de usuarios shipping & herramientas internas

Responsable de la gestión directa de usuarios y las herramientas de operaciones internas.

**Dominio**:
- Administración de usuarios (alta, baja, edición)
- Atributos de usuario (warehouse, facility, crossdocking)
- Jerarquía organizacional (líder directo, gestión)
- Badges y credenciales
- Labour Share entre sites

**Productos a cargo**:
- **Pidgey** — Notificaciones outbound (`xtools.adminml.com/tools/pidgey/*`)
- **Alfred** — Operaciones masivas: tickets, aprobaciones, procesos bulk, CSV upload (`xtools.adminml.com/tools/alfred/*`)
- **Chat Interno** — Comunicación interna entre operarios y líderes

## Sistemas del equipo

| Sistema | Responsable | Descripción |
|---------|-------------|-------------|
| `shipping-users-mgmt-api` (Groot) | Groot (ambas células) | API core de gestión de usuarios shipping |
| Kraken (auth) | Kraken | Auth/roles/permisos |
| Pidgey | Nexus | Notificaciones |
| Alfred | Nexus | Operaciones masivas |
| Chat Interno | Nexus | Comunicación interna |

## Sistemas externos relacionados

- **WMS** (wms.adminml.com): Warehouse management system
- **LMS**: Labour Management System
- **Kioske**: Terminal de autoservicio para reps
- **xtools**: Herramientas de autogestión de perfil
- **SSFF**: Shipping Fulfillment Frontend

## Nota importante

Nosotros **somos** el equipo Groot. Nunca referirse al equipo como externo en runbooks, soluciones o guías. Las escalaciones internas son entre células (Kraken ↔ Nexus), no hacia "equipo dev Groot".
