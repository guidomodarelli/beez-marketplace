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
| Pidgey | Nexus | [Ver alcance en el catálogo de productos Nexus](./nexus-team.md#productos-a-cargo) |
| Alfred | Nexus | [Ver alcance en el catálogo de productos Nexus](./nexus-team.md#productos-a-cargo) |
| Chat Interno | Nexus | Comunicación interna |
| Godric | Nexus | [Ver alcance en el catálogo de productos Nexus](./nexus-team.md#productos-a-cargo) |
| Autogestión de perfil | Kraken | Autogestión de CAD/atributos vía xtools (`/tools/profile/mercadoenvios`) |

## Plataformas con ownership parcial de Groot

- **xtools** (xtools.adminml.com): Plataforma de herramientas internas de shipping. La plataforma es externa, pero **rutas específicas son productos Groot**:
  - `/tools/pidgey/*` → Nexus; ver [`nexus-team.md#productos-a-cargo`](./nexus-team.md#productos-a-cargo)
  - `/tools/alfred/*` → Nexus; ver [`nexus-team.md#productos-a-cargo`](./nexus-team.md#productos-a-cargo)
  - `/tools/profile/mercadoenvios` → Kraken (autogestión de perfil)
  - Tickets sobre estas rutas son **internos del equipo**, no escalaciones externas.

## Sistemas externos (sin ownership de Groot)

- **WMS** (wms.adminml.com): Warehouse management system
- **LMS**: Labour Management System
- **Kioske**: Terminal de autoservicio para reps
- **SSFF** (SuccessFactors): Plataforma de RRHH corporativa. Fuente de verdad para jerarquía organizacional, gestores y estado de usuarios internos. Groot sincroniza datos desde SSFF — cambios de jerarquía/gestor deben hacerse en SSFF, no en Groot.

## Referencias

- **Guía Labour Share** — manual operativo alojado en Grid Sharing. Su nombre, identificador y URL canónicos se leen desde [`knowledge/config/groot-queue-readiness.json`](../config/groot-queue-readiness.json), sin duplicarlos en esta descripción del equipo.

## Nota importante

Nosotros **somos** el equipo Groot. Nunca referirse al equipo como externo en runbooks, soluciones o guías. Las escalaciones internas son entre células (Kraken ↔ Nexus), no hacia "equipo dev Groot".
