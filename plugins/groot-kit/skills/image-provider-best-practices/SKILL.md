---
name: image-provider-best-practices
description: Use ImageProvider and image-loading best practices in MELI/Nordic frontends. Trigger whenever adding, replacing, reviewing, or debugging images, icons, logos, avatars, background assets, broken asset paths, lazy loading, or environment-dependent URLs so relative paths go through ImageProvider and absolute URLs are avoided.
metadata:
  tags: "context-optimized-v1.18.0"
---

# Image Provider Best Practices

## Quick start
Use ImageProvider for relative or environment-dependent image paths, keep default lazy-load enabled, and avoid hardcoded absolute URLs.

## Core workflow
1. Identify every new or modified image source.
2. Route relative or environment-dependent sources through ImageProvider (follow local usage patterns).
3. Preserve default lazy-load behavior unless an explicit above-the-fold requirement exists.
4. Replace absolute URLs with ImageProvider or environment-based configuration.

## Guidelines
- **ImageProvider**: Use the shared ImageProvider component/provider whenever image paths are relative or depend on the environment (CDN, base path, site).
- **Lazy-load**: Keep the default lazy-load behavior to improve performance; opt out only when product requirements demand eager loading.
- **No absolute URLs**: Avoid hardcoded absolute URLs in components; prefer relative paths or environment-based configuration.
- **Consistency**: Follow existing ImageProvider usage patterns in the codebase for props, imports, and naming.

## Patterns

### Relative path via ImageProvider
```
<ImageProvider src="images/banner.png" alt="Banner principal" />
```

### Environment-dependent asset
```
const logoPath = `images/logo-${siteId}.png`;
<ImageProvider src={logoPath} alt="Site logo" />
```

### Avoid hardcoded absolute URLs
```
const logoPath = "images/logo.png";
<ImageProvider src={logoPath} alt="Logo" />
```

## Quick checklist
- Relative or environment-dependent images use ImageProvider.
- Default lazy-load behavior stays enabled unless explicitly required.
- Absolute URLs are avoided or moved to environment configuration.
