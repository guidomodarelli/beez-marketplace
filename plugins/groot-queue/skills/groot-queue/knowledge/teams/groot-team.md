# Equipo Groot

Groot es el equipo de desarrollo responsable del sistema de gestión de usuarios de shipping en Mercado Libre. Administra usuarios de warehouse/fulfillment, roles, permisos, atributos, jerarquía organizacional, badges, credenciales y Labour Share entre sites.

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

Ver [`nexus-team.md`](./nexus-team.md) para detalle completo: dominio, productos, miembros y criterio de asignación.

## Sistemas del equipo

| Sistema | Responsable | Descripción |
|---------|-------------|-------------|
| Groot | Groot (ambas células) | API core de gestión de usuarios shipping |
| Kraken (auth) | Kraken | Auth/roles/permisos |
| Kraken Menu | Nexus | Menú lateral genérico de apps Groot |
| Pidgey | Nexus | Notificaciones |
| Alfred | Nexus | Operaciones masivas |
| Chat Interno | Nexus | Comunicación interna |
| Godric | Nexus | (pendiente documentar) |
| Autogestión de perfil | Kraken | Autogestión de CAD/atributos vía xtools (`/tools/profile/mercadoenvios`) |

## Plataformas con ownership parcial de Groot

- **xtools** (xtools.adminml.com): Plataforma de herramientas internas de shipping. La plataforma es externa, pero **rutas específicas son productos Groot**:
  - `/tools/pidgey/*` → Nexus (notificaciones)
  - `/tools/alfred` → Nexus (operaciones masivas)
  - `/tools/profile/mercadoenvios` → Kraken (autogestión de perfil)
  - Tickets sobre estas rutas son **internos del equipo**, no escalaciones externas.

## Sistemas externos (sin ownership de Groot)

- **WMS** (wms.adminml.com): Warehouse management system
- **LMS**: Labour Management System
- **Kioske**: Terminal de autoservicio para reps
- **SSFF**: Success Factors

## Referencias

- [Guía Labour Share](https://grid.adminml.com/d/01KWVJRP5DBAN5RD41PDQ518D1/view) — manual de usuario operativo de Labour Share (requiere `/grid-sharing:grid` para leer el contenido)

## Nota importante

Nosotros **somos** el equipo Groot. Nunca referirse al equipo como externo en runbooks, soluciones o guías. Las escalaciones internas son entre células (Kraken ↔ Nexus), no hacia "equipo dev Groot".
