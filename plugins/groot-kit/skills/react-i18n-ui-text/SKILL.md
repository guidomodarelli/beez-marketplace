---
name: react-i18n-ui-text
description: Enforces i18n.gettext for all user-facing strings in React (JSX literals, modal titles, buttons, placeholders, helper/error text, toast messages, labels, aria/sr labels) to satisfy @meli-lint/react/i18n-jsx-no-literals. Use proactively whenever changing UI copy, error messages, validation feedback, modal text, retry labels or accessibility labels in MELI/Nordic React, even when the user does not mention i18n. Add useI18n from nordic/i18n and manage gettext catalogs by reusing existing msgids and adding en, es-AR, and pt-BR only when required.
---

# React i18n JSX No Literals

## Quick start
Apply `i18n.gettext(...)` to every user-facing string and add `useI18n` when missing, following Nordic i18n conventions and the lint rule `@meli-lint/react/i18n-jsx-no-literals`. Before adding a new key, check `i18n/*/messages.po` and prefer reusing or updating existing catalog entries.

Treat `i18n/` as the source of truth. In Nordic projects, edit translation catalogs only under `i18n/`; do not manually edit `translations/`, because it is generated from the files in `i18n/`.

## Core workflow
1. Locate JSX literals and user-facing strings in props (title, placeholder, label, helper, error, tooltip, aria, etc.).
2. Import `useI18n` from `nordic/i18n` unless the file already uses a different i18n module (keep existing convention).
3. Add `const { i18n } = useI18n();` (or equivalent) in the component.
4. Wrap literals and user-facing strings with `i18n.gettext(...)`.
5. Before creating a new gettext key, search `i18n/*/messages.po` for an equivalent `msgid`.
6. If only the displayed wording changes, keep the same `msgid` and update `msgstr` in each locale file.
7. If the text is semantically new, add a new `msgid` and provide `msgstr` values for `en`, `es-AR`, and `pt-BR`.
8. Always use neutral Spanish for new user-facing copy and new `msgid` text.
9. For interpolations, use placeholders: `i18n.gettext('Texto {0}', value)`.
10. Avoid translating user-generated content or IDs unless they are user-facing literal labels.
11. Keep existing non-user-facing literals untouched (CSS classes, test ids, enum keys, data attributes).

## Catalog rules (`msgid` / `msgstr`)
- Search existing keys before adding new ones: `rg -n 'msgid "..."' i18n/*/messages.po`
- Treat `msgid` as the stable identifier; do not create a new key for simple copy edits.
- Edit catalogs in `i18n/`, never in `translations/`.
- Update `msgstr` for each locale when copy changes:
`i18n/en/messages.po`, `i18n/es-AR/messages.po`, `i18n/pt-BR/messages.po`.
- Keep placeholders and formatting tokens aligned across locales (`{0}`, line breaks, punctuation).
- Prefer consistent terminology across the three locales.
- Keep Spanish (`es-AR`) phrasing neutral and region-agnostic unless the product explicitly needs local wording.

## Treat these as user-facing
- JSX text nodes: `<p>Texto</p>`
- Props that render text: `title`, `label`, `placeholder`, `helper`, `description`, `srLabel`, `aria-label`, `alt`, `tooltip`, `emptyMessage`, `buttonText`, toast/notification messages
- Error messages shown to users (including in modals or notifications)
- Tag labels, chip labels, menu items, dropdown options

## Do not translate
- CSS class names, ids, keys, data attributes
- Internal enum values, route names, analytics event names
- Variables that already contain translated text from backend (unless explicitly required)

## Patterns

### Basic JSX literal
```jsx
<p>{i18n.gettext('Filtrar')}</p>
```

### Props with literals
```jsx
<Modal title={i18n.gettext('Filtrar')} />
<Input placeholder={i18n.gettext('Buscar...')} />
```

### Interpolation
```jsx
i18n.gettext('Eliminar filtro: {0}', value)
```

### Conditional literal
```jsx
{checked ? i18n.gettext('Habilitado') : i18n.gettext('Deshabilitado')}
```

### Using existing translated values
```jsx
// If label is already a translated key/value
<p>{i18n.gettext(label)}</p>
```

## Quick checklist
- `useI18n` imported and used
- No raw user-facing literals in JSX
- All user-facing string props wrapped
- Existing `msgid` searched before creating a new key
- Copy edits applied by updating `msgstr` in all locales
- New keys added only for new semantics, with translations in `en`, `es-AR`, and `pt-BR`
- Interpolations use `{0}` placeholders
- Non-user-facing literals left untouched
