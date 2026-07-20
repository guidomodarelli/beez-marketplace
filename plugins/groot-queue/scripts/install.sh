#!/bin/bash

# Installer for the run-groot-queue command

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/run-groot-queue.sh"
INSTALL_DIR="$HOME/.local/bin"
TARGET_SCRIPT="$INSTALL_DIR/run-groot-queue"

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  run-groot-queue Installer${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo -e "${RED}✗ Error: run-groot-queue.sh not found at $SOURCE_SCRIPT${NC}"
    exit 1
fi

mkdir -p "$INSTALL_DIR"

if [ -f "$TARGET_SCRIPT" ] || [ -L "$TARGET_SCRIPT" ]; then
    echo -e "${YELLOW}run-groot-queue is already installed at $TARGET_SCRIPT${NC}"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[YySs]$ ]]; then
        echo -e "${YELLOW}Installation cancelled.${NC}"
        exit 0
    fi
    rm -f "$TARGET_SCRIPT"
fi

ln -sf "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
chmod +x "$SOURCE_SCRIPT"

if [ -L "$TARGET_SCRIPT" ] && [ -x "$TARGET_SCRIPT" ]; then
    echo -e "${GREEN}✓ run-groot-queue installed → $TARGET_SCRIPT${NC}"
else
    echo -e "${RED}✗ Error during installation${NC}"
    exit 1
fi

echo ""

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${YELLOW}⚠ $INSTALL_DIR is not in your PATH${NC}"
    echo -e "  Add: ${GREEN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo ""
fi

echo -e "${BLUE}Usage:${NC}"
echo -e "  ${GREEN}run-groot-queue list${NC}                List and triage the SSHP queue"
echo -e "  ${GREEN}run-groot-queue classify SSHP-X${NC}    Classify a ticket"
echo -e "  ${GREEN}run-groot-queue derive SSHP-X${NC}      Derive a ticket"
echo -e "  ${GREEN}run-groot-queue assign-unassigned${NC}  Auto-assign unattended tickets"
echo -e "  ${GREEN}run-groot-queue --provider copilot${NC} Override provider"
echo ""
