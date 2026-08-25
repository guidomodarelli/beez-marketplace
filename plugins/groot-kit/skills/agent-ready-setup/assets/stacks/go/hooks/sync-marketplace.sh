#!/bin/bash
# sync-marketplace.sh
# Upgrades the groot-marketplace to pull the latest Claude Code configs.
# Runs automatically on every Claude Code session start (SessionStart hook).

set -e

echo "[claude-sync] Upgrading groot-marketplace..."
fury ai assets marketplace upgrade --name groot-marketplace
echo "[claude-sync] Done."
