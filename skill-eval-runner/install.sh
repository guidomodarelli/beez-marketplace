#!/bin/bash

# Installer for run-evals command
# Installs the central eval runner globally so it can be run from anywhere

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/run-evals.sh"

INSTALL_DIR="$HOME/.local/bin"
TARGET_SCRIPT="$INSTALL_DIR/run-evals"

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Run-Evals Global Installer${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo -e "${RED}✗ Error: run-evals.sh not found at $SOURCE_SCRIPT${NC}"
    exit 1
fi

mkdir -p "$INSTALL_DIR"

if [ -f "$TARGET_SCRIPT" ] || [ -L "$TARGET_SCRIPT" ]; then
    echo -e "${YELLOW}run-evals is already installed at $TARGET_SCRIPT${NC}"
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
    echo -e "${GREEN}✓ run-evals installed successfully!${NC}"
    echo ""
    echo -e "  Command:  ${GREEN}run-evals${NC}"
    echo -e "  Location: ${GREEN}$TARGET_SCRIPT${NC}"
    echo -e "  Source:   ${GREEN}$SOURCE_SCRIPT${NC}"
    echo ""
else
    echo -e "${RED}✗ Error during installation${NC}"
    exit 1
fi

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${YELLOW}⚠ $INSTALL_DIR is not in your PATH${NC}"
    echo -e "  Add: ${GREEN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo ""
fi

echo -e "${BLUE}Usage:${NC}"
echo -e "  ${GREEN}run-evals${NC}                  Run evals for skill in current dir (JSONL by default)"
echo -e "  ${GREEN}run-evals path/to/skill${NC}    Run evals for a specific skill (JSONL by default)"
echo -e "  ${GREEN}run-evals --all${NC}            Run evals for all skills (JSONL by default)"
echo -e "  ${GREEN}run-evals --pretty${NC}         Use the human-readable colored report"
echo -e "  ${GREEN}run-evals --provider codex${NC} Override provider auto-detection"
echo ""
