#!/bin/bash
# sync-marketplace.sh
# Upgrades groot-marketplace for the active provider.
# Runs automatically on session start (SessionStart hook).

set -euo pipefail

readonly MARKETPLACE_NAME="groot-marketplace"

provider_argument="${1:-}"
case "$provider_argument" in
  --provider|-p)
    if [[ $# -ne 2 || -z "${2:-}" ]]; then
      printf 'ERROR: %s requires claude or codex\n' "$provider_argument" >&2
      exit 1
    fi
    provider="$2"
    ;;
  claude|codex)
    if [[ $# -ne 1 ]]; then
      printf 'ERROR: provider argument does not accept extra values\n' >&2
      exit 1
    fi
    provider="$provider_argument"
    ;;
  "")
    case "$0" in
      .agents/hooks/sync-marketplace.sh|*/.agents/hooks/sync-marketplace.sh)
        provider="codex"
        ;;
      .claude/hooks/sync-marketplace.sh|*/.claude/hooks/sync-marketplace.sh)
        provider="claude"
        ;;
      *)
        provider="claude"
        ;;
    esac
    ;;
  *)
    printf 'ERROR: unsupported marketplace provider: %s\n' "$provider_argument" >&2
    exit 1
    ;;
esac

case "$provider" in
  claude|codex) ;;
  *)
    printf 'ERROR: unsupported marketplace provider: %s\n' "$provider" >&2
    exit 1
    ;;
esac

echo "[marketplace-sync] Upgrading $MARKETPLACE_NAME for $provider..."
fury ai assets marketplace upgrade \
  --name "$MARKETPLACE_NAME" \
  --provider "$provider"
echo "[marketplace-sync] Done."
