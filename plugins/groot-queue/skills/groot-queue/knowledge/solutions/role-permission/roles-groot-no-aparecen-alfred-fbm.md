---
ticket: SSHP-1412053
category: role-permission
summary: Roles configurados en Groot no aparecían disponibles en Alfred (template FBM). Se agregaron los roles faltantes, incluyendo FBM_DISPOSAL_PICKING_FORKLIFT_OPERATOR.
date: 2026-04-15
effectiveness: confirmed
verdict: VALIDO_GROOT
---

## Problema
Los operadores reportaron que ciertos roles configurados en Groot no aparecían disponibles al utilizar la herramienta Alfred con el template de FBM (Fulfillment By Mercado Libre). Específicamente, algunos roles necesarios para operaciones FBM no estaban listados en el template de modificación masiva.

## Causa Raiz
Los roles correspondientes a operaciones FBM no habían sido incluidos en el catálogo de roles disponibles para el template FBM de Alfred. Entre los roles faltantes se identificó FBM_DISPOSAL_PICKING_FORKLIFT_OPERATOR y otros roles del dominio FBM.

## Solucion Aplicada
Se agregaron los roles faltantes al template FBM de Alfred, incluyendo FBM_DISPOSAL_PICKING_FORKLIFT_OPERATOR. Tras la actualización, los roles quedaron disponibles para ser utilizados en modificaciones masivas mediante Alfred.

## API Calls Involucrados
- Alfred: `xtools.adminml.com` (herramienta de modificaciones masivas via templates)

## Tags
alfred, fbm, roles, template, fbm-disposal-picking-forklift-operator, modificacion-masiva, xtools
