---
name: andes-tokens-sass-modules
description: Enforce Andes design tokens and constants in SASS Modules for MELI/Nordic projects (colors, typography, spacing, breakpoints, radius, elevation). Trigger whenever adding, reviewing, or fixing .scss/.module.scss styles, hard-coded colors, spacing, typography, responsive breakpoints, radius, elevation, or theme drift.
metadata:
  tags: "context-optimized-v1.18.2"
---

# Andes Tokens in SASS Modules

## Quick start
Use Andes design tokens and constants in every SASS Module for colors, typography, spacing, and breakpoints. Prefer Andes CSS custom properties or mixins over hard-coded values to keep MELI styling aligned with Andes.

## Core workflow
1. Locate the SASS Module and identify any hard-coded colors, spacing, font sizes, or breakpoints.
2. Replace raw values with the closest Andes token already used in the project (CSS variables or mixins).
3. Use the `var(--andes-..., fallback)` pattern for CSS custom properties, keeping the fallback equal to the previous value.
4. Prefer Andes typography tokens or Andes React components for font size, line height, and weight instead of custom values.
5. Use Andes breakpoint variables or mixins already present in the codebase instead of new pixel values.
6. Only add a new raw value if no Andes token exists; align with the user on the exception.

## Guidelines
- **Colors**: Use `var(--andes-color-...)` tokens; avoid raw hex values.
- **Spacing**: Use `var(--andes-spacing-...)` tokens for margin, padding, gap, and layout spacing.
- **Typography**: Use Andes typography mixins/tokens or component props; avoid custom font stacks or sizes.
- **Breakpoints**: Use Andes breakpoint tokens or mixins defined in the project; avoid custom media query values.
- **Radius/Elevation**: Use Andes radius/shadow tokens if available; avoid new hard-coded values.
- **Imports**: Follow local Andes SASS conventions (`$andes-theme` and Andes style imports) and add only what the module needs.

## Patterns

### Colors and spacing with fallback
```scss
.product-card {
  padding: var(--andes-spacing-16, 16px);
  color: var(--andes-color-gray-700, #333);
}
```

### Using existing local fallbacks
```scss
.product-card__meta {
  color: var(--andes-color-gray-550, $color-gray);
}
```

## Quick checklist
- All user-facing colors use Andes color tokens.
- All margins, paddings, and gaps use Andes spacing tokens.
- Typography uses Andes tokens or Andes React components.
- Breakpoints rely on Andes tokens or mixins already in the codebase.
- No new hard-coded values unless explicitly approved.
