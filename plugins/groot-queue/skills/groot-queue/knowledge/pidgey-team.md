# Célula Pidgey — Chat Interno / Notificaciones Outbound

Célula interna de Groot responsable de xtools/Pidgey (`xtools.adminml.com/tools/pidgey/*`): chat interno y notificaciones outbound. Los tickets de acceso denegado a esta sección se asignan automáticamente via shuffle a un miembro de esta célula (no existe squad en Jira).

## Miembros del equipo

```
PIDGEY_TEAM:
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

- Hacer un **shuffle aleatorio** de la lista de emails al momento de asignar.
- Tomar el primero del orden barajado.
- Usar `acli jira workitem assign --key <KEY> --assignee <email> --yes`.
- Dejar nota interna indicando que se trata de acceso a xtools/Pidgey (ver comentario sugerido en R-DER-13).
