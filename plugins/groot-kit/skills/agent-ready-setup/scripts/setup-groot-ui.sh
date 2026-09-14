#!/usr/bin/env bash
# Installs the latest groot-ui package and configures frontend helper scripts.

set -euo pipefail

readonly GROOT_UI_PACKAGE_SPEC="groot-ui@latest"
readonly I18N_SCRIPT_NAME="i18n"
readonly I18N_SCRIPT_COMMAND="groot-i18n"
readonly LOCAL_TO_PRODUCTION_SCRIPT_NAME="local2prod"
readonly LOCAL_TO_PRODUCTION_SCRIPT_COMMAND="groot-config-sync"
readonly OBSOLETE_SCRIPT_NAMES_JSON='["i18n:gettext","i18n:upload","generate-po.zip","upload-translations","clean-locales"]'
readonly OBSOLETE_DEPENDENCY_NAMES_JSON='["kraken-translations"]'

package_json="${1:-package.json}"

if [[ $# -gt 1 ]]; then
  printf 'ERROR: usage: %s [package.json path]\n' "$0" >&2
  exit 1
fi

if [[ ! -e "$package_json" ]]; then
  printf '[groot-ui] %s was not found; installation skipped.\n' "$package_json"
  exit 0
fi

if [[ -L "$package_json" ]]; then
  printf 'ERROR: %s is a symlink; package configuration was not changed.\n' "$package_json" >&2
  exit 1
fi

if [[ ! -f "$package_json" ]]; then
  printf 'ERROR: %s is not a regular file; package configuration was not changed.\n' "$package_json" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  printf 'ERROR: npm is required to install %s.\n' "$GROOT_UI_PACKAGE_SPEC" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  printf 'ERROR: node is required to configure %s.\n' "$package_json" >&2
  exit 1
fi

node - "$package_json" \
  "$I18N_SCRIPT_NAME" \
  "$I18N_SCRIPT_COMMAND" \
  "$LOCAL_TO_PRODUCTION_SCRIPT_NAME" \
  "$LOCAL_TO_PRODUCTION_SCRIPT_COMMAND" \
  "$OBSOLETE_SCRIPT_NAMES_JSON" \
  "$OBSOLETE_DEPENDENCY_NAMES_JSON" <<'NODE'
const fs = require('fs');
const path = require('path');

const [
  packagePath,
  i18nScriptName,
  i18nScriptCommand,
  localToProductionScriptName,
  localToProductionScriptCommand,
  obsoleteScriptNamesJson,
  obsoleteDependencyNamesJson,
] = process.argv.slice(2);
const obsoleteScriptNames = JSON.parse(obsoleteScriptNamesJson);
const obsoleteDependencyNames = JSON.parse(obsoleteDependencyNamesJson);
const dependencySections = [
  'dependencies',
  'devDependencies',
  'optionalDependencies',
  'peerDependencies',
];
let packageJson;

try {
  packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
} catch (error) {
  throw new Error(`could not parse ${packagePath}: ${error.message}`);
}

if (!packageJson || typeof packageJson !== 'object' || Array.isArray(packageJson)) {
  throw new Error(`${packagePath} must contain a JSON object`);
}

if (packageJson.scripts === undefined) {
  packageJson.scripts = {};
} else if (!packageJson.scripts || typeof packageJson.scripts !== 'object' || Array.isArray(packageJson.scripts)) {
  throw new Error(`${packagePath}.scripts must be a JSON object`);
}

for (const scriptName of obsoleteScriptNames) {
  delete packageJson.scripts[scriptName];
}
for (const dependencySection of dependencySections) {
  if (!packageJson[dependencySection] || typeof packageJson[dependencySection] !== 'object') {
    continue;
  }
  for (const dependencyName of obsoleteDependencyNames) {
    delete packageJson[dependencySection][dependencyName];
  }
}
packageJson.scripts[i18nScriptName] = i18nScriptCommand;
packageJson.scripts[localToProductionScriptName] = localToProductionScriptCommand;

const packageDirectory = path.dirname(packagePath);
const temporaryPackagePath = path.join(
  packageDirectory,
  `.${path.basename(packagePath)}.agent-ready-groot-ui-${process.pid}`,
);
const packageMode = fs.statSync(packagePath).mode & 0o777;

try {
  fs.writeFileSync(temporaryPackagePath, `${JSON.stringify(packageJson, null, 2)}\n`, { mode: packageMode });
  fs.chmodSync(temporaryPackagePath, packageMode);
  fs.renameSync(temporaryPackagePath, packagePath);
} catch (error) {
  fs.rmSync(temporaryPackagePath, { force: true });
  throw new Error(`could not update ${packagePath}: ${error.message}`);
}
NODE

printf '[groot-ui] Installing %s...\n' "$GROOT_UI_PACKAGE_SPEC"
npm install --save "$GROOT_UI_PACKAGE_SPEC"

printf '[groot-ui] Configured %s, %s, and %s.\n' \
  "$GROOT_UI_PACKAGE_SPEC" \
  "$I18N_SCRIPT_NAME" \
  "$LOCAL_TO_PRODUCTION_SCRIPT_NAME"
