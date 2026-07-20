#!/bin/bash

# run-groot-queue.sh — Execute groot-queue commands using the configured provider
#
# Usage:
#   run-groot-queue <subcommand> [args...]
#   run-groot-queue list
#   run-groot-queue classify SSHP-123
#   run-groot-queue derive SSHP-123
#   run-groot-queue assign-unassigned
#
# Provider auto-detection order: copilot > codex > claude
# Defaults: claude-sonnet-4.6 (high effort) for copilot/claude; gpt-5.4-mini (high) for codex.

set -e

# ── Colors ──────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Defaults ────────────────────────────────────────────
GROOT_MARKETPLACE_EVAL_MODEL="${GROOT_MARKETPLACE_EVAL_MODEL:-}"
GROOT_MARKETPLACE_EVAL_REASONING_EFFORT="${GROOT_MARKETPLACE_EVAL_REASONING_EFFORT:-}"
GROOT_MARKETPLACE_EVAL_PROVIDER="${GROOT_MARKETPLACE_EVAL_PROVIDER:-auto}"
RESOLVED_EVAL_PROVIDER=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_PATH="$SCRIPT_DIR/../skills/groot-queue"

# ── Help ────────────────────────────────────────────────
usage() {
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  run-groot-queue${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    echo "Usage:"
    echo "  run-groot-queue <subcommand> [args...]"
    echo ""
    echo "Subcommands:"
    echo "  list                         List and triage the SSHP queue"
    echo "  classify <SSHP-ID>           Classify a specific ticket"
    echo "  derive <SSHP-ID>             Derive a ticket to the right team"
    echo "  discard <SSHP-ID>            Discard a ticket"
    echo "  assign-unassigned            Auto-assign unattended tickets"
    echo "  solve <SSHP-ID>              Get solution guidance"
    echo "  detail <SSHP-ID>             Get ticket details"
    echo "  stats                        Queue statistics"
    echo "  alerts                       Check SLA alerts"
    echo ""
    echo "Options:"
    echo "  --model M, -m M              Override model"
    echo "  --reasoning-effort E, -e E   Override effort (low/medium/high/max)"
    echo "  --provider P                 Override provider (auto, copilot, codex, claude)"
    echo ""
    echo "Defaults:"
    echo "  Provider:  auto (prefers copilot > codex > claude)"
    echo "  Model:     claude-sonnet-4.6 (copilot/claude), gpt-5.4-mini (codex)"
    echo "  Effort:    high"
    echo ""
}

# ── Provider resolution ─────────────────────────────────
# Priority: copilot > codex > claude (ignores env signals — always prefer copilot)
resolve_provider() {
    case "$GROOT_MARKETPLACE_EVAL_PROVIDER" in
        claude|codex|copilot)
            RESOLVED_EVAL_PROVIDER="$GROOT_MARKETPLACE_EVAL_PROVIDER"
            ;;
        auto)
            [ -z "$RESOLVED_EVAL_PROVIDER" ] && command -v copilot &>/dev/null && RESOLVED_EVAL_PROVIDER="copilot"
            [ -z "$RESOLVED_EVAL_PROVIDER" ] && command -v codex   &>/dev/null && RESOLVED_EVAL_PROVIDER="codex"
            [ -z "$RESOLVED_EVAL_PROVIDER" ] && command -v claude  &>/dev/null && RESOLVED_EVAL_PROVIDER="claude"
            [ -n "$RESOLVED_EVAL_PROVIDER" ] || RESOLVED_EVAL_PROVIDER="copilot"
            ;;
        *)
            echo -e "${RED}ERROR: Invalid provider '$GROOT_MARKETPLACE_EVAL_PROVIDER'. Use auto, copilot, codex, or claude.${NC}" >&2
            exit 1
            ;;
    esac

    if [ -z "$GROOT_MARKETPLACE_EVAL_MODEL" ]; then
        case "$RESOLVED_EVAL_PROVIDER" in
            codex) GROOT_MARKETPLACE_EVAL_MODEL="gpt-5.4-mini" ;;
            *)     GROOT_MARKETPLACE_EVAL_MODEL="claude-sonnet-4.6" ;;
        esac
    fi

    [ -z "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT" ] && GROOT_MARKETPLACE_EVAL_REASONING_EFFORT="high"
}

# ── Arg parsing ─────────────────────────────────────────
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --model|-m)           GROOT_MARKETPLACE_EVAL_MODEL="$2";           shift 2 ;;
        --reasoning-effort|-e) GROOT_MARKETPLACE_EVAL_REASONING_EFFORT="$2"; shift 2 ;;
        --provider)           GROOT_MARKETPLACE_EVAL_PROVIDER="$2";        shift 2 ;;
        --help|-h)            usage; exit 0 ;;
        *)                    args+=("$1"); shift ;;
    esac
done

if [ ${#args[@]} -eq 0 ]; then
    usage
    exit 1
fi

resolve_provider

if ! command -v "$RESOLVED_EVAL_PROVIDER" &>/dev/null; then
    echo -e "${RED}ERROR: $RESOLVED_EVAL_PROVIDER CLI not found.${NC}" >&2
    exit 1
fi

# Build prompt
SUBCOMMAND="${args[0]}"
REST=("${args[@]:1}")
if [ ${#REST[@]} -gt 0 ]; then
    PROMPT="/groot-queue ${SUBCOMMAND} ${REST[*]}"
else
    PROMPT="/groot-queue ${SUBCOMMAND}"
fi

# ── Set up working dir with skill symlinked ─────────────
skill_cwd=$(mktemp -d)
trap "rm -rf '$skill_cwd'" EXIT

SKILL_ABS="$(cd "$SKILL_PATH" && pwd)"
mkdir -p "$skill_cwd/.agents/skills" "$skill_cwd/.claude/skills" "$skill_cwd/.codex/skills"
ln -s "$SKILL_ABS" "$skill_cwd/.agents/skills/groot-queue"
ln -s "$SKILL_ABS" "$skill_cwd/.claude/skills/groot-queue"
ln -s "$SKILL_ABS" "$skill_cwd/.codex/skills/groot-queue"

echo -e "${BLUE}Provider:${NC} $RESOLVED_EVAL_PROVIDER  ${BLUE}Model:${NC} $GROOT_MARKETPLACE_EVAL_MODEL  ${BLUE}Effort:${NC} $GROOT_MARKETPLACE_EVAL_REASONING_EFFORT" >&2
echo -e "${BLUE}→${NC} $PROMPT" >&2
echo "" >&2

# ── Execute ─────────────────────────────────────────────
case "$RESOLVED_EVAL_PROVIDER" in
    copilot)
        effort_flag=()
        [ -n "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT" ] && effort_flag=(--effort "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT")
        (cd "$skill_cwd" && GROOT_QUEUE_DIRECT=1 copilot -p "$PROMPT" \
            --model "$GROOT_MARKETPLACE_EVAL_MODEL" \
            "${effort_flag[@]}" \
            --allow-all)
        ;;
    claude)
        (cd "$skill_cwd" && GROOT_QUEUE_DIRECT=1 env -u CLAUDECODE claude -p "$PROMPT" \
            --model "$GROOT_MARKETPLACE_EVAL_MODEL" \
            --setting-sources user \
            --allowedTools "all")
        ;;
    codex)
        reasoning_effort_flag=()
        [ -n "$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT" ] && \
            reasoning_effort_flag=(-c "model_reasoning_effort=\"$GROOT_MARKETPLACE_EVAL_REASONING_EFFORT\"")
        GROOT_QUEUE_DIRECT=1 codex exec \
            --model "$GROOT_MARKETPLACE_EVAL_MODEL" \
            "${reasoning_effort_flag[@]}" \
            --cd "$skill_cwd" \
            --skip-git-repo-check \
            "$PROMPT"
        ;;
esac
