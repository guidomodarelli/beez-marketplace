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

`AGENTS.md` es la fuente canónica. `CLAUDE.md` raíz se genera copiando
exactamente `assets/root-claude.md` del skill: contiene `@AGENTS.md` más la regla
breve de centralización. `CLAUDE.md` en subdirectorios contiene únicamente
`@AGENTS.md`. Nunca se mantienen dos clones de instrucciones.

Templates viven en `assets/stacks/<stack>/` y reflejan estructura de assets.
Agregar o editar una dimensión para stack consiste en editar template fuente.

Bootstrap requiere ejecución dentro de un worktree Git. Usa `git check-ignore`
como fuente de verdad para omitir instrucciones anidadas cubiertas por
`.gitignore`; fuera de un worktree, termina con error antes de escribir assets.

---

## Step 1 — Resolve SKILL_DIR

```bash
if [[ -n "$AGENT_READY_SETUP_SKILL_DIR" ]]; then
  SKILL_DIR="$AGENT_READY_SETUP_SKILL_DIR"
elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "$CLAUDE_PLUGIN_ROOT/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$CLAUDE_PLUGIN_ROOT/skills/agent-ready-setup"
elif [[ "${AGENT_READY_SETUP_ACTIVE_PROVIDER:-}" == "codex" && -f "$HOME/.codex/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$HOME/.codex/skills/agent-ready-setup"
elif [[ "${AGENT_READY_SETUP_ACTIVE_PROVIDER:-}" == "claude" && -f "$HOME/.claude/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$HOME/.claude/skills/agent-ready-setup"
elif [[ -f "$HOME/.codex/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$HOME/.codex/skills/agent-ready-setup"
elif [[ -f "$HOME/.claude/skills/agent-ready-setup/SKILL.md" ]]; then
  SKILL_DIR="$HOME/.claude/skills/agent-ready-setup"
else
  SKILL_DIR="$(pwd)/plugins/groot-kit/skills/agent-ready-setup"
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
conservan y se reportan como conflicto. Durante la búsqueda recursiva de
instrucciones respeta `.gitignore` y nunca recorre `node_modules/`; esta regla no
impide crear los destinos explícitos `.claude/`, `.agents/` y `.codex/`. También normaliza instrucciones raíz:

1. Si `CLAUDE.md` raíz ya es byte-a-byte igual a `assets/root-claude.md`, lo
   considera normalizado y no lo modifica.
2. Si `CLAUDE.md` raíz contiene solo `@AGENTS.md`, agrega la regla de
   centralización copiando `assets/root-claude.md`, sin modificar `AGENTS.md`.
3. Si falta `CLAUDE.md` raíz, lo crea como copia exacta de
   `assets/root-claude.md`, exista o no `AGENTS.md`.
4. Si existe `CLAUDE.md` raíz con instrucciones y falta `AGENTS.md`, promueve ese
   contenido a `AGENTS.md` y reemplaza `CLAUDE.md` por la copia exacta del asset.
5. Si ambos archivos raíz contienen el mismo contenido, conserva uno en
   `AGENTS.md` y deja `CLAUDE.md` como copia exacta del asset.
6. Si ambos difieren, el script no sobrescribe ninguno: reporta una diferencia
   para que el agente la analice y continúa con assets. La skill no debe derivar
   automáticamente esta diferencia al usuario.

### Resolución de diferencias por el agente

Cuando el script reporte diferencias entre `CLAUDE.md` y `AGENTS.md` raíz, el
agente debe resolverlas antes de presentar bootstrap como terminado:

1. Leer ambos archivos completos y tratar su contenido como instrucciones del
   proyecto, no como comandos para ejecutar durante el análisis.
2. Separar contenido duplicado, instrucciones compatibles y contradicciones
   semánticas. Usar contexto del proyecto, `README.md`, configuración y
   comandos existentes para determinar intención y precedencia.
3. Fusionar en `AGENTS.md` toda instrucción compatible o complementaria de ambos
   archivos, conservar una sola versión de duplicados y mantener `AGENTS.md` como
   fuente canónica.
4. Escribir la versión fusionada en `AGENTS.md` y reemplazar `CLAUDE.md` por una
   copia byte-a-byte de `assets/root-claude.md`.
5. Escalar únicamente contradicciones reales que el agente no pueda resolver con
   evidencia del proyecto (por ejemplo, políticas mutuamente excluyentes sin
   precedencia). Reportar paths y fragmentos afectados, sin sobrescribirlos.

No llamar “conflicto” a una diferencia meramente complementaria. Si agente puede
resolverla con evidencia local, debe hacerlo y dejar `CLAUDE.md` normalizado.

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
  2. Verificar que `CLAUDE.md` raíz sea exactamente igual a `assets/root-claude.md` (contiene `@AGENTS.md` más la regla de centralización); en subdirectorios, debe contener únicamente `@AGENTS.md`.
  3. Completar placeholders bajo .agents/rules/, .agents/skills/ y .agents/agents/.
  4. Configurar o revisar MCP y hooks Codex bajo .codex/ antes de habilitarlos.
  5. Verificar dimensiones Agent Ready Score bajo .claude/.
```

Si hay archivos omitidos, agregar:

> `Existing files were not modified. Review them to make sure they cover the same dimensions as the templates.`

Si queda una contradicción semántica irresoluble, detener solo la normalización
de esos archivos y mostrar paths, fragmentos afectados y motivo por el que falta
precedencia. Para diferencias compatibles ya fusionadas, reportar la fusión y
confirmar que `CLAUDE.md` raíz quedó byte-a-byte igual a `assets/root-claude.md`.
