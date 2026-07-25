#!/bin/bash

# run-groot-queue.sh — Execute groot-queue commands using the configured provider.
# Non-operational auto order: copilot > codex > claude.
# Operational auto order: codex > claude (Copilot has no readiness inventory API).

set -euo pipefail
umask 077

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

GROOT_MARKETPLACE_EVAL_MODEL="${GROOT_MARKETPLACE_EVAL_MODEL:-}"
GROOT_MARKETPLACE_EVAL_REASONING_EFFORT="${GROOT_MARKETPLACE_EVAL_REASONING_EFFORT:-}"
GROOT_MARKETPLACE_EVAL_PROVIDER="${GROOT_MARKETPLACE_EVAL_PROVIDER:-auto}"
RESOLVED_EVAL_PROVIDER=""
SKILL_CWD=""
READINESS_RESULT_FILE=""
LAST_READINESS_EXIT_CODE=0
LAST_READINESS_FAILURE_CODES=""

unset GROOT_QUEUE_READINESS_RESULT_FILE GROOT_QUEUE_GRID_PREFLIGHT_RESULT_FILE GROOT_QUEUE_ACTIVE_PROVIDER

SOURCE_PATH="${BASH_SOURCE[0]}"
while [ -L "$SOURCE_PATH" ]; do
    SOURCE_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$SOURCE_PATH")" && pwd -P)"
    LINK_TARGET="$(readlink "$SOURCE_PATH")"
    case "$LINK_TARGET" in
        /*) SOURCE_PATH="$LINK_TARGET" ;;
        *) SOURCE_PATH="$SOURCE_DIRECTORY/$LINK_TARGET" ;;
    esac
done
SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$SOURCE_PATH")" && pwd -P)"
SKILL_PATH="$SCRIPT_DIRECTORY/../skills/groot-queue"
READINESS_CHECKER="$SKILL_PATH/scripts/check-groot-queue-readiness.sh"

usage() {
    printf '%b\n' "${BLUE}════════════════════════════════════════${NC}"
    printf '%b\n' "${BLUE}  run-groot-queue${NC}"
    printf '%b\n' "${BLUE}════════════════════════════════════════${NC}"
    printf '\nUso:\n'
    printf '  run-groot-queue <subcomando> [argumentos...]\n\n'
    printf 'Subcomandos:\n'
    printf '  start                              Mostrar bienvenida y catálogo\n'
    printf '  setup                              Verificar el entorno\n'
    printf '  list                               Listar y triar la cola SSHP\n'
    printf '  classify                           Clasificar tickets abiertos\n'
    printf '  detail <SSHP-ID>                   Mostrar detalle de un ticket\n'
    printf '  solve <SSHP-ID>                    Obtener una guía de solución\n'
    printf '  alerts [--dry-run]                 Revisar alertas de SLA\n'
    printf '  stats                              Mostrar estadísticas de la cola\n'
    printf '  assign-unassigned                  Asignar tickets sin responsable\n'
    printf '  derive <SSHP-ID> [...]             Derivar tickets al equipo correcto\n'
    printf '  discard <SSHP-ID> [...]            Descartar tickets fuera de alcance\n'
    printf '  save <SSHP-ID> <descripción>       Guardar una solución aplicada\n'
    printf '  add-rule                           Agregar una regla de triage\n'
    printf '  backfill-guides                    Publicar guías faltantes\n'
    printf '  analyze-history [opciones]         Analizar tickets cerrados\n\n'
    printf 'Opciones del launcher:\n'
    printf '  --model M, -m M                    Sobrescribir modelo\n'
    printf '  --reasoning-effort E, -e E         Sobrescribir esfuerzo (low/medium/high/max)\n'
    printf '  --provider P                       Usar provider (auto/copilot/codex/claude)\n'
    printf '  --help, -h                         Mostrar esta ayuda antes del subcomando\n\n'
    printf 'En comandos operativos, auto evalúa codex y claude; setup/help también admite copilot.\n'
}

fail() {
    printf '%bError:%b %s\n' "$RED" "$NC" "$1" >&2
    exit 2
}

require_option_value() {
    local option_name="$1"
    local remaining_count="$2"
    local option_value="${3:-}"

    if [ "$remaining_count" -lt 2 ] || [ -z "$option_value" ]; then
        fail "la opción $option_name requiere un valor."
    fi

    case "$option_value" in
        -*) fail "la opción $option_name requiere un valor válido." ;;
        *) ;;
    esac
}

cleanup() {
    if [ -n "${SKILL_CWD:-}" ] && [ -d "$SKILL_CWD" ]; then
        rm -rf -- "$SKILL_CWD"
    fi
}

create_skill_cwd() {
    if SKILL_CWD="$(mktemp -d -t groot-queue.XXXXXX 2>/dev/null)"; then
        return 0
    fi

    if SKILL_CWD="$(mktemp -d /tmp/groot-queue.XXXXXX 2>/dev/null)"; then
        return 0
    fi

    return 1
}

resolve_provider_without_readiness() {
    local candidate_provider

    if [ "$GROOT_MARKETPLACE_EVAL_PROVIDER" != "auto" ]; then
        RESOLVED_EVAL_PROVIDER="$GROOT_MARKETPLACE_EVAL_PROVIDER"
        return 0
    fi

    for candidate_provider in copilot codex claude; do
        if command -v "$candidate_provider" >/dev/null 2>&1; then
            RESOLVED_EVAL_PROVIDER="$candidate_provider"
            return 0
        fi
    done

    return 1
}

read_readiness_failure_codes() {
    local failure_codes=""

    if ! command -v jq >/dev/null 2>&1; then
        printf '%s' 'LOCAL_DEPENDENCY_UNAVAILABLE'
        return 0
    fi

    failure_codes="$(jq -er '
        select(type == "object" and (.failures | type == "array"))
        | [.failures[].code | select(type == "string")]
        | unique
        | join(", ")
        | select(length > 0)
    ' "$READINESS_RESULT_FILE" 2>/dev/null || true)"

    printf '%s' "${failure_codes:-READINESS_RESULT_INVALID}"
}

run_readiness() {
    local requested_provider="$1"
    local checker_status=0

    : > "$READINESS_RESULT_FILE"
    chmod 600 "$READINESS_RESULT_FILE"

    if bash "$READINESS_CHECKER" --provider "$requested_provider" > "$READINESS_RESULT_FILE" 2>/dev/null; then
        checker_status=0
    else
        checker_status=$?
    fi

    LAST_READINESS_EXIT_CODE="$checker_status"
    LAST_READINESS_FAILURE_CODES="$(read_readiness_failure_codes)"

    if [ "$checker_status" -eq 0 ] \
        && command -v jq >/dev/null 2>&1 \
        && jq -e --arg provider "$requested_provider" \
            '.schema_version == 2 and .scope == "shell" and .ok == true and .exit_code == 0 and .provider == $provider' \
            "$READINESS_RESULT_FILE" >/dev/null 2>&1; then
        LAST_READINESS_FAILURE_CODES=""
        return 0
    fi

    if [ "$checker_status" -eq 0 ]; then
        LAST_READINESS_EXIT_CODE=70
    fi

    return 1
}

resolve_operational_provider() {
    local candidate_provider
    local candidate_summary
    local failure_summaries=()

    if [ "$GROOT_MARKETPLACE_EVAL_PROVIDER" != "auto" ]; then
        if run_readiness "$GROOT_MARKETPLACE_EVAL_PROVIDER"; then
            RESOLVED_EVAL_PROVIDER="$GROOT_MARKETPLACE_EVAL_PROVIDER"
            return 0
        fi

        printf '%bEl readiness de groot-queue bloqueó la ejecución.%b\n' "$RED" "$NC" >&2
        printf 'Provider %s: %s (exit %s).\n' \
            "$GROOT_MARKETPLACE_EVAL_PROVIDER" \
            "$LAST_READINESS_FAILURE_CODES" \
            "$LAST_READINESS_EXIT_CODE" >&2
        printf 'Ejecutá run-groot-queue setup con este provider para diagnosticar el entorno.\n' >&2
        return 1
    fi

    for candidate_provider in codex claude; do
        if run_readiness "$candidate_provider"; then
            RESOLVED_EVAL_PROVIDER="$candidate_provider"
            return 0
        fi

        candidate_summary="$candidate_provider: $LAST_READINESS_FAILURE_CODES (exit $LAST_READINESS_EXIT_CODE)"
        failure_summaries+=("$candidate_summary")
    done

    printf '%bNingún provider superó el readiness de groot-queue.%b\n' "$RED" "$NC" >&2
    for candidate_summary in "${failure_summaries[@]}"; do
        printf '  - %s\n' "$candidate_summary" >&2
    done
    printf 'Ejecutá run-groot-queue setup con un provider disponible para diagnosticar el entorno.\n' >&2
    return 1
}

COMMAND_NAME=""
COMMAND_ARGUMENTS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --model|-m)
            require_option_value "$1" "$#" "${2:-}"
            GROOT_MARKETPLACE_EVAL_MODEL="$2"
            shift 2
            ;;
        --reasoning-effort|-e)
            require_option_value "$1" "$#" "${2:-}"
            GROOT_MARKETPLACE_EVAL_REASONING_EFFORT="$2"
            shift 2
            ;;
        --provider)
            require_option_value "$1" "$#" "${2:-}"
            GROOT_MARKETPLACE_EVAL_PROVIDER="$2"
            shift 2
            ;;
        --help|-h)
            if [ -z "$COMMAND_NAME" ]; then
                usage
                exit 0
            fi
            COMMAND_ARGUMENTS+=("$1")
            shift
            ;;
        --)
            shift
            if [ -z "$COMMAND_NAME" ]; then
                if [ "$#" -eq 0 ]; then
                    fail 'falta el subcomando después de --.'
                fi
                COMMAND_NAME="$1"
                shift
            fi
            while [ "$#" -gt 0 ]; do
                COMMAND_ARGUMENTS+=("$1")
                shift
            done
            ;;
        -*)
            if [ -z "$COMMAND_NAME" ]; then
                fail "opción desconocida: $1"
            fi
            COMMAND_ARGUMENTS+=("$1")
            shift
            ;;
        *)
            if [ -z "$COMMAND_NAME" ]; then
                COMMAND_NAME="$1"
            else
                COMMAND_ARGUMENTS+=("$1")
            fi
            shift
            ;;
    esac
done

if [ -z "$COMMAND_NAME" ]; then
    usage >&2
    exit 2
fi

case "$GROOT_MARKETPLACE_EVAL_PROVIDER" in
    auto|copilot|codex|claude) ;;
    *) fail "provider inválido: $GROOT_MARKETPLACE_EVAL_PROVIDER. Usá auto, copilot, codex o claude." ;;
esac

if [ -z "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT" ]; then
    GROOT_MARKETPLACE_EVAL_REASONING_EFFORT='high'
fi
case "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT" in
    low|medium|high|max) ;;
    *) fail "effort inválido: $GROOT_MARKETPLACE_EVAL_REASONING_EFFORT. Usá low, medium, high o max." ;;
esac

COMMAND_REQUESTS_HELP=false
if [ "${#COMMAND_ARGUMENTS[@]}" -gt 0 ]; then
    for command_argument in "${COMMAND_ARGUMENTS[@]}"; do
        case "$command_argument" in
            --help|-h) COMMAND_REQUESTS_HELP=true ;;
            *) ;;
        esac
    done
fi

if ! create_skill_cwd; then
    printf '%bError:%b no se pudo crear el directorio temporal.\n' "$RED" "$NC" >&2
    exit 70
fi
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if ! SKILL_ABSOLUTE_PATH="$(CDPATH= cd -- "$SKILL_PATH" && pwd -P)"; then
    printf '%bError:%b no se pudo resolver la skill groot-queue.\n' "$RED" "$NC" >&2
    exit 70
fi

mkdir -p "$SKILL_CWD/.agents/skills" "$SKILL_CWD/.claude/skills" "$SKILL_CWD/.codex/skills"
ln -s "$SKILL_ABSOLUTE_PATH" "$SKILL_CWD/.agents/skills/groot-queue"
ln -s "$SKILL_ABSOLUTE_PATH" "$SKILL_CWD/.claude/skills/groot-queue"
ln -s "$SKILL_ABSOLUTE_PATH" "$SKILL_CWD/.codex/skills/groot-queue"

OPERATIONAL_COMMAND=true
if [ "$COMMAND_NAME" = 'setup' ] || [ "$COMMAND_REQUESTS_HELP" = 'true' ]; then
    OPERATIONAL_COMMAND=false
fi

if [ "$OPERATIONAL_COMMAND" = 'true' ]; then
    READINESS_RESULT_FILE="$SKILL_CWD/readiness-result.json"

    if ! resolve_operational_provider; then
        exit 1
    fi
else
    if ! resolve_provider_without_readiness; then
        printf '%bError:%b no se encontró ningún CLI de provider disponible.\n' "$RED" "$NC" >&2
        exit 2
    fi
fi

if ! command -v "$RESOLVED_EVAL_PROVIDER" >/dev/null 2>&1; then
    printf '%bError:%b no se encontró el CLI de %s.\n' "$RED" "$NC" "$RESOLVED_EVAL_PROVIDER" >&2
    exit 2
fi

if [ -z "$GROOT_MARKETPLACE_EVAL_MODEL" ]; then
    case "$RESOLVED_EVAL_PROVIDER" in
        codex) GROOT_MARKETPLACE_EVAL_MODEL='gpt-5.4-mini' ;;
        *) GROOT_MARKETPLACE_EVAL_MODEL='claude-sonnet-4.6' ;;
    esac
fi

PROMPT="/groot-queue $COMMAND_NAME"
if [ "${#COMMAND_ARGUMENTS[@]}" -gt 0 ]; then
    for command_argument in "${COMMAND_ARGUMENTS[@]}"; do
        PROMPT="$PROMPT $command_argument"
    done
fi

CHILD_ENVIRONMENT=(
    "GROOT_QUEUE_ACTIVE_PROVIDER=$RESOLVED_EVAL_PROVIDER"
    "GROOT_QUEUE_SKILL_DIR=$SKILL_ABSOLUTE_PATH"
)
if [ "$OPERATIONAL_COMMAND" = 'true' ]; then
    CHILD_ENVIRONMENT+=("GROOT_QUEUE_READINESS_RESULT_FILE=$READINESS_RESULT_FILE")
fi
if [ "$RESOLVED_EVAL_PROVIDER" = 'codex' ]; then
    CHILD_ENVIRONMENT+=("FURY_CODEX_MCP_GLOBAL_INSTALL=0")
fi

printf '%bProvider:%b %s\n' "$BLUE" "$NC" "$RESOLVED_EVAL_PROVIDER" >&2
printf '%bIniciando groot-queue.%b\n\n' "$GREEN" "$NC" >&2

case "$RESOLVED_EVAL_PROVIDER" in
    copilot)
        COPILOT_EFFORT_FLAGS=()
        if [ -n "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT" ]; then
            COPILOT_EFFORT_FLAGS=(--effort "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT")
        fi
        (
            cd "$SKILL_CWD"
            env "${CHILD_ENVIRONMENT[@]}" \
                copilot -p "$PROMPT" \
                --model "$GROOT_MARKETPLACE_EVAL_MODEL" \
                "${COPILOT_EFFORT_FLAGS[@]}" \
                --allow-all
        )
        ;;
    claude)
        (
            cd "$SKILL_CWD"
            env -u CLAUDECODE "${CHILD_ENVIRONMENT[@]}" \
                claude -p "$PROMPT" \
                --model "$GROOT_MARKETPLACE_EVAL_MODEL" \
                --setting-sources user \
                --allowedTools 'all'
        )
        ;;
    codex)
        CODEX_REASONING_FLAGS=()
        if [ -n "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT" ]; then
            CODEX_REASONING_FLAGS=(-c "model_reasoning_effort=\"$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT\"")
        fi
        env "${CHILD_ENVIRONMENT[@]}" \
            codex exec \
            --model "$GROOT_MARKETPLACE_EVAL_MODEL" \
            "${CODEX_REASONING_FLAGS[@]}" \
            --cd "$SKILL_CWD" \
            --skip-git-repo-check \
            "$PROMPT"
        ;;
esac
