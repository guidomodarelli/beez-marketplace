---
name: prepare-release
description: >-
  Automates release branch creation and PR to master. Reads last git tag from
  master, calculates next MINOR version, creates release/x.x.x from develop,
  and opens the PR. Triggers on /prepare-release, "preparar release",
  "crear release", "nuevo release", "quiero hacer un release".
license: MIT
metadata:
  version: "1.0.0"
  author: "lpadularrosa"
  category: "development"
  tags: "release, git, versioning, gitflow, github, prepare-release"
  command: "/prepare-release"
---

# Prepare Release

Automatiza el proceso de preparar un release: calcula la próxima versión, crea la rama `release/x.x.x` desde develop y abre el PR a master.

## Cuando Usar Esta Skill

- Usuario invoca `/prepare-release`
- Usuario dice "preparar release", "crear release", "nuevo release", "quiero hacer un release"

---

## Flujo de Ejecución

### Paso 1 — Verificar prerequisitos

Ejecutar los siguientes chequeos:

```bash
# Verificar gh CLI
gh --version

# Verificar remote origin
git remote get-url origin

# Verificar si hay cambios sin commitear
git status --porcelain
```

- Si `gh` no está instalado: informar al usuario que debe instalar GitHub CLI (`brew install gh`) y detener.
- Si no hay remote `origin`: informar al usuario y detener.
- Si hay cambios sin commitear:
  - Ejecutar `git stash`
  - Informar al usuario: "Se guardaron los cambios locales con git stash. Se restaurarán al finalizar."
  - Guardar en memoria que se hizo stash para restaurar en el Paso 7.

---

### Paso 2 — Obtener última versión desde master

```bash
git fetch origin --tags
git tag --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1
```

- Si se encontró un tag (ej: `1.115.0` o `v1.115.0`):
  - Normalizar quitando el prefijo `v` si existe.
  - Guardar como versión actual.
- Si **no** se encontró ningún tag:
  - Informar al usuario: "No se encontraron tags de versión en el repositorio."
  - Usar `0.0.0` como versión base y continuar al Paso 3.

---

### Paso 3 — Calcular próxima versión y confirmar con el usuario

- Parsear la versión actual en `MAJOR`, `MINOR`, `PATCH`.
- Calcular próxima versión: `MAJOR.(MINOR+1).0`

Mostrar al usuario:
```
Versión actual (último tag en master): X.Y.Z
Próxima versión propuesta:             X.(Y+1).0
```

Preguntar con AskUserQuestion:
- **Pregunta**: "¿Confirmás la versión `X.(Y+1).0` para este release?"
- **Header**: "Versión"
- **Opciones**:
  1. `Confirmar X.(Y+1).0` — Usar la versión calculada.
  2. `Ingresar manualmente` — El usuario escribirá la versión en "Other".

Si el usuario eligió "Ingresar manualmente" (seleccionó "Other" e ingresó un valor): usar esa versión. Validar que tenga formato `X.Y.Z` (tres números separados por puntos).

Guardar la versión final confirmada como `RELEASE_VERSION`.

---

### Paso 4 — Verificar que la rama release no exista ya

```bash
git branch -r | grep "release/${RELEASE_VERSION}"
```

- Si ya existe la rama `release/${RELEASE_VERSION}` en origin: informar al usuario y detener. La rama ya fue creada previamente.

---

### Paso 5 — Crear rama release desde develop

```bash
git checkout -b release/${RELEASE_VERSION} origin/develop
```

- Si el comando falla (ej: `origin/develop` no existe), intentar con `origin/main` como fallback.
- Si ambos fallan: informar al usuario e indicar que verifique el nombre de la rama base.

---

### Paso 6 — Push de la rama

```bash
git push -u origin release/${RELEASE_VERSION}
```

- Si el push falla: mostrar el error al usuario y detener.

---

### Paso 7 — Crear PR a master

```bash
gh pr create \
  --title "release: version ${RELEASE_VERSION}" \
  --body "$(cat <<'EOF'
## Release ${RELEASE_VERSION}

Este PR prepara el release de la versión **${RELEASE_VERSION}**.

- **Rama origen**: \`release/${RELEASE_VERSION}\`
- **Rama destino**: \`master\`

### Notas
- Al abrir este PR se genera automáticamente el **Release Candidate**.
- Al mergearlo a master se genera el **Release definitivo**.
EOF
)" \
  --base master \
  --head release/${RELEASE_VERSION}
```

- Mostrar al usuario la URL del PR creado.

---

### Paso 8 — Restaurar stash (si aplica)

- Si en el Paso 1 se hizo `git stash`:
  ```bash
  git stash pop
  ```
  - Informar al usuario: "Cambios locales restaurados."

---

### Resultado Final

Informar al usuario:

```
✓ Rama release/${RELEASE_VERSION} creada desde develop
✓ PR abierto hacia master
→ URL del PR: <url>
```

---

## Manejo de Errores

| Situación | Acción |
|-----------|--------|
| `gh` no instalado | Informar e indicar instalación: `brew install gh` |
| Sin remote origin | Informar que el repo no tiene remote configurado |
| Sin tags en el repo | Usar 0.0.0 como base y proponer 0.1.0 |
| `origin/develop` no existe | Intentar con `origin/main`, si falla informar al usuario |
| Rama release ya existe en origin | Informar y detener — no recrear |
| Push falla por permisos | Mostrar error y sugerir verificar permisos del repo |
| Versión manual con formato inválido | Solicitar nuevamente con formato `X.Y.Z` |
