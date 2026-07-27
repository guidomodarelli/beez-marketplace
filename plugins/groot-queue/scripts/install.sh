#!/bin/bash

# Installer for the run-groot-queue command.

set -euo pipefail
umask 077

readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_SCRIPT="$SCRIPT_DIRECTORY/run-groot-queue.sh"
INSTALL_DIRECTORY="$HOME/.local/bin"
TARGET_SCRIPT="$INSTALL_DIRECTORY/run-groot-queue"
TEMPORARY_DIRECTORY=""
TEMPORARY_WRAPPER=""

cleanup() {
    if [ -n "${TEMPORARY_DIRECTORY:-}" ] && [ -d "$TEMPORARY_DIRECTORY" ]; then
        rm -rf -- "$TEMPORARY_DIRECTORY"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

create_wrapper() {
    local quoted_source

    TEMPORARY_DIRECTORY="$(mktemp -d "$INSTALL_DIRECTORY/.run-groot-queue.XXXXXX")"
    TEMPORARY_WRAPPER="$TEMPORARY_DIRECTORY/run-groot-queue"
    printf -v quoted_source '%q' "$SOURCE_SCRIPT"
    printf '#!/bin/bash\nexec %s "$@"\n' "$quoted_source" > "$TEMPORARY_WRAPPER"
    chmod 755 "$TEMPORARY_WRAPPER"
}

publish_wrapper() {
    if [ -L "$TARGET_SCRIPT" ] && [ -d "$TARGET_SCRIPT" ]; then
        rm -f -- "$TARGET_SCRIPT"
    fi
    mv -f -- "$TEMPORARY_WRAPPER" "$TARGET_SCRIPT"
    rmdir -- "$TEMPORARY_DIRECTORY"
    TEMPORARY_DIRECTORY=""
    TEMPORARY_WRAPPER=""
}

printf '%b\n' "${BLUE}════════════════════════════════════════${NC}"
printf '%b\n' "${BLUE}  Instalador de run-groot-queue${NC}"
printf '%b\n\n' "${BLUE}════════════════════════════════════════${NC}"

if [ ! -f "$SOURCE_SCRIPT" ]; then
    printf '%b\n' "${RED}✗ Error: no se encontró run-groot-queue.sh en $SOURCE_SCRIPT${NC}" >&2
    exit 1
fi
if [ ! -x "$SOURCE_SCRIPT" ]; then
    printf '%b\n' "${RED}✗ Error: run-groot-queue.sh no es ejecutable. Corregí el permiso en el checkout antes de instalar.${NC}" >&2
    exit 1
fi

mkdir -p "$INSTALL_DIRECTORY"

if [ -d "$TARGET_SCRIPT" ] && [ ! -L "$TARGET_SCRIPT" ]; then
    printf '%b\n' "${RED}✗ Error: $TARGET_SCRIPT es un directorio; no puede reemplazarse por un wrapper.${NC}" >&2
    exit 1
fi

create_wrapper

if [ -f "$TARGET_SCRIPT" ] && [ ! -L "$TARGET_SCRIPT" ] && cmp -s "$TEMPORARY_WRAPPER" "$TARGET_SCRIPT"; then
    printf '%b\n' "${GREEN}✓ run-groot-queue ya apunta al launcher actual → $TARGET_SCRIPT${NC}"
elif [ -e "$TARGET_SCRIPT" ] || [ -L "$TARGET_SCRIPT" ]; then
    printf '%b\n' "${YELLOW}run-groot-queue ya existe en $TARGET_SCRIPT${NC}"
    read -p "¿Reemplazarlo? (y/N): " -n 1 -r
    printf '\n'
    if [[ ! $REPLY =~ ^[YySs]$ ]]; then
        printf '%b\n' "${YELLOW}Instalación cancelada.${NC}"
        exit 0
    fi
    publish_wrapper
else
    publish_wrapper
fi

if [ ! -f "$TARGET_SCRIPT" ] || [ -L "$TARGET_SCRIPT" ] || [ ! -x "$TARGET_SCRIPT" ]; then
    printf '%b\n' "${RED}✗ Error: no se pudo verificar el launcher instalado.${NC}" >&2
    exit 1
fi

printf '%b\n\n' "${GREEN}✓ run-groot-queue instalado → $TARGET_SCRIPT${NC}"

if [[ ":$PATH:" != *":$INSTALL_DIRECTORY:"* ]]; then
    printf '%b\n' "${YELLOW}⚠ $INSTALL_DIRECTORY no está en tu PATH${NC}"
    printf '%b\n\n' "  Agregá: ${GREEN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
fi

printf '%b\n' "${BLUE}El instalador gestiona solo el wrapper del launcher; no instala plugins, MCPs ni dependencias.${NC}"
printf '%b\n' "${BLUE}Ejecutá run-groot-queue --help para ver comandos y opciones.${NC}"
