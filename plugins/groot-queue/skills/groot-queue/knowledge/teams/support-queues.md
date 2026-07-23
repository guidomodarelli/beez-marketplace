# Equipos y colas de soporte — Funciones principales

> Fuente de verdad para determinar a qué equipo corresponde un ticket según el dominio del problema reportado.
> Uso: consultar en `/groot-queue classify`, `/groot-queue solve`, `/groot-queue:assign-unassigned` y cualquier subcomando que requiera decidir ownership.

---

## IAM Soporte

Equipo encargado de la **gestión de cuentas LDAP**. Resuelve problemas de:

- MFA (Multi-Factor Authentication)
- Cambio de contraseña
- Cambio de datos personales (nombre, tax id)
- Problemas con la creación de la cuenta LDAP
- Usuarios sin la marca de shipping (flag de envíos)

**Criterio de derivación**: si el ticket involucra identidad, credenciales, datos personales de la cuenta o el flag de shipping a nivel IAM, corresponde a este equipo.

---

## FBM (WMS)

Equipo grande encargado de **todas las apps de gestión en los fulfillment** y en los procesos UTR (Unidad de Trabajo Resolutiva).

**Dominio**: aplicaciones operativas de warehouse management (WMS), gestión de inventario, procesos inbound/outbound en fulfillment centers.

**Criterio de derivación**: si el ticket reporta un problema funcional dentro de una app de WMS (no de permisos de usuario) o de un proceso operativo de fulfillment, corresponde a este equipo.

---

## LMS (Labour Management System)

Equipo encargado de **medir la productividad de un facility**. A nivel de usuarios:

- Miden productividad
- Planifican rendimiento
- Optimizan el rendimiento y la productividad de los trabajadores

**Criterio de derivación**: si el ticket reporta una mala productividad, errores de contabilización de horas, diferencias en métricas de rendimiento, o problemas funcionales de la herramienta LMS (pantalla en blanco, CAD incorrecto mostrado en LMS), corresponde a este equipo.

**Distinción clave con WMS**: un operador puede reportar "problema en WMS" cuando en realidad el síntoma es de productividad/horas/rendimiento → en ese caso corresponde a LMS, no a WMS. Verificar el dominio real del problema, no el sistema que el usuario menciona.

---

## Time & Attendance

Equipo encargado de **controlar la asistencia y los turnos** de una operación. Atiende productos como:

- **HCM** (Head Count Manager para externos)
- Gestión de turnos y asistencia

**Criterio de derivación**: cualquier ticket que referencie problemas en HCM, External Person, gestión de turnos, control de asistencia o scheduling de workforce corresponde a esta cola.

**Señales**:
- Universales (sin variante idiomática): "HCM", "External Person", "Rostering".
- ES: "turnos", "asistencia", "control de asistencia", "gestión de turnos", "planificación de turnos".
- PT: "turnos", "asistência", "controle de ponto", "controle de frequência", "gestão de turnos", "planejamento de turnos".
- EN: "shifts", "attendance", "attendance control", "shift management", "shift planning", "scheduling".

---

## Logistics / FOS

Dos equipos distintos (**Logistics** y **FOS** — Field Operations Support) que comparten el mismo dominio **cross-shipping** de apps de operaciones de:

- Fulfillment
- XD (Cross-Docking)
- SVC (Service Centers)

**Dominio**: apps operativas transversales entre tipos de nodo (fulfillment, XD, SVC). Similar a WMS pero orientado a la capa logística cross-shipping.

**Criterio de derivación**: si el problema es funcional en una app de operaciones logísticas cross-shipping (no de permisos de usuario) y no corresponde al dominio específico de FBM/WMS → derivar a **Helpdesk IA** para que rutee internamente al equipo correcto (Logistics o FOS). Desde Groot no tenemos señales para distinguir entre ambos.

---

## Groot

Equipo de **gestión de usuarios**. Brinda herramientas de configuración de usuarios en las dimensiones:

- Alta de usuarios
- Baja de usuarios
- Modificación (roles, atributos) de usuarios

**Scope limitado**: corregir **inconsistencias en flujos de gestión de usuario** y **errores sistémicos** de la herramienta. **NO** errores de apps que implementan Groot como método de autorización.

**Criterio de validez**: un ticket es válido para Groot solo si reporta un error sistémico (bug, crash, timeout, comportamiento inesperado) en las herramientas de gestión de usuarios. Si el problema es de una app que *usa* Groot para autorizar pero el usuario está correctamente configurado → no corresponde a Groot.

> Ver [`groot-team.md`](./groot-team.md) para detalle de células (Kraken + Nexus), sistemas y ownership.

---

## Guía de desambiguación

| Síntoma reportado | Equipo real probable | Razón |
|-------------------|---------------------|-------|
| "No puedo acceder a WMS" + permisos OK en Groot | FBM (WMS) o Logistics | Problema funcional de WMS, no de permisos |
| "Productividad mal medida" + menciona WMS | LMS | El dominio es productividad, no warehouse |
| "Error en HCM" o "External Person" | Time & Attendance | HCM es su producto |
| "No puedo crear cuenta" + tax id / flag shipping | IAM Soporte | Identidad y credenciales |
| "Rol no se asigna" + error sistémico en la tool | Groot | Bug de la herramienta |
| "Rol no se asigna" + sin error (solo pide que lo hagan) | No corresponde a soporte | Autogestión del gestor de operación |
| "App de fulfillment no carga" + permisos OK | FBM / Logistics / FOS (Helpdesk IA rutea) | App operativa, no de usuarios |
| "Horas de Be a Rep mal contabilizadas en LMS" | LMS | Dominio de productividad/horas |
