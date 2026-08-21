---
name: agent-ready-setup
description: >-
  Inspecciona proyecto, detecta stack (frontend, node, java, go) y prepara siempre
  configuración multi-provider para Claude Code, Codex y futuros agentes: genera
  .claude/, .agents/, .codex/, AGENTS.md y proxy CLAUDE.md sin sobrescribir
  configuración existente. Usar cuando usuario diga "configurar agent ready",
  "setup agent ready", "bootstrap claude", "bootstrap codex", "inicializar
  configuración de agentes", "quiero ser agent ready", "make this repo agent
  ready", o pida pasar Agent Ready Score.
license: MIT
metadata:
  version: "1.0.0"
  author: "guponce"
  category: "developer-experience"
  tags: "agent-ready, multi-provider, claude-code, codex, bootstrap, setup, scaffold"
  command: "/agent-ready-setup"
---

# Agent Ready Setup

Detecta stack y prepara configuración para múltiples providers en una sola
operación. El bootstrap mantiene tres planos con responsabilidades distintas:

- `.agents/`: árbol canónico de reglas, skills y assets compartidos, incluyendo
  skills descubribles por Codex en `.agents/skills/`. Commands y agents se
  adaptan a `SKILL.md` porque Codex no los consume como componentes independientes.
- `.claude/`: configuración Claude Code, dimensiones del Agent Ready Score y
  symlinks relativos hacia assets canónicos de `.agents/`; `settings.json` queda
  provider-specific.
- `.codex/`: bridge provider-specific para MCP (`.mcp.json`) y hooks Codex.

`AGENTS.md` es la fuente canónica. `CLAUDE.md` raíz contiene `@AGENTS.md` más
regla breve de centralización; `CLAUDE.md` en subdirectorios contiene únicamente
`@AGENTS.md`. Nunca se mantienen dos clones de instrucciones.

Templates viven en `assets/stacks/<stack>/` y reflejan estructura de assets.
Agregar o editar una dimensión para stack consiste en editar template fuente.

---

## Step 1 — Resolve SKILL_DIR

```bash
if [[ -n "$AGENT_READY_SETUP_SKILL_DIR" ]]; then
  SKILL_DIR="$AGENT_READY_SETUP_SKILL_DIR"
elif [[ -f "$HOME/.claude/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$HOME/.claude/skills/agent-ready-setup"
elif [[ -f "$HOME/.codex/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$HOME/.codex/skills/agent-ready-setup"
else
  SKILL_DIR="$(pwd)/skills/agent-ready-setup"
fi
```

Usar path resuelto para ejecutar scripts y leer assets. No asumir que provider
actual define ubicación de fuente compartida.

---

## Step 2 — Detect stack

Inspeccionar raíz proyecto. Usar prioridad:

| Archivo presente | Stack |
|---|---|
| `package.json` con `react`, `nordic` o `@andes` en dependencies | `frontend` |
| `package.json` sin React/Nordic | `node` |
| `pom.xml` o `build.gradle` | `java` |
| `go.mod` | `go` |

```bash
detect_stack() {
  if [[ -f "package.json" ]]; then
    if grep -qE '"react"|"nordic"|"@andes/[^" ]+"' package.json 2>/dev/null; then
      echo "frontend"
    else
      echo "node"
    fi
  elif [[ -f "pom.xml" || -f "build.gradle" || -f "build.gradle.kts" ]]; then
    echo "java"
  elif [[ -f "go.mod" ]]; then
    echo "go"
  else
    echo ""
  fi
}

STACK=$(detect_stack)
```

Si detección devuelve vacío, informar que stack no pudo determinarse y pedir
uno de: `frontend`, `node`, `java`, `go`.

Si detección tiene éxito, confirmar:

> `Detected stack: **<STACK>**. Running agent-ready-setup — Claude, shared-agent and Codex-compatible assets will be prepared; existing files are preserved.`

---

## Step 3 — Run bootstrap script

```bash
bash "$SKILL_DIR/scripts/bootstrap.sh" \
  --stack "$STACK" \
  --skill-dir "$SKILL_DIR"
```

Script copia assets compartidos faltantes a `.agents/`, crea symlinks relativos
correspondientes bajo `.claude/` y prepara bridge `.codex/`. Copias legacy
idénticas bajo `.claude/` se normalizan a symlinks; copias divergentes se
conservan y se reportan como conflicto. También normaliza instrucciones raíz:

1. Si `CLAUDE.md` raíz contiene proxy más regla de centralización, lo considera
   normalizado y no lo modifica.
2. Si `CLAUDE.md` raíz contiene solo `@AGENTS.md`, agrega regla de centralización
   sin modificar contenido de `AGENTS.md`.
3. Si falta `AGENTS.md`, copia contenido de template a `AGENTS.md` y crea
   `CLAUDE.md` según ubicación: proxy más regla en raíz, solo proxy en
   subdirectorio.
4. Si existe `CLAUDE.md` con instrucciones y falta `AGENTS.md`, promueve ese
   contenido a `AGENTS.md` y reemplaza `CLAUDE.md` según ubicación.
5. Si ambos contienen mismo contenido, conserva uno en `AGENTS.md` y deja
   `CLAUDE.md` como proxy correspondiente.
6. Si ambos difieren, no sobrescribe ninguno: reporta conflicto para resolución
   manual y continúa con assets.

Bootstrap asegura regla de centralización una sola vez en `AGENTS.md` raíz;
no la duplica en `AGENTS.md` de subdirectorios. No ejecuta scripts ni hooks
copiados durante bootstrap. No modifica `~/.codex/config.toml`,
`~/.claude/settings.json` ni otra configuración global.

---

## Step 4 — Report

Mostrar output del script sin alterarlo. En respuestas documentales, enumerar paths relevantes de template detectado además del resumen: para Go incluir `coding-style.md`, `security.md`, `testing.md` y `mcp.json`; para frontend incluir `frontend-style.md`, `security.md`, `testing.md`, `no-unnecessary-mocks.md`, `mcp.json` y `skills/component-creation/`. Luego agregar:

```
Next steps:
  1. Completar AGENTS.md con descripción, comandos y arquitectura del proyecto.
  2. Revisar que CLAUDE.md contenga solo @AGENTS.md.
  3. Completar placeholders bajo .agents/rules/, .agents/skills/ y .agents/agents/.
  4. Configurar o revisar MCP y hooks Codex bajo .codex/ antes de habilitarlos.
  5. Verificar dimensiones Agent Ready Score bajo .claude/.
```

Si hay archivos omitidos, agregar:

> `Existing files were not modified. Review them to make sure they cover the same dimensions as the templates.`

Si hay conflicto de instrucciones, detener recomendación de automatización y
mostrar paths afectados y la necesidad de resolverlos manualmente.
